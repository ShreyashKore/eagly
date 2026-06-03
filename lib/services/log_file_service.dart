import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../data/device.dart';
import '../data/log_entry.dart';
import '../utils/utils.dart';
import 'log_formats/log_formats.dart';
import 'preferences_service.dart';

class LogExportResult {
  const LogExportResult({this.fileName, this.error, this.cancelled = false});

  final String? fileName;
  final String? error;
  final bool cancelled;

  bool get isSuccess => !cancelled && error == null;

  factory LogExportResult.success({required String fileName}) {
    return LogExportResult(fileName: fileName);
  }

  factory LogExportResult.failure({String? fileName, required String error}) {
    return LogExportResult(fileName: fileName, error: error);
  }

  factory LogExportResult.cancelled() {
    return const LogExportResult(cancelled: true);
  }
}

class LogImportResult {
  const LogImportResult({
    this.logs,
    this.fileName,
    this.error,
    this.cancelled = false,
  });

  final List<LogEntry>? logs;
  final String? fileName;
  final String? error;
  final bool cancelled;

  bool get isSuccess => !cancelled && error == null && logs != null;

  factory LogImportResult.success({
    required List<LogEntry> logs,
    required String fileName,
  }) {
    return LogImportResult(logs: logs, fileName: fileName);
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

  /// Export [logs] to a file using [format] (defaults to [defaultFormat]).
  ///
  /// Opens a system save-file dialog and writes the serialised content.
  static Future<LogExportResult> exportLogs(
    List<LogEntry> logs,
    Device? device, {
    LogFormat format = defaultFormat,
  }) async {
    if (logs.isEmpty) {
      return LogExportResult.failure(error: 'No logs available to export.');
    }

    final initialDirectory = await _resolveInitialDirectory();

    final exported = format.export(logs, device: device);

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Logs',
      fileName: exported.suggestedFileName,
      allowedExtensions: format.id.fileExtensions,
      initialDirectory: initialDirectory,
      type: FileType.custom,
    );

    if (result == null) return LogExportResult.cancelled();

    final fileName = extractFileName(result);

    try {
      await File(result).writeAsString(exported.content);
      await _rememberDialogDirectoryFromPath(result);
      return LogExportResult.success(fileName: fileName);
    } catch (e) {
      return LogExportResult.failure(
        fileName: fileName,
        error: 'Failed to export logs to "$fileName": ${describeError(e)}',
      );
    }
  }

  /// Import logs from a file using [format] (defaults to [defaultFormat]).
  ///
  /// Opens a system file-picker dialog, reads the file, and delegates
  /// parsing to [format].
  static Future<LogImportResult> importLogs({
    LogFormat format = defaultFormat,
  }) async {
    final initialDirectory = await _resolveInitialDirectory();

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import Logcat File',
      initialDirectory: initialDirectory,
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) {
      return LogImportResult.cancelled();
    }

    final pickedFile = result.files.first;
    final filePath = pickedFile.path;
    final fileName = pickedFile.name.isNotEmpty
        ? pickedFile.name
        : (filePath == null ? 'Imported file' : extractFileName(filePath));

    if (filePath == null) {
      return LogImportResult.failure(
        fileName: fileName,
        error:
            'Failed to import "$fileName": The selected file could not be accessed.',
      );
    }

    try {
      await _rememberDialogDirectoryFromPath(filePath);

      final content = await File(filePath).readAsString();
      final parseResult = format.parse(content);

      return LogImportResult.success(
        logs: parseResult.logs,
        fileName: fileName,
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

  static Future<String?> _resolveInitialDirectory() async {
    if (!_supportsInitialDirectory) {
      return null;
    }

    final rememberedDirectory = PreferencesService.lastFileDialogDirectory;
    if (_isUsableInitialDirectory(rememberedDirectory)) {
      return rememberedDirectory;
    }

    for (final candidate in _defaultInitialDirectoryCandidates()) {
      if (_isUsableInitialDirectory(candidate)) {
        return candidate;
      }
    }

    return null;
  }

  static Future<void> _rememberDialogDirectoryFromPath(String path) async {
    final directoryPath = File(path).parent.path;
    if (!_isUsableInitialDirectory(directoryPath)) {
      return;
    }

    await PreferencesService.setLastFileDialogDirectory(directoryPath);
  }

  static Iterable<String> _defaultInitialDirectoryCandidates() sync* {
    final homeDirectory = _userHomeDirectory;
    if (homeDirectory == null || homeDirectory.isEmpty) {
      return;
    }

    yield '$homeDirectory${Platform.pathSeparator}Downloads';
    yield '$homeDirectory${Platform.pathSeparator}Documents';
    yield homeDirectory;
  }

  static bool _isUsableInitialDirectory(String? path) {
    if (path == null || path.isEmpty) {
      return false;
    }

    final directory = Directory(path);
    return directory.isAbsolute && directory.existsSync();
  }

  static bool get _supportsInitialDirectory =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  static String? get _userHomeDirectory {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return home;
    }

    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return userProfile;
    }

    final homeDrive = Platform.environment['HOMEDRIVE'];
    final homePath = Platform.environment['HOMEPATH'];
    if (homeDrive != null &&
        homeDrive.isNotEmpty &&
        homePath != null &&
        homePath.isNotEmpty) {
      return '$homeDrive$homePath';
    }

    return null;
  }
}
