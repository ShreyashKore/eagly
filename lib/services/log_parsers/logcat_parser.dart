import '../../data/log_entry.dart';
import '../../data/log_level.dart';
import '../../utils/log_entry_utils.dart';

/// Parses `adb logcat -v threadtime` output into [LogEntry] objects.
///
/// Logcat emits one self-contained entry per line, so this parser is
/// stateless: each line maps to at most one entry and nothing is buffered
/// between calls.
class LogcatParser {
  const LogcatParser();

  LogEntry? parse(String line) {
    return _parseFromLogcat(line);
  }
}

final RegExp _logcatSectionSeparatorRegex = RegExp(
  r'^-+\s+(beginning of|switch to)\s+(.+?)\s*$',
  caseSensitive: false,
);

LogEntry? _parseFromLogcat(String line) {
  final separatorMatch = _logcatSectionSeparatorRegex.firstMatch(line);
  if (separatorMatch != null) {
    final prefix = separatorMatch.group(1)!.toLowerCase();
    final section = separatorMatch.group(2)!.trim();
    final message = switch (prefix) {
      'beginning of' => 'Beginning of $section',
      'switch to' => 'Switched to $section',
      _ => line.trim(),
    };

    return LogEntryUtils.buildSpecial(
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
