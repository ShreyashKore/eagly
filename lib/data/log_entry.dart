class LogEntry {
  final String timestamp;
  final String pid;
  final String tid;
  final String level;
  final String tag;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.pid,
    required this.tid,
    required this.level,
    required this.tag,
    required this.message,
  });

  static LogEntry? parse(String line) {
    final regex = RegExp(
        r'^(\d\d-\d\d\s+\d\d:\d\d:\d\d\.\d+)\s+(\d+)\s+(\d+)\s+([VDIWEF])\s+([^:]+):\s+(.*)'
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
}
