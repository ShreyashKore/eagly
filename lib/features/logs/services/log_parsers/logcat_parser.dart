import '../../data/models/log_entry.dart';
import '../../data/models/log_level.dart';
import '../../../../utils/log_entry_utils.dart';
import 'log_line_parser.dart';

/// Parses `adb logcat -v long` output into [LogEntry] objects.
///
/// `-v long` prints each entry as a bracketed header line followed by the
/// message verbatim — embedded newlines included — and a blank footer line:
///
/// ```text
/// [ 09-26 20:46:04.996 32036:32036 D/EaglyML  ]
/// line one
/// line two
///
/// ```
///
/// (`-v threadtime` instead repeats the header on every line of a multi-line
/// message, and one message can't be told apart from two logged by the same
/// thread in the same millisecond.) A message may itself contain blank lines,
/// so an entry is only known to be complete when the next header or section
/// separator arrives — see [LogLineParser].
class LogcatParser implements LogLineParser {
  _LogcatEntryBuilder? _currentEntry;

  @override
  List<LogEntry> addLine(String line) {
    final separator = _parseSectionSeparator(line);
    if (separator != null) return [?flush(), separator];

    final header = _LogcatEntryBuilder.tryParse(line);
    if (header != null) {
      final previousEntry = flush();
      _currentEntry = header;
      return [?previousEntry];
    }

    _currentEntry?.appendLine(line);
    return const [];
  }

  @override
  LogEntry? flush() {
    final entry = _currentEntry?.build();
    _currentEntry = null;
    return entry;
  }
}

final RegExp _logcatSectionSeparatorRegex = RegExp(
  r'^-+\s+(beginning of|switch to)\s+(.+?)\s*$',
  caseSensitive: false,
);

final RegExp _logcatHeaderRegex = RegExp(
  r'^\[\s+(\d\d-\d\d\s+\d\d:\d\d:\d\d\.\d+)\s+(\d+):\s*(\d+)\s+([VDIWEF])/(.*?)\s*\]$',
);

LogEntry? _parseSectionSeparator(String line) {
  final separatorMatch = _logcatSectionSeparatorRegex.firstMatch(line);
  if (separatorMatch == null) return null;

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

class _LogcatEntryBuilder {
  _LogcatEntryBuilder({
    required this.timestamp,
    required this.pid,
    required this.tid,
    required this.level,
    required this.tag,
  });

  final String timestamp;
  final String pid;
  final String tid;
  final String level;
  final String tag;
  final List<String> _lines = [];

  static _LogcatEntryBuilder? tryParse(String line) {
    final match = _logcatHeaderRegex.firstMatch(line);
    if (match == null) return null;

    return _LogcatEntryBuilder(
      timestamp: match.group(1)!,
      pid: match.group(2)!,
      tid: match.group(3)!,
      level: match.group(4)!,
      tag: match.group(5)!.trim(),
    );
  }

  void appendLine(String line) => _lines.add(line);

  LogEntry build() {
    // Drop the blank footer line (and any trailing newlines of the message
    // itself, which the header-per-line format never showed either).
    var end = _lines.length;
    while (end > 0 && _lines[end - 1].isEmpty) {
      end--;
    }

    return LogEntry(
      timestamp: timestamp,
      pid: pid,
      tid: tid,
      level: level,
      tag: tag,
      message: _lines.sublist(0, end).join('\n'),
    );
  }
}
