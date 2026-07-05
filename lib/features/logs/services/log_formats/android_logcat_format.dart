import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../../data/device.dart';
import '../../data/models/log_entry.dart';
import '../../data/models/log_level.dart';
import '../../../../utils/timestamp_utils.dart';
import '../../../../utils/utils.dart';
import 'log_format.dart';

/// Android Studio / `adb logcat` JSON export format.
///
/// File structure:
/// ```json
/// {
///   "metadata": { "device": …, "exportedAt": …, "totalLogs": … },
///   "logcatMessages": [ { "header": { … }, "message": "…" }, … ]
/// }
/// ```
class AndroidLogcatFormat extends LogFormat {
  const AndroidLogcatFormat();

  @override
  LogFormatId get id => LogFormatId.androidLogcat;

  @override
  LogFormatExportResult export(List<LogEntry> entries, {Device? device}) {
    final exportData = {
      'metadata': {
        'device': {
          'physicalDevice': device != null
              ? {'serialNumber': device.id, 'status': device.status}
              : null,
        },
        'exportedAt': DateTime.now().toIso8601String(),
        'totalLogs': entries.length,
      },
      'logcatMessages': entries.map(_entryToMap).toList(),
    };

    final content = const JsonEncoder.withIndent('  ').convert(exportData);
    final suggestedFileName =
        'logcat_export_${DateTime.now().millisecondsSinceEpoch}.json';

    return LogFormatExportResult(
      content: content,
      suggestedFileName: suggestedFileName,
    );
  }

  /// Serialises a single [LogEntry] to the Android Studio JSON map format.
  /// Never add any new keys to the map; as Android Studio will not import them.
  /// Only use the keys that are already present in the exported files.
  Map<String, dynamic> _entryToMap(LogEntry entry) {
    final timestampObj = TimestampUtils.parseTimestampToSecondsNanos(
      entry.timestamp,
    );
    return {
      'header': {
        'logLevel': _exportLevel(entry.level),
        'pid': int.tryParse(entry.pid) ?? 0,
        'tid': int.tryParse(entry.tid) ?? 0,
        'tag': entry.tag,
        'applicationId': entry.packageName ?? entry.pid,
        'processName': entry.processName ?? entry.pid,
        'timestamp': timestampObj,
      },
      'message': entry.message,
    };
  }

  @override
  LogFormatParseResult parse(String content) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      throw const FormatException('File is not valid JSON.');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid log export format.');
    }

    final logcatMessages = decoded['logcatMessages'] as List<dynamic>?;
    if (logcatMessages == null) {
      throw const FormatException('Missing logcatMessages array.');
    }

    final logs = <LogEntry>[];
    for (final msg in logcatMessages) {
      if (msg is! Map<String, dynamic>) continue;
      final entry = _entryFromMap(msg);
      if (entry != null) logs.add(entry);
    }

    return LogFormatParseResult(logs: logs);
  }

  /// Deserialises a single Android Studio JSON map entry back to [LogEntry].
  LogEntry? _entryFromMap(Map<String, dynamic> map) {
    try {
      final header = map['header'] as Map<String, dynamic>?;
      if (header == null) {
        throw const FormatException('Missing header in log entry');
      }

      final type = _logEntryTypeFromString(header['entryType']?.toString());
      final rawLevel = header['logLevel']?.toString() ?? '';
      final level = _resolveLevel(rawLevel);
      final pid = header['pid']?.toString() ?? '0';
      final tid = header['tid']?.toString() ?? '0';
      final tag = header['tag']?.toString() ?? '';
      final applicationId = header['applicationId']?.toString() ?? '';
      final processName = header['processName']?.toString() ?? '';

      String timestamp = '';
      final timestampData = header['timestamp'];
      if (timestampData is Map) {
        final seconds = parseIntOrZero(timestampData['seconds']);
        final nanos = parseIntOrZero(timestampData['nanos']);
        timestamp = TimestampUtils.formatTimestamp(seconds, nanos);
      } else if (timestampData is String) {
        timestamp = timestampData;
      }

      final message = map['message']?.toString() ?? '';

      return LogEntry(
        type: type,
        timestamp: timestamp,
        pid: pid,
        tid: tid,
        level: level,
        tag: tag,
        packageName: applicationId,
        processName: processName,
        message: message,
        platform: DevicePlatform.android,
      );
    } catch (error) {
      debugPrint('Error parsing log entry from exported map: $error');
      return null;
    }
  }

  static LogEntryType _logEntryTypeFromString(String? raw) {
    return LogEntryType.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => LogEntryType.log,
    );
  }

  /// Resolves a serialised level string back to the stored level code.
  ///
  /// Handles three formats produced across versions:
  ///  - Legacy Android full name: `'ERROR'` → `'E'`
  ///  - Android single-char code: `'E'` → `'E'`
  ///  - iOS os_log code:           `'fault'` → `'fault'`
  static String _resolveLevel(String raw) {
    if (raw.isEmpty) return LogLevel.verbose.androidCode;

    final androidLevel = LogLevel.normalizeAndroidStoredLevel(raw);
    if (androidLevel != raw.trim() ||
        LogLevel.fromAndroidCode(raw).code != raw) {
      return androidLevel;
    }

    return LogLevel.normalizeIosStoredLevel(raw);
  }

  static String _exportLevel(String level) {
    final trimmed = level.trim();
    if (trimmed.length == 1) {
      final logLevel = LogLevel.fromStored(trimmed);
      if (!logLevel.isUnknown) return logLevel.androidExportName;
    }
    return trimmed;
  }
}
