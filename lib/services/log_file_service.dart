import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../data/device.dart';
import '../data/log_entry.dart';
import '../utils/log_utils.dart';
import '../utils/timestamp_utils.dart';

class LogFileService {
  /// Export logs to JSON file in Android Studio logcat format
  static Future<void> exportLogs(List<LogEntry> logs, Device? device) async {
    if (logs.isEmpty) return;

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Logs',
      fileName: 'logcat_export_${DateTime.now().millisecondsSinceEpoch}.json',
      allowedExtensions: ['json'],
      type: FileType.custom,
    );

    if (result == null) return;

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
  }

  /// Import logs from JSON file
  static Future<List<LogEntry>?> importLogs() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import Logcat File',
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return null;

    final filePath = result.files.first.path;
    if (filePath == null) return null;

    try {
      final file = File(filePath);
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final logcatMessages = data['logcatMessages'] as List<dynamic>?;
      if (logcatMessages == null) return null;

      final importedLogs = <LogEntry>[];
      for (final msg in logcatMessages) {
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
          final seconds = timestampData['seconds'] as int? ?? 0;
          final nanos = timestampData['nanos'] as int? ?? 0;
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

      return importedLogs;
    } catch (e) {
      return null;
    }
  }
}
