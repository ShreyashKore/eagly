import '../../../data/log_entry.dart';
import '../../../utils/log_buffer.dart';

class LogStoreAppendResult {
  const LogStoreAppendResult({required this.didEvictStoredLogs});

  final bool didEvictStoredLogs;
}

class LogStoreFlushResult {
  const LogStoreFlushResult({
    required this.hadPendingLogs,
    required this.didEvictStoredLogs,
  });

  final bool hadPendingLogs;
  final bool didEvictStoredLogs;
}

class LogTabLogStore {
  LogTabLogStore({required int baseCapacity})
    : _logsBuffer = LogBuffer<LogEntry>(baseCapacity: baseCapacity);

  LogBuffer<LogEntry> _logsBuffer;
  final List<LogEntry> _pendingLogs = [];

  int _logsMemoryBytes = 0;
  int _pendingLogsMemoryBytes = 0;

  List<LogEntry> get logs => _logsBuffer.getLogs();
  int get size => _logsBuffer.size;
  bool get hasLogs => _logsBuffer.size > 0;
  bool get hasAnyCachedLogs => hasLogs || _pendingLogs.isNotEmpty;
  int get totalMemoryBytes => _logsMemoryBytes + _pendingLogsMemoryBytes;
  List<LogEntry> get currentLogsSnapshot =>
      List<LogEntry>.unmodifiable([..._logsBuffer.getLogs(), ..._pendingLogs]);

  void setRetentionFilter(LogFilter<LogEntry>? filter) {
    _logsBuffer.setFilter(filter);
  }

  List<LogEntry> search(bool Function(LogEntry log) predicate) {
    return _logsBuffer.search(predicate);
  }

  void replaceStoredLogs(
    Iterable<LogEntry> entries, {
    required int baseCapacity,
    LogFilter<LogEntry>? retentionFilter,
  }) {
    final nextBuffer = LogBuffer<LogEntry>(baseCapacity: baseCapacity);
    nextBuffer.setFilter(retentionFilter);
    for (final entry in entries) {
      nextBuffer.append(entry);
    }
    nextBuffer.trimToCapacity();
    _logsBuffer = nextBuffer;
    _logsMemoryBytes = _estimateLogsBytes(_logsBuffer.getLogs());
  }

  void clearStoredLogs() {
    _logsBuffer.clear();
    _logsMemoryBytes = 0;
  }

  void clearAll() {
    clearStoredLogs();
    _pendingLogs.clear();
    _pendingLogsMemoryBytes = 0;
  }

  void queuePendingLog(LogEntry entry) {
    _pendingLogs.add(entry);
    _pendingLogsMemoryBytes += _estimateLogEntryBytes(entry);
  }

  LogStoreAppendResult appendImmediate(LogEntry entry) {
    final evictedLogs = _logsBuffer.append(entry);
    final addedBytes = _estimateLogEntryBytes(entry);
    final evictedBytes = _estimateLogsBytes(evictedLogs);

    _logsMemoryBytes += addedBytes - evictedBytes;
    if (_logsMemoryBytes < 0) {
      _logsMemoryBytes = 0;
    }

    return LogStoreAppendResult(didEvictStoredLogs: evictedLogs.isNotEmpty);
  }

  LogStoreFlushResult flushPending() {
    if (_pendingLogs.isEmpty) {
      return const LogStoreFlushResult(
        hadPendingLogs: false,
        didEvictStoredLogs: false,
      );
    }

    final pendingLogs = List<LogEntry>.of(_pendingLogs);
    final pendingLogsMemoryBytes = _pendingLogsMemoryBytes;
    _pendingLogs.clear();
    _pendingLogsMemoryBytes = 0;

    var evictedMemoryBytes = 0;
    var didEvictStoredLogs = false;
    for (final logEntry in pendingLogs) {
      final evictedLogs = _logsBuffer.append(logEntry);
      if (evictedLogs.isEmpty) continue;
      didEvictStoredLogs = true;
      evictedMemoryBytes += _estimateLogsBytes(evictedLogs);
    }

    _logsMemoryBytes += pendingLogsMemoryBytes - evictedMemoryBytes;
    if (_logsMemoryBytes < 0) {
      _logsMemoryBytes = 0;
    }

    return LogStoreFlushResult(
      hadPendingLogs: true,
      didEvictStoredLogs: didEvictStoredLogs,
    );
  }

  int _estimateLogEntryBytes(LogEntry log) {
    int stringBytes(String value) => value.length * 2;

    return 128 +
        stringBytes(log.type.name) +
        stringBytes(log.timestamp) +
        stringBytes(log.pid) +
        stringBytes(log.tid) +
        stringBytes(log.level) +
        stringBytes(log.tag) +
        stringBytes(log.message) +
        stringBytes(log.lowercaseSearchable) +
        (log.packageName == null ? 0 : stringBytes(log.packageName!));
  }

  int _estimateLogsBytes(Iterable<LogEntry> entries) {
    var total = 0;
    for (final entry in entries) {
      total += _estimateLogEntryBytes(entry);
    }
    return total;
  }
}

