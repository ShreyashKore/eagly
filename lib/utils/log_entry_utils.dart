import '../data/log_column.dart';
import '../data/log_entry.dart';
import '../data/log_level.dart';
import 'timestamp_utils.dart';

enum LogCopyFormat { messageOnly, timestampAndMessage, fullLine }

final class LogEntryUtils {
  static final RegExp _logcatSectionSeparatorRegex = RegExp(
    r'^-+\s+(beginning of|switch to)\s+(.+?)\s*$',
    caseSensitive: false,
  );

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

  static LogEntry? parseFromLogcat(String line) {
    final separatorMatch = _logcatSectionSeparatorRegex.firstMatch(line);
    if (separatorMatch != null) {
      final prefix = separatorMatch.group(1)!.toLowerCase();
      final section = separatorMatch.group(2)!.trim();
      final message = switch (prefix) {
        'beginning of' => 'Beginning of $section',
        'switch to' => 'Switched to $section',
        _ => line.trim(),
      };

      return buildSpecial(
        type: LogEntryType.notice,
        timestamp: '',
        tag: 'adb logcat',
        level: LogLevel.info.androidCode,
        message: message,
        processName: section,
      );
    }

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
      tag: match.group(5)!.trim(),
      message: match.group(6)!,
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

  String valueForColumn(LogColumn column) => switch (column) {
    LogColumn.timestamp => timestamp,
    LogColumn.pid => packageName ?? processName ?? pid,
    LogColumn.tid => tid,
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