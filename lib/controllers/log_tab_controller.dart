import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../data/device.dart';
import '../data/log_column.dart';
import '../data/log_entry.dart';
import '../data/log_tab_settings.dart';
import '../data/log_view_mode.dart';
import '../services/adb_service.dart';
import '../services/log_file_service.dart';
import '../utils/log_utils.dart';

enum LogcatState { stopped, running, paused }

class LogTabController extends ChangeNotifier {
  LogTabController({
    required this.id,
    required String initialTitle,
    required LogTabSettings initialSettings,
    required bool showGetStartedInitially,
    this.onExitGetStarted,
    AdbService? adbService,
  }) : _title = initialTitle,
       _settings = initialSettings,
       _showGetStarted = showGetStartedInitially,
       _adbService = adbService ?? AdbService() {
    filterController.text = searchQuery;
    logLinesController.text = logLinesLimit.toString();
  }

  final String id;
  final VoidCallback? onExitGetStarted;
  final AdbService _adbService;

  final ScrollController scrollController = ScrollController();
  final TextEditingController filterController = TextEditingController();
  final FocusNode filterFocusNode = FocusNode();
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  final TextEditingController logLinesController = TextEditingController();

  final List<LogEntry> _buffer = [];

  StreamSubscription<LogEntry>? _logSub;
  Timer? _flushTimer;
  Timer? _debounceTimer;
  Timer? _inlineSearchDebounce;

  var devices = <Device>[];
  Device? selectedDevice;
  var logs = <LogEntry>[];

  var logcatState = LogcatState.stopped;
  var searchQuery = '';
  var _appliedSearchQuery = '';

  var _searchBarVisible = false;
  var _inlineSearchQuery = '';
  var _appliedInlineSearchQuery = '';
  var _searchCaseSensitive = false;
  var _searchCurrentMatchIndex = 0;

  var _editingLogLinesLimit = false;
  var _logsMemoryBytes = 0;
  var _bufferMemoryBytes = 0;
  var _logViewerRevision = 0;

  var _disposed = false;
  var _showGetStarted = false;
  final String _title;
  LogTabSettings _settings;

  List<LogEntry>? _cachedFilteredLogs;
  int _lastLogsLength = 0;
  String _lastFilterQuery = '';
  String _lastLogLevel = 'V';

  List<int>? _cachedSearchMatchIndices;
  String _smCacheQuery = '';
  bool _smCacheCaseSensitive = false;
  Set<String> _smCacheHiddenCols = {};
  int _smCacheFilteredLen = -1;

  String get title {
    if (selectedDevice != null) return selectedDevice!.displayName;
    if (logs.isNotEmpty) return 'Imported Logs';
    if (_showGetStarted) return 'Get Started';
    return _title;
  }

  bool get showGetStarted => _showGetStarted;
  bool get searchBarVisible => _searchBarVisible;
  bool get searchCaseSensitive => _searchCaseSensitive;
  int get searchCurrentMatch => _searchCurrentMatchIndex;
  bool get editingLogLinesLimit => _editingLogLinesLimit;
  int get logViewerRevision => _logViewerRevision;
  bool get isRunning => logcatState != LogcatState.stopped;
  bool get isPaused => logcatState == LogcatState.paused;
  bool get hasLogs => logs.isNotEmpty;
  bool get hasSelectedDevice => selectedDevice != null;
  bool get hasVisibleWorkspace => hasSelectedDevice || hasLogs;
  int get totalLogsMemoryBytes => _logsMemoryBytes + _bufferMemoryBytes;
  String get appliedInlineSearchQuery => _appliedInlineSearchQuery;
  String get inlineSearchQuery => _inlineSearchQuery;

  bool get wrapText => _settings.wrapText;
  bool get autoScroll => _settings.autoScroll;
  String get selectedLogLevel => _settings.selectedLogLevel;
  LogViewMode get viewMode => _settings.viewMode;
  int get logLinesLimit => _settings.logLinesLimit;
  Set<String> get hiddenColumns => _settings.hiddenColumns;
  Map<String, double> get columnWidths => _settings.columnWidths;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _updateSettings(LogTabSettings settings) {
    _settings = settings;
    _notify();
  }

