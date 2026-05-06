import 'package:flutter/foundation.dart';

import '../utils/log_entry_id_generator.dart';
import '../utils/timestamp_utils.dart';
import 'log_column.dart';
import 'log_level.dart';

enum LogEntryType {
  log('Log'),
  started('Started'),
  resumed('Resumed'),
  paused('Paused'),
  stopped('Stopped'),
  error('Error occurred'),
  notice('Notice');

  const LogEntryType(this.label);

  final String label;

  bool get isSpecial => this != LogEntryType.log;

  static LogEntryType fromString(String? raw) {
    return LogEntryType.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => LogEntryType.log,
    );
  }
}

class LogEntry {
  final int id;
  final LogEntryType type;
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
    int? id,
    this.type = LogEntryType.log,
    required this.timestamp,
    required this.pid,
    required this.tid,
    required this.level,
    required this.tag,
    required this.message,
    this.packageName,
    this.processName,
  }) : id = _resolveId(id),
       lowercaseSearchable = [
         timestamp,
         pid,
         tid,
         level,
         tag,
         message,
         if (packageName != null && packageName.trim().isNotEmpty) packageName,
         if (processName != null && processName.trim().isNotEmpty) processName,
       ].join(' ').toLowerCase();

  factory LogEntry.special({
    required LogEntryType type,
    required String message,
    String? timestamp,
    String tag = 'logview',
    String level = 'I',
    String pid = '',
    String tid = '',
    String? packageName,
    String? processName,
  }) {
    assert(type != LogEntryType.log, 'Use the default constructor for logs.');
    return LogEntry(
      type: type,
      timestamp: timestamp ?? TimestampUtils.formatDate(DateTime.now()),
      pid: pid,
      tid: tid,
      level: level,
      tag: tag,
      message: message.trim(),
      packageName: packageName,
      processName: processName,
    );
  }

  factory LogEntry.loggingState({
    required LogEntryType type,
    String? message,
    String tag = 'logview',
    String? packageName,
    String? processName,
    String? timestamp,
  }) {
    return LogEntry.special(
      type: type,
      timestamp: timestamp,
      tag: tag,
      level: type == LogEntryType.error ? 'E' : 'I',
      message: (message == null || message.trim().isEmpty)
          ? _defaultMessageForType(type)
          : message.trim(),
      packageName: packageName,
      processName: processName,
    );
  }

  factory LogEntry.toolError({
    required String message,
    required String tag,
    required String processName,
  }) {
    return LogEntry.loggingState(
      type: LogEntryType.error,
      tag: tag,
      message: message,
      packageName: processName,
      processName: processName,
    );
  }

  bool get isSpecialEntry => type.isSpecial;

  bool get isActualLog => type == LogEntryType.log;

  bool get isUserSelectable => isActualLog;

  bool get isCopyable => isActualLog;

  String get typeLabel => type.label;

  String get specialSearchableText {
    return [
      type.label,
      timestamp,
      tag,
      packageName,
      processName,
      message,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
  }

  String valueForColumn(LogColumn column) => switch (column) {
    LogColumn.timestamp => timestamp,
    LogColumn.pid => packageName ?? processName ?? pid,
    LogColumn.tid => tid,
    LogColumn.level => isSpecialEntry ? typeLabel : level,
    LogColumn.tag => tag,
    LogColumn.message => message,
  };

  @override
  String toString() {
    return 'LogEntry(id: $id, type: ${type.name}, timestamp: $timestamp, pid: $pid, tid: $tid, level: $level, tag: $tag, message: $message, packageName: $packageName, processName: $processName)';
  }

  @override
  int get hashCode {
    return Object.hash(
      timestamp,
      type,
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
        other.type == type &&
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
        'entryType': type.name,
        'logLevel': level,
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

      // Support both legacy full names (ERROR/WARN/…) and current codes (E/W/…
      // for Android, fault/debug/… for iOS). Try Android name lookup first,
      // then fall back to treating the value as a literal code.
      final type = LogEntryType.fromString(header['entryType']?.toString());
      final rawLevel = header['logLevel']?.toString() ?? '';
      final level = _resolveLevel(rawLevel);
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
        type: type,
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

  /// Resolves a serialised level string back to the stored level code.
  ///
  /// Handles three formats produced across versions:
  ///  - Legacy Android full name: `'ERROR'` → `'E'`
  ///  - Android single-char code: `'E'` → `'E'`
  ///  - iOS os_log code:           `'fault'` → `'fault'`
  static String _resolveLevel(String raw) {
    if (raw.isEmpty) {
      return LogLevel.verbose.androidCode;
    }

    final androidLevel = LogLevel.normalizeAndroidStoredLevel(raw);
    if (androidLevel != raw.trim() ||
        LogLevel.fromAndroidCode(raw).code != raw) {
      return androidLevel;
    }

    final iosLevel = LogLevel.normalizeIosStoredLevel(raw);
    return iosLevel;
  }

  static int _resolveId(int? value) {
    if (value != null) {
      return value;
    }
    return LogEntryIdGenerator.instance.next();
  }

  static String _defaultMessageForType(LogEntryType type) {
    return switch (type) {
      LogEntryType.log => '',
      LogEntryType.started => 'Started capturing logs.',
      LogEntryType.resumed => 'Resumed live logging.',
      LogEntryType.paused => 'Paused live logging.',
      LogEntryType.stopped => 'Stopped capturing logs.',
      LogEntryType.error => 'A logging error occurred.',
      LogEntryType.notice => 'Logging state updated.',
    };
  }
}
