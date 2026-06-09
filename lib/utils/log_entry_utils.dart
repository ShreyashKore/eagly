import '../features/logs/data/models/log_column.dart';
import '../features/logs/data/models/log_entry.dart';
import 'timestamp_utils.dart';

enum LogCopyFormat { messageOnly, timestampAndMessage, fullLine }

final class LogEntryUtils {
  static LogEntry buildSpecial({
    required LogEntryType type,
    required String message,
    String? timestamp,
    String tag = 'eagly',
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

  static LogEntry buildLoggingState({
    required LogEntryType type,
    String? message,
    String tag = 'eagly',
    String? packageName,
    String? processName,
    String? timestamp,
  }) {
    return buildSpecial(
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

  static LogEntry buildToolError({
    required String message,
    required String tag,
    required String processName,
  }) {
    return buildLoggingState(
      type: LogEntryType.error,
      tag: tag,
      message: message,
      packageName: processName,
      processName: processName,
    );
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

extension LogEntryCollectionExt on Iterable<LogEntry> {
  String formatForCopy(LogCopyFormat format) {
    return map((entry) => entry.formatForCopy(format)).join('\n');
  }
}

extension LogEntryExt on LogEntry {
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

  String valueForColumn(LogColumn column, {bool isIos = false}) =>
      switch (column) {
        LogColumn.timestamp => timestamp,
        // iOS: packageName holds the compact process name ("novio", "runningboardd").
        // Android: packageName is the resolved package name, or PID as fallback.
        LogColumn.pid => packageName ?? processName ?? pid,
        // iOS has no thread ID in syslog output (stored as '0'); show PID instead.
        // Android: combined "PID/TID" so both are visible in one cell.
        LogColumn.tid => isIos ? pid : '$pid/$tid',
        LogColumn.level => isSpecialEntry ? typeLabel : level,
        LogColumn.tag => tag,
        LogColumn.message => message,
      };

  String formatForCopy(LogCopyFormat format) {
    return switch (format) {
      LogCopyFormat.messageOnly => message,
      LogCopyFormat.timestampAndMessage => '$timestamp $message',
      LogCopyFormat.fullLine =>
        '$timestamp ${packageName ?? pid} $tid $level $tag: $message',
    };
  }
}