  void _exitGetStarted() {
    if (!_showGetStarted) return;
    _showGetStarted = false;
    onExitGetStarted?.call();
  }

  void focusFilterInputs() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      filterFocusNode.requestFocus();
      filterController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: filterController.text.length,
      );
    });
  }

  Future<void> loadDevices() async {
    _exitGetStarted();
    _notify();

    final fetchedDevices = await _adbService.getDevices();
    if (_disposed) return;

    final currentSelectionId = selectedDevice?.id;
    devices = fetchedDevices;

    if (fetchedDevices.isEmpty) {
      selectedDevice = null;
      await _stopLogcatInternal(resetState: true);
      _notify();
      return;
    }

    if (currentSelectionId != null) {
      selectedDevice = fetchedDevices.firstWhereOrNull(
        (device) => device.id == currentSelectionId,
      );
    }

    selectedDevice ??= fetchedDevices.length == 1 ? fetchedDevices.first : null;
    _notify();
  }

  Future<void> setSelectedDevice(Device? device) async {
    _exitGetStarted();
    if (selectedDevice?.id == device?.id) return;
    selectedDevice = device;
    if (isRunning) {
      await _stopLogcatInternal(resetState: true);
    }
    _notify();
  }

  Future<void> startLogcat() async {
    if (selectedDevice == null) return;
    _exitGetStarted();

    await _stopLogcatInternal(resetState: false);
    if (_disposed) return;

    logs = [];
    _buffer.clear();
    _logsMemoryBytes = 0;
    _bufferMemoryBytes = 0;
    _invalidateFilteredLogs();
    logcatState = LogcatState.running;
    _notify();

    _logSub = _adbService.startLogcat(selectedDevice!.id).listen((logEntry) {
      if (_disposed || logcatState == LogcatState.paused) return;
      _buffer.add(logEntry);
      _bufferMemoryBytes += _estimateLogEntryBytes(logEntry);
    });

    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_disposed || _buffer.isEmpty) return;

      logs = [...logs, ..._buffer];
      _logsMemoryBytes += _bufferMemoryBytes;
      _buffer.clear();
      _bufferMemoryBytes = 0;

      if (logs.length > logLinesLimit * 1.2) {
        final keep = logLinesLimit.floor();
        logs = logs.sublist(logs.length - keep);
        _logsMemoryBytes = _estimateLogsBytes(logs);
      }

      _invalidateFilteredLogs();
      _notify();

      if (autoScroll && scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!scrollController.hasClients) return;
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        });
      }
    });
  }

  Future<void> stopLogcat() => _stopLogcatInternal(resetState: true);

  Future<void> _stopLogcatInternal({required bool resetState}) async {
    _flushTimer?.cancel();
    _flushTimer = null;

    await _logSub?.cancel();
    _logSub = null;
    await _adbService.stopActiveLogcat();

    if (resetState && !_disposed) {
      logcatState = LogcatState.stopped;
      _notify();
    }
  }

  void togglePauseResume() {
    if (!isRunning) return;
    logcatState = isPaused ? LogcatState.running : LogcatState.paused;
    _notify();
  }

  void clearLogs() {
    logs = [];
    _buffer.clear();
    _logsMemoryBytes = 0;
    _bufferMemoryBytes = 0;
    _invalidateFilteredLogs();
    _notify();
  }

  Future<void> exportLogs() async {
    await LogFileService.exportLogs(logs, selectedDevice);
  }

  Future<void> importLogs() async {
    _exitGetStarted();
    _notify();

    final importedLogs = await LogFileService.importLogs();
    if (_disposed || importedLogs == null) return;

    await _stopLogcatInternal(resetState: false);
    if (_disposed) return;

    selectedDevice = null;
    logs = importedLogs;
    _buffer.clear();
    _logsMemoryBytes = _estimateLogsBytes(logs);
    _bufferMemoryBytes = 0;
    logcatState = LogcatState.stopped;
    _invalidateFilteredLogs();
    _notify();
  }

  void scrollToEnd() {
    if (!scrollController.hasClients) return;
    scrollController.animateTo(
      scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void disableAutoScroll() {
    if (!autoScroll) return;
    _updateSettings(_settings.copyWith(autoScroll: false));
  }

  void clearFilter() {
    _debounceTimer?.cancel();
    filterController.clear();
    searchQuery = '';
    _appliedSearchQuery = '';
    _invalidateFilteredLogs();
    focusFilterInputs();
    _notify();
  }

  void onSearchChanged(String value) {
    searchQuery = value;
    _notify();

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      _appliedSearchQuery = value;
      _invalidateFilteredLogs();
      _notify();
    });
  }

  void setSelectedLogLevel(String level) {
    _updateSettings(_settings.copyWith(selectedLogLevel: level));
    _invalidateFilteredLogs();
  }

  void toggleWrapText() {
    _logViewerRevision++;
    _updateSettings(_settings.copyWith(wrapText: !wrapText));
  }

  void toggleAutoScroll() {
    _updateSettings(_settings.copyWith(autoScroll: !autoScroll));
  }

  void cycleViewMode() {
    _updateSettings(
      _settings.copyWith(
        viewMode: LogViewMode.values[(viewMode.index + 1) % LogViewMode.values.length],
      ),
    );
  }

  void setHiddenColumns(Set<String> columns) {
    _logViewerRevision++;
    _updateSettings(_settings.copyWith(hiddenColumns: Set.of(columns)));
    _invalidateSearchMatches();
  }

  void setColumnWidths(Map<String, double> widths) {
    _updateSettings(_settings.copyWith(columnWidths: Map.of(widths)));
  }

  void setEditingLogLinesLimit(bool value) {
    _editingLogLinesLimit = value;
    if (value) {
      logLinesController.text = logLinesLimit.toString();
    }
    _notify();
  }

  bool submitLogLinesLimit([String? rawValue]) {
    final parsed = int.tryParse((rawValue ?? logLinesController.text).trim());
    if (parsed == null || parsed < 1000) {
      _editingLogLinesLimit = false;
      _notify();
      return false;
    }

    _editingLogLinesLimit = false;
    logLinesController.text = parsed.toString();
    _updateSettings(_settings.copyWith(logLinesLimit: parsed));

    if (logs.length > parsed) {
      logs = logs.sublist(logs.length - parsed);
      _logsMemoryBytes = _estimateLogsBytes(logs);
      _invalidateFilteredLogs();
    }

    _notify();
    return true;
  }

  void toggleSearchBar() {
    _inlineSearchDebounce?.cancel();
    _searchBarVisible = !_searchBarVisible;

    if (!_searchBarVisible) {
      _inlineSearchQuery = '';
      _appliedInlineSearchQuery = '';
      searchController.clear();
      _invalidateSearchMatches();
      _searchCurrentMatchIndex = 0;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed) return;
        searchFocusNode.requestFocus();
        searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: searchController.text.length,
        );
      });
    }

    _notify();
  }

  void onInlineSearchChanged(String value) {
    _inlineSearchQuery = value;
    _searchCurrentMatchIndex = 0;
    _notify();

    _inlineSearchDebounce?.cancel();
    _inlineSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      _appliedInlineSearchQuery = value;
      _invalidateSearchMatches();
      _notify();
    });
  }

  void setSearchCaseSensitive(bool value) {
    _inlineSearchDebounce?.cancel();
    _searchCaseSensitive = value;
    _appliedInlineSearchQuery = _inlineSearchQuery;
    _invalidateSearchMatches();
    _searchCurrentMatchIndex = 0;
    _notify();
  }

  void onSearchNext() {
    final matches = searchMatchIndices;
    if (matches.isEmpty) return;
    _searchCurrentMatchIndex = (_searchCurrentMatchIndex + 1) % matches.length;
    _notify();
  }

  void onSearchPrev() {
    final matches = searchMatchIndices;
    if (matches.isEmpty) return;
    _searchCurrentMatchIndex =
        (_searchCurrentMatchIndex - 1 + matches.length) % matches.length;
    _notify();
  }

  List<LogEntry> get filteredLogs {
    final selectedLevelValue = LogUtils.levelHierarchy[selectedLogLevel] ?? 4;

    if (_cachedFilteredLogs != null &&
        _lastLogsLength == logs.length &&
        _lastFilterQuery == _appliedSearchQuery &&
        _lastLogLevel == selectedLogLevel) {
      return _cachedFilteredLogs!;
    }

    _lastLogsLength = logs.length;
    _lastFilterQuery = _appliedSearchQuery;
    _lastLogLevel = selectedLogLevel;

    final query = _appliedSearchQuery.toLowerCase();
    _cachedFilteredLogs = logs.where((log) {
      final logLevelValue = LogUtils.levelHierarchy[log.level] ?? 4;
      if (logLevelValue > selectedLevelValue) return false;
      if (_appliedSearchQuery.isEmpty) return true;
      return log.lowercaseSearchable.contains(query);
    }).toList();

    return _cachedFilteredLogs!;
  }

  List<int> get searchMatchIndices {
    final filtered = filteredLogs;
    if (_cachedSearchMatchIndices != null &&
        _smCacheQuery == _appliedInlineSearchQuery &&
        _smCacheCaseSensitive == _searchCaseSensitive &&
        _smCacheHiddenCols.length == hiddenColumns.length &&
        _smCacheHiddenCols.containsAll(hiddenColumns) &&
        _smCacheFilteredLen == filtered.length) {
      return _cachedSearchMatchIndices!;
    }

    _smCacheQuery = _appliedInlineSearchQuery;
    _smCacheCaseSensitive = _searchCaseSensitive;
    _smCacheHiddenCols = Set.of(hiddenColumns);
    _smCacheFilteredLen = filtered.length;
    _cachedSearchMatchIndices = _computeSearchMatches(filtered);
    return _cachedSearchMatchIndices!;
  }

  int currentSearchMatchLogIndex(List<int> matches) {
    if (matches.isEmpty) return -1;
    return matches[_searchCurrentMatchIndex.clamp(0, matches.length - 1)];
  }

  String formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;

    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }

    final precision = value >= 100 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
  }

  void _invalidateFilteredLogs() {
    _cachedFilteredLogs = null;
    _invalidateSearchMatches();
  }

  void _invalidateSearchMatches() {
    _cachedSearchMatchIndices = null;
  }

  String _logColumnValue(LogEntry log, LogColumn column) => switch (column) {
    LogColumn.timestamp => log.timestamp,
    LogColumn.pid => log.packageName ?? log.pid,
    LogColumn.tid => log.tid,
    LogColumn.level => log.level,
    LogColumn.tag => log.tag,
    LogColumn.message => log.message,
  };

  List<int> _computeSearchMatches(List<LogEntry> items) {
    if (_appliedInlineSearchQuery.isEmpty) return [];

    final query = _searchCaseSensitive
        ? _appliedInlineSearchQuery
        : _appliedInlineSearchQuery.toLowerCase();
    final visibleColumns = LogColumn.values
        .where((column) => !hiddenColumns.contains(column.name))
        .toList();

    final result = <int>[];
    for (var index = 0; index < items.length; index++) {
      final log = items[index];
      for (final column in visibleColumns) {
        final text = _searchCaseSensitive
            ? _logColumnValue(log, column)
            : _logColumnValue(log, column).toLowerCase();
        if (text.contains(query)) {
          result.add(index);
          break;
        }
      }
    }
    return result;
  }

  int _estimateLogEntryBytes(LogEntry log) {
    int stringBytes(String value) => value.length * 2;

    return 128 +
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
    _debounceTimer?.cancel();
    _inlineSearchDebounce?.cancel();
    unawaited(_logSub?.cancel());
    unawaited(_adbService.dispose());
    scrollController.dispose();
    filterController.dispose();
    filterFocusNode.dispose();
    searchController.dispose();
    searchFocusNode.dispose();
    logLinesController.dispose();
    super.dispose();
  }
}


