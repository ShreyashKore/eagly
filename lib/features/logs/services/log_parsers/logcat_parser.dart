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
/// separator arrives — see [LogLineParser]. The blank footer is still a strong
/// hint, which [pendingEntryStatus] reports.
class LogcatParser implements LogLineParser {
  _LogcatEntryBuilder? _currentEntry;

  /// The header of the entry [flush] last handed over, for body lines that
  /// turn up after it. Cleared by the next header or separator.
  _LogcatEntryBuilder? _flushedHeader;

  @override
  List<LogEntry> addLine(String line) {
    final separator = _parseSectionSeparator(line);
    if (separator != null) return [?_completeCurrent(), separator];

    final header = _LogcatEntryBuilder.tryParse(line);
    if (header != null) {
      final previousEntry = _completeCurrent();
      _currentEntry = header;
      return [?previousEntry];
    }

    final entry = _currentEntry ??= _flushedHeader?.resumed();
    entry?.appendLine(line);
    return const [];
  }

  @override
  LogEntry? flush() {
    final entry = _currentEntry;
    if (entry == null) return null;
    _currentEntry = null;
    _flushedHeader = entry;
    return entry.build();
  }

  @override
  PendingEntryStatus get pendingEntryStatus {
    final entry = _currentEntry;
    if (entry == null) return PendingEntryStatus.none;
    return entry.status;
  }

  /// Ends the current entry because a new header or separator arrived, which
  /// also ends any chance of late body lines belonging to a flushed one.
  LogEntry? _completeCurrent() {
    final entry = _currentEntry?.build();
    _currentEntry = null;
    _flushedHeader = null;
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

class _LogcatEntryBuilder({
  required this.timestamp,
  required this.pid,
  required this.tid,
  required this.level,
  required this.tag,
  this.isResumed = false,
}) {
  final String timestamp;
  final String pid;
  final String tid;
  final String level;
  final String tag;

  /// Whether this carries on an entry that was flushed before its end, and so
  /// holds the rest of its lines under the same header.
  final bool isResumed;
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

  _LogcatEntryBuilder resumed() => _LogcatEntryBuilder(
    timestamp: timestamp,
    pid: pid,
    tid: tid,
    level: level,
    tag: tag,
    isResumed: true,
  );

  void appendLine(String line) => _lines.add(line);

  PendingEntryStatus get status {
    if (_lines.isEmpty) return PendingEntryStatus.awaitingBody;
    return _lines.last.isEmpty
        ? PendingEntryStatus.complete
        : PendingEntryStatus.incomplete;
  }

  /// Returns null for a resumed entry holding nothing but blank lines — a late
  /// footer — which would otherwise show as an empty row.
  LogEntry? build() {
    // Drop the blank footer line (and any trailing newlines of the message
    // itself, which the header-per-line format never showed either).
    var end = _lines.length;
    while (end > 0 && _lines[end - 1].isEmpty) {
      end--;
    }
    if (isResumed && end == 0) return null;

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
