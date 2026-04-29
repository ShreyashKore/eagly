import 'package:flutter/foundation.dart';

import '../utils/log_utils.dart';
import '../utils/timestamp_utils.dart';

class LogEntry {
  final String timestamp;
  final String pid;
  final String tid;
  final String level;
  final String tag;
  final String message;
  final String lowercaseSearchable;
  String? packageName;
  String? processName;

  LogEntry({
    required this.timestamp,
    required this.pid,
    required this.tid,
    required this.level,
    required this.tag,
    required this.message,
    this.packageName,
    this.processName,
  }) : lowercaseSearchable = '$tag $message'.toLowerCase();

  @override
  String toString() {
    return 'LogEntry(timestamp: $timestamp, pid: $pid, tid: $tid, level: $level, tag: $tag, message: $message, packageName: $packageName, processName: $processName)';
  }

  @override
  int get hashCode {
    return Object.hash(
      timestamp,
      pid,
      tid,
      level,
      tag,
      message,
      packageName,
      processName,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LogEntry &&
        other.timestamp == timestamp &&
        other.pid == pid &&
        other.tid == tid &&
        other.level == level &&
        other.tag == tag &&
        other.message == message &&
        other.packageName == packageName &&
        other.processName == processName;
  }

  static LogEntry? parseFromLogcat(String line) {
    final regex = RegExp(
      r'^(\d\d-\d\d\s+\d\d:\d\d:\d\d\.\d+)\s+(\d+)\s+(\d+)\s+([VDIWEF])\s+([^:]+):\s+(.*)',
    );

    final match = regex.firstMatch(line);
    if (match == null) return null;

    return LogEntry(
      timestamp: match.group(1)!,
      pid: match.group(2)!,
      tid: match.group(3)!,
      level: match.group(4)!,
      tag: match.group(5)!,
      message: match.group(6)!,
    );
  }

  Map<String, dynamic> toExportMap() {
    final timestampObj = TimestampUtils.parseTimestampToSecondsNanos(timestamp);
    return {
      'header': {
        'logLevel': LogUtils.logLevelName(level),
        'pid': int.tryParse(pid) ?? 0,
        'tid': int.tryParse(tid) ?? 0,
        'tag': tag,
        'applicationId': packageName,
        'processName': processName,
        'timestamp': timestampObj,
      },
      'message': message,
    };
  }

  static LogEntry? fromExportedMap(Map<String, dynamic> map) {
    try {
      final header = map['header'] as Map<String, dynamic>?;
      if (header == null) throw FormatException('Missing header in log entry');

      final level = LogUtils.logLevelFromName(
        header['logLevel']?.toString() ?? 'V',
      );
      final pid = header['pid']?.toString() ?? '0';
      final tid = header['tid']?.toString() ?? '0';
      final tag = header['tag']?.toString() ?? '';
      final applicationId = header['applicationId']?.toString() ?? '';
      final processName = header['processName']?.toString() ?? '';

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

      final message = map['message']?.toString() ?? '';

      return LogEntry(
        timestamp: timestamp,
        pid: pid,
        tid: tid,
        level: level,
        tag: tag,
        packageName: applicationId,
        processName: processName,
        message: message,
      );
    } catch (e) {
      debugPrint('Error parsing log entry from exported map: $e');
      return null;
    }
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
