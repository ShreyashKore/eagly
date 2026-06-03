import '../utils/log_entry_id_generator.dart';

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
  }) : id = id ?? LogEntryIdGenerator.instance.next(),
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
}
