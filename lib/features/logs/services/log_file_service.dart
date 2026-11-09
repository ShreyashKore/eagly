import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../../data/device.dart';
import '../data/models/log_column.dart';
import '../data/models/log_entry.dart';
import '../../../utils/log_entry_utils.dart';
import '../../../utils/timestamp_utils.dart';
import '../../../utils/utils.dart';
import 'log_formats/log_formats.dart';
import '../../../services/preferences_service.dart';
import '../../../utils/file_dialog_directory.dart';

/// Which entries an export writes.
enum LogExportScope(
  /// Label in the export dialog.
  final String label,

  /// Added to the suggested file name, so an excerpt isn't mistaken for the
  /// whole capture later.
  final String? fileNameSuffix,
) {
  all('All logs', null),
  filtered('Matching the current filters', 'filtered'),
  selected('Selected rows', 'selected'),
}

/// The file layout an export writes.
enum LogExportFormat(
  /// Label in the export dialog.
  final String label,

  /// One line on what the format is good for.
  final String description,

  /// Extensions the save dialog offers; the first is the suggested one.
  final List<String> fileExtensions,
) {
  androidStudio(
    'Android Studio JSON',
    'Opens in Android Studio\'s Logcat and imports back into Eagly.',
    ['json', 'logcat'],
  ),
  plainText(
    'Plain text',
    'One line per entry, as Copy writes them. For grep, diffs and bug '
        'reports; Eagly can\'t import it back.',
    ['txt', 'log'],
  );

  /// The format named [name] (an [Enum.name]), or [androidStudio].
  static LogExportFormat fromName(String? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => androidStudio);
}

class const LogExportResult({
  final String? fileName,

  /// Absolute path of the written file, on success.
  final String? path,
  final String? error,
  final bool cancelled = false,
}) {
  bool get isSuccess => !cancelled && error == null;

  factory LogExportResult.success({
    required String fileName,
    required String path,
  }) {
    return LogExportResult(fileName: fileName, path: path);
  }

  factory LogExportResult.failure({String? fileName, required String error}) {
    return LogExportResult(fileName: fileName, error: error);
  }

  factory LogExportResult.cancelled() {
    return const LogExportResult(cancelled: true);
  }
}

class const LogImportResult({
  final List<LogEntry>? logs,
  final String? fileName,

  /// Absolute path of the imported file, when known. Used to record the file
  /// in the recent-files list for quick re-open.
  final String? filePath,
  final String? error,
  final bool cancelled = false,
}) {
  bool get isSuccess => !cancelled && error == null && logs != null;

  factory LogImportResult.success({
    required List<LogEntry> logs,
    required String fileName,
    String? filePath,
  }) {
    return LogImportResult(logs: logs, fileName: fileName, filePath: filePath);
  }

  factory LogImportResult.failure({String? fileName, required String error}) {
    return LogImportResult(fileName: fileName, error: error);
  }

  factory LogImportResult.cancelled() {
    return const LogImportResult(cancelled: true);
  }
}

class LogFileService {
  /// The default format used when none is supplied explicitly.
  static const LogFormat defaultFormat = AndroidLogcatFormat();

  /// Export [logs] (the [scope] of [device]'s capture) to a file in
  /// [format].
  ///
  /// A plain-text export writes only [columns] when given (see
  /// [LogEntryExt.formatColumns]), and the full line otherwise. [isIos] picks
  /// how iOS cells read. The JSON layout always carries every field.
  ///
  /// Serialises [logs] first, then opens a system save-file dialog and writes
  /// the content, so entries arriving while the dialog is open aren't
  /// included.
  static Future<LogExportResult> exportLogs(
    List<LogEntry> logs,
    Device? device, {
    LogExportFormat format = LogExportFormat.androidStudio,
    LogExportScope scope = LogExportScope.all,
    Set<LogColumn>? columns,
    bool isIos = false,
  }) async {
    if (logs.isEmpty) {
      return LogExportResult.failure(error: 'No logs available to export.');
    }

    final initialDirectory = FileDialogDirectory.initial();

    final content = switch (format) {
      LogExportFormat.androidStudio =>
        defaultFormat.export(logs, device: device).content,
      LogExportFormat.plainText =>
        columns == null
            ? '${logs.formatForCopy(LogCopyFormat.fullLine)}\n'
            : '${logs.map((e) => e.formatColumns(columns, isIos: isIos)).join('\n')}\n',
    };

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Logs',
      fileName: suggestedExportFileName(
        device: device,
        format: format,
        scope: scope,
        time: DateTime.now(),
      ),
      allowedExtensions: format.fileExtensions,
      initialDirectory: initialDirectory,
      type: FileType.custom,
    );

    if (result == null) return LogExportResult.cancelled();

    final fileName = extractFileName(result);

    try {
      await File(result).writeAsString(content);
      await FileDialogDirectory.rememberParentOf(result);
      return LogExportResult.success(fileName: fileName, path: result);
    } catch (e) {
      return LogExportResult.failure(
        fileName: fileName,
        error: 'Failed to export logs to "$fileName": ${describeError(e)}',
      );
    }
  }

  /// `<device>-logs[-filtered|-selected]-<timestamp>.<ext>`, with the device
  /// name reduced to characters every file system accepts.
  static String suggestedExportFileName({
    required Device? device,
    required LogExportFormat format,
    required LogExportScope scope,
    required DateTime time,
  }) {
    final deviceName = (device?.displayName ?? '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stem = [
      if (deviceName.isNotEmpty) deviceName,
      'logs',
      ?scope.fileNameSuffix,
      fileNameTimestamp(time),
    ].join('-');
    return '$stem.${format.fileExtensions.first}';
  }

  /// Import logs from a file using [format] (defaults to [defaultFormat]).
  ///
  /// When [path] is supplied the picker is skipped and the file is read
  /// directly (used to re-open a recent file). Otherwise a system file-picker
  /// dialog is shown. The file is read and parsing is delegated to [format].
  /// On success the file is recorded in the recent-files list.
  static Future<LogImportResult> importLogs({
    LogFormat format = defaultFormat,
    String? path,
  }) async {
    final String filePath;
    final String fileName;

    if (path != null) {
      filePath = path;
      fileName = extractFileName(path);
    } else {
      final initialDirectory = FileDialogDirectory.initial();

      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Import Logcat File',
        initialDirectory: initialDirectory,
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty) {
        return LogImportResult.cancelled();
      }

      final pickedFile = result.files.first;
      final pickedPath = pickedFile.path;
      final pickedName = pickedFile.name.isNotEmpty
          ? pickedFile.name
          : (pickedPath == null
                ? 'Imported file'
                : extractFileName(pickedPath));

      if (pickedPath == null) {
        return LogImportResult.failure(
          fileName: pickedName,
          error:
              'Failed to import "$pickedName": The selected file could not be accessed.',
        );
      }

      filePath = pickedPath;
      fileName = pickedName;
    }

    try {
      await FileDialogDirectory.rememberParentOf(filePath);

      final content = await File(filePath).readAsString();
      final parseResult = format.parse(content);

      await PreferencesService.addRecentLogFile(filePath);

      return LogImportResult.success(
        logs: parseResult.logs,
        fileName: fileName,
        filePath: filePath,
      );
    } on FormatException catch (e) {
      return LogImportResult.failure(
        fileName: fileName,
        error: 'Failed to import "$fileName": ${e.message}',
      );
    } catch (e) {
      return LogImportResult.failure(
        fileName: fileName,
        error: 'Failed to import "$fileName": ${describeError(e)}',
      );
    }
  }
}
