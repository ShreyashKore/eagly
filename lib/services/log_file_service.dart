import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../data/device.dart';
import '../data/log_entry.dart';
import '../utils/log_utils.dart';
import '../utils/timestamp_utils.dart';

class LogExportResult {
  const LogExportResult({
    this.fileName,
    this.error,
    this.cancelled = false,
  });

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
  /// Export logs to JSON file in Android Studio logcat format
  static Future<LogExportResult> exportLogs(List<LogEntry> logs, Device? device) async {
    if (logs.isEmpty) {
      return LogExportResult.failure(error: 'No logs available to export.');
    }

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Logs',
      fileName: 'logcat_export_${DateTime.now().millisecondsSinceEpoch}.json',
      allowedExtensions: ['json'],
      type: FileType.custom,
    );

    if (result == null) return LogExportResult.cancelled();

    final fileName = _extractFileName(result);

    try {
      final exportData = {
        'metadata': {
          'device': device != null
              ? {
                  'serialNumber': device.id,
                  'status': device.status,
                }
              : null,
          'exportedAt': DateTime.now().toIso8601String(),
          'totalLogs': logs.length,
        },
        'logcatMessages': logs.map((log) {
          final timestampObj = TimestampUtils.parseTimestampToSecondsNanos(log.timestamp);

          return {
            'header': {
              'logLevel': LogUtils.logLevelName(log.level),
              'pid': int.tryParse(log.pid) ?? 0,
              'tid': int.tryParse(log.tid) ?? 0,
              'tag': log.tag,
              'timestamp': timestampObj,
            },
            'message': log.message,
          };
        }).toList(),
      };

      final file = File(result);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(exportData));
      return LogExportResult.success(fileName: fileName);
    } catch (e) {
      return LogExportResult.failure(
        fileName: fileName,
        error: 'Failed to export logs to "$fileName": ${_describeError(e)}',
      );
    }
  }

  /// Import logs from JSON file
  static Future<LogImportResult> importLogs() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import Logcat File',
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return LogImportResult.cancelled();

    final pickedFile = result.files.first;
    final filePath = pickedFile.path;
    final fileName = pickedFile.name.isNotEmpty
        ? pickedFile.name
        : (filePath == null ? 'Imported file' : _extractFileName(filePath));
    if (filePath == null) {
      return LogImportResult.failure(
        fileName: fileName,
        error: 'Failed to import "$fileName": The selected file could not be accessed.',
      );
    }

    try {
      final file = File(filePath);
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        return LogImportResult.failure(
          fileName: fileName,
          error: 'Failed to import "$fileName": Invalid log export format.',
        );
      }
      final data = decoded;

      final logcatMessages = data['logcatMessages'] as List<dynamic>?;
      if (logcatMessages == null) {
        return LogImportResult.failure(
          fileName: fileName,
          error: 'Failed to import "$fileName": Missing logcatMessages array.',
        );
      }

      final importedLogs = <LogEntry>[];
      for (final msg in logcatMessages) {
        if (msg is! Map<String, dynamic>) continue;

        final header = msg['header'] as Map<String, dynamic>?;
        if (header == null) continue;

        final level = LogUtils.logLevelFromName(header['logLevel']?.toString() ?? 'V');
        final pid = header['pid']?.toString() ?? '0';
        final tid = header['tid']?.toString() ?? '0';
        final tag = header['tag']?.toString() ?? '';

        // Convert timestamp from JSON format
        String timestamp = '';
        final timestampData = header['timestamp'];
        if (timestampData is Map) {
          // Format: {seconds: 1774431614, nanos: 314000000}
          final seconds = _parseInt(timestampData['seconds']);
          final nanos = _parseInt(timestampData['nanos']);
          timestamp = TimestampUtils.formatTimestamp(seconds, nanos);
        } else if (timestampData is String) {
          // Already a string, use as-is
          timestamp = timestampData;
        }

        final message = msg['message']?.toString() ?? '';

        importedLogs.add(LogEntry(
          timestamp: timestamp,
          pid: pid,
          tid: tid,
          level: level,
          tag: tag,
          message: message,
        ));
      }

      return LogImportResult.success(logs: importedLogs, fileName: fileName);
    } catch (e) {
      return LogImportResult.failure(
        fileName: fileName,
        error: 'Failed to import "$fileName": ${_describeError(e)}',
      );
    }
  }

  static String _extractFileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.isEmpty ? path : segments.last;
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _describeError(Object error) {
    if (error is FormatException) {
      return error.message;
    }

    final message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }
}
