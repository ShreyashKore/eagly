class LogEntry {
  final String timestamp;
  final String pid;
  final String tid;
  final String level;
  final String tag;
  final String message;
  final String lowercaseSearchable;
  String? packageName;

  LogEntry({
    required this.timestamp,
    required this.pid,
    required this.tid,
    required this.level,
    required this.tag,
    required this.message,
    this.packageName,
  }) : lowercaseSearchable = '$tag $message'.toLowerCase();


  @override
  String toString() {
    return 'LogEntry(timestamp: $timestamp, pid: $pid, tid: $tid, level: $level, tag: $tag, message: $message, packageName: $packageName)';
  }

  @override
  int get hashCode {
    return Object.hash(timestamp, pid, tid, level, tag, message, packageName);
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
        other.packageName == packageName;
  }

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
