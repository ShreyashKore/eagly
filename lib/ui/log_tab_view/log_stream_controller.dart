import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/device.dart';
import '../../data/log_entry.dart';
import '../../services/device_session_service.dart';
import '../../utils/log_buffer.dart';

enum LogcatState { stopped, running, paused }

/// Manages the active logcat stream, the pending-log buffer, flush timer,
/// and session-state log entries.
class LogStreamController extends ChangeNotifier {
  LogStreamController({
    required int initialLogLinesLimit,
    required DeviceSessionService deviceSessionService,
    required LogFilter<LogEntry>? Function() retentionFilterProvider,
    required ScrollController scrollController,
    required bool Function() autoScrollProvider,
    required VoidCallback onRowsEvicted,
    required VoidCallback onLogsChanged,
  })  : _deviceSessionService = deviceSessionService,
        _retentionFilterProvider = retentionFilterProvider,
        _scrollController = scrollController,
        _autoScrollProvider = autoScrollProvider,
        _onRowsEvicted = onRowsEvicted,
        _onLogsChanged = onLogsChanged,
        _logsBuffer = LogBuffer<LogEntry>(baseCapacity: initialLogLinesLimit);

  final DeviceSessionService _deviceSessionService;
  final LogFilter<LogEntry>? Function() _retentionFilterProvider;
  final ScrollController _scrollController;
  final bool Function() _autoScrollProvider;
  final VoidCallback _onRowsEvicted;
  final VoidCallback _onLogsChanged;

  LogBuffer<LogEntry> _logsBuffer;
  final List<LogEntry> _pendingLogs = [];

  StreamSubscription<LogEntry>? _logSub;
  Timer? _flushTimer;

  var logcatState = LogcatState.stopped;
  var _logsMemoryBytes = 0;
  var _pendingLogsMemoryBytes = 0;
  bool _disposed = false;

  Device? selectedDevice;

  bool get isRunning => logcatState != LogcatState.stopped;
  bool get isPaused => logcatState == LogcatState.paused;
  bool get hasLogs => _logsBuffer.size > 0;
  bool get hasAnyCachedLogs => hasLogs || _pendingLogs.isNotEmpty;
  int get totalLogsMemoryBytes => _logsMemoryBytes + _pendingLogsMemoryBytes;

  List<LogEntry> getLogs() => _logsBuffer.getLogs();

  int get logsBufferSize => _logsBuffer.size;

  List<LogEntry> searchLogs(bool Function(LogEntry) predicate) =>
      _logsBuffer.search(predicate);

  List<LogEntry> get currentLogsSnapshot =>
      List<LogEntry>.unmodifiable([..._logsBuffer.getLogs(), ..._pendingLogs]);

  void syncFilter() {
    _logsBuffer.setFilter(_retentionFilterProvider());
  }

  void replaceStoredLogs(Iterable<LogEntry> entries, int logLinesLimit) {
    final nextBuffer = LogBuffer<LogEntry>(baseCapacity: logLinesLimit);
    nextBuffer.setFilter(_retentionFilterProvider());
    for (final entry in entries) {
      nextBuffer.append(entry);
    }
    nextBuffer.trimToCapacity();
    _logsBuffer = nextBuffer;
    _logsMemoryBytes = _estimateLogsBytes(_logsBuffer.getLogs());
    _onLogsChanged();
  }

  void clearStoredLogs() {
    _logsBuffer.clear();
    _logsMemoryBytes = 0;
    _onLogsChanged();
  }

  void clearPendingLogs() {
    _pendingLogs.clear();
    _pendingLogsMemoryBytes = 0;
  }

  /// Appends a single entry immediately (no batching) – used for session
  /// state entries and special log entries.
  void appendImmediateLogEntry(LogEntry entry) {
    final evictedLogs = _logsBuffer.append(entry);
    final addedBytes = _estimateLogEntryBytes(entry);
    final evictedBytes = _estimateLogsBytes(evictedLogs);

    _logsMemoryBytes += addedBytes - evictedBytes;
    if (_logsMemoryBytes < 0) _logsMemoryBytes = 0;

    if (evictedLogs.isNotEmpty) _onRowsEvicted();

    _onLogsChanged();
    notifyListeners();

    if (_autoScrollProvider() && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void appendSessionStateEntry(
    LogEntryType type, {
    String? message,
    String? tag,
  }) {
    appendImmediateLogEntry(
      _buildSessionStateEntry(type, message: message, tag: tag),
    );
  }

  Future<void> start() async {
    await stopInternal(resetState: false);
    if (_disposed) return;

    clearStoredLogs();
    clearPendingLogs();
    logcatState = LogcatState.running;
    appendSessionStateEntry(LogEntryType.started);
    notifyListeners();

    _logSub = _deviceSessionService.startLogStream(selectedDevice!).listen((
      logEntry,
    ) {
      if (_disposed) return;
      if (logEntry.isSpecialEntry) {
        appendImmediateLogEntry(logEntry);
        return;
      }
      if (logcatState == LogcatState.paused) return;
      _pendingLogs.add(logEntry);
      _pendingLogsMemoryBytes += _estimateLogEntryBytes(logEntry);
    });

    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_disposed || _pendingLogs.isEmpty) return;

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
      if (_logsMemoryBytes < 0) _logsMemoryBytes = 0;

      if (didEvictStoredLogs) _onRowsEvicted();

      _onLogsChanged();
      notifyListeners();

      if (_autoScrollProvider() && _scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        });
      }
    });
  }

  Future<void> stop() => stopInternal(resetState: true);

  Future<void> stopInternal({required bool resetState}) async {
    _flushTimer?.cancel();
    _flushTimer = null;

    await _logSub?.cancel();
    _logSub = null;
    await _deviceSessionService.stopActiveLogStream();

    if (resetState && !_disposed) {
      logcatState = LogcatState.stopped;
      appendSessionStateEntry(LogEntryType.stopped);
      notifyListeners();
    }
  }

  void togglePauseResume() {
    if (!isRunning) return;
    final wasPaused = isPaused;
    logcatState = wasPaused ? LogcatState.running : LogcatState.paused;
    appendSessionStateEntry(
      wasPaused ? LogEntryType.resumed : LogEntryType.paused,
    );
    notifyListeners();
  }

  LogEntry _buildSessionStateEntry(
    LogEntryType type, {
    String? message,
    String? tag,
  }) {
    final subject = selectedDevice?.displayLabel.primary ??
        selectedDevice?.displayName ??
        selectedDevice?.id ??
        'device';

    final effectiveMessage = switch (type) {
      LogEntryType.started => message ?? 'Started capturing logs for $subject.',
      LogEntryType.resumed => message ?? 'Resumed live logging for $subject.',
      LogEntryType.paused => message ?? 'Paused live logging for $subject.',
      LogEntryType.stopped => message ?? 'Stopped capturing logs for $subject.',
      LogEntryType.error => message ?? 'A logging error occurred for $subject.',
      LogEntryType.notice => message ?? 'Logging state updated for $subject.',
      LogEntryType.log => message ?? '',
    };

    return LogEntry.loggingState(
      type: type,
      tag: tag ?? 'logview session',
      message: effectiveMessage,
      packageName: selectedDevice?.id,
      processName: subject,
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

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    // _logSub and _deviceSessionService are disposed by the parent.
    super.dispose();
  }
}


