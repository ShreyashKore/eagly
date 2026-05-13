import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/device.dart';
import '../../data/log_entry.dart';
import '../../data/log_level.dart';
import '../../data/log_tab_settings.dart';
import '../../services/device_repository.dart';
import '../../services/device_session_service.dart';
import '../../services/log_file_service.dart';
import '../../utils/log_buffer.dart';
import '../../utils/text_search_pattern.dart';
import '../wireless_connection/wireless_connection_controller.dart';
import 'log_filter_controller.dart';
import 'log_inline_search_controller.dart';
import 'log_row_selection_controller.dart';

export 'log_filter_controller.dart' show LogFilterController;
export 'log_inline_search_controller.dart' show LogInlineSearchController;
export 'log_row_selection_controller.dart'
    show LogRowSelectionController, LogCopyFormat;

enum LogcatState { stopped, running, paused }

class LogTabController extends ChangeNotifier {
  LogTabController({
    required this.id,
    required String initialTitle,
    required LogTabSettings initialSettings,
    this.onExitGetStarted,
    this.isDeviceSelectedInAnotherTab,
    DeviceRepository? deviceRepository,
    DeviceSessionService? deviceSessionService,
  }) : _title = initialTitle,
       _settings = initialSettings,
       _deviceRepository = deviceRepository ?? DeviceRepository.instance,
       _logsBuffer = LogBuffer<LogEntry>(
         baseCapacity: initialSettings.logLinesLimit,
       ),
       _deviceSessionService = deviceSessionService ?? DeviceSessionService() {
    // Wire sub-controllers
    filterCtrl.initFromSettings(
      searchQuery: '',
      packageFilterQuery: '',
      pidTidFilterQuery: '',
      tagFilterQuery: '',
      selectedLogLevel: initialSettings.selectedLogLevel,
    );
    searchCtrl.onDisableAutoScroll = disableAutoScroll;

    filterCtrl.addListener(_onSubControllerChanged);
    searchCtrl.addListener(_onSubControllerChanged);
    selectionCtrl.addListener(_onSubControllerChanged);

    wirelessController = WirelessConnectionController(
      deviceRepository: _deviceRepository,
      deviceSessionService: _deviceSessionService,
      onDevicesApplied: (fetchedDevices) =>
          _applyFetchedDevices(fetchedDevices),
      onActivateDevice: selectDeviceAndStart,
      isDeviceSelectedInAnotherTab: isDeviceSelectedInAnotherTab,
      selectedDeviceIdProvider: () => selectedDevice?.id,
      isRunningProvider: () => isRunning,
    );
    logLinesController.text = logLinesLimit.toString();
    devices = _deviceRepository.devices.toList(growable: false);
    _syncLogBufferFilter();
    _deviceRepository.addListener(_handleDeviceRepositoryChanged);
    unawaited(_deviceRepository.ensureStarted());
  }

  final String id;
  final VoidCallback? onExitGetStarted;
  final bool Function(String deviceId)? isDeviceSelectedInAnotherTab;
  final DeviceRepository _deviceRepository;
  final DeviceSessionService _deviceSessionService;
  late final WirelessConnectionController wirelessController;

  // ── Sub-controllers ─────────────────────────────────────────────────────
  final LogFilterController filterCtrl = LogFilterController();
  final LogInlineSearchController searchCtrl = LogInlineSearchController();
  final LogRowSelectionController selectionCtrl = LogRowSelectionController();

  // ── Own state ───────────────────────────────────────────────────────────
  final ScrollController scrollController = ScrollController();
  final TextEditingController logLinesController = TextEditingController();

  LogBuffer<LogEntry> _logsBuffer;
  final List<LogEntry> _pendingLogs = [];

  StreamSubscription<LogEntry>? _logSub;
  Timer? _flushTimer;

  var devices = <Device>[];
  Device? selectedDevice;

  var logcatState = LogcatState.stopped;

  var _editingLogLinesLimit = false;
  var _logsMemoryBytes = 0;
  var _pendingLogsMemoryBytes = 0;
  var _logViewerRevision = 0;

  var _disposed = false;
  var _showGetStarted = true;
  final String _title;
  String? _importedFileName;
  LogTabSettings _settings;

  // Filtered logs cache
  List<LogEntry>? _cachedFilteredLogs;
  int _lastLogsLength = 0;
  String _lastFilterQuery = '';
  String _lastPackageFilterQuery = '';
  String _lastPidTidFilterQuery = '';
  String _lastTagFilterQuery = '';
  LogLevel _lastLogLevel = LogLevel.verbose;

  // ── Delegated getters from FilterController ─────────────────────────────
  TextEditingController get filterController => filterCtrl.filterController;
  FocusNode get filterFocusNode => filterCtrl.filterFocusNode;
  TextEditingController get packageFilterController =>
      filterCtrl.packageFilterController;
  FocusNode get packageFilterFocusNode => filterCtrl.packageFilterFocusNode;
  TextEditingController get pidTidFilterController =>
      filterCtrl.pidTidFilterController;
  FocusNode get pidTidFilterFocusNode => filterCtrl.pidTidFilterFocusNode;
  TextEditingController get tagFilterController =>
      filterCtrl.tagFilterController;
  FocusNode get tagFilterFocusNode => filterCtrl.tagFilterFocusNode;
  String get searchQuery => filterCtrl.searchQuery;
  String get packageFilterQuery => filterCtrl.packageFilterQuery;
  String get pidTidFilterQuery => filterCtrl.pidTidFilterQuery;
  String get tagFilterQuery => filterCtrl.tagFilterQuery;
  List<String> get recentMessageFilters => filterCtrl.recentMessageFilters;
  List<String> get recentPackageFilters => filterCtrl.recentPackageFilters;
  List<String> get recentPidTidFilters => filterCtrl.recentPidTidFilters;
  List<String> get recentTagFilters => filterCtrl.recentTagFilters;

  // ── Delegated getters from InlineSearchController ───────────────────────
  TextEditingController get searchController => searchCtrl.searchController;
  FocusNode get searchFocusNode => searchCtrl.searchFocusNode;
  bool get searchBarVisible => searchCtrl.searchBarVisible;
  bool get searchCaseSensitive => searchCtrl.searchCaseSensitive;
  bool get searchWholeWord => searchCtrl.searchWholeWord;
  bool get searchRegex => searchCtrl.searchRegex;
  int get searchCurrentMatch => searchCtrl.searchCurrentMatch;
  String? get selectedSearchText => searchCtrl.selectedSearchText;
  String get appliedInlineSearchQuery => searchCtrl.appliedInlineSearchQuery;
  String get inlineSearchQuery => searchCtrl.inlineSearchQuery;
  TextSearchPattern get inlineSearchPattern => searchCtrl.inlineSearchPattern;
  bool get inlineSearchHasError => searchCtrl.inlineSearchHasError;
  String? get inlineSearchErrorText => searchCtrl.inlineSearchErrorText;

  // ── Delegated getters from RowSelectionController ───────────────────────
  bool get rowSelectionMode => selectionCtrl.rowSelectionMode;
  Set<int> get selectedRowIndices => selectionCtrl.selectedRowIndices;
  bool get hasSelectedRows => selectionCtrl.hasSelectedRows;
  int get selectedRowCount => selectionCtrl.selectedRowCount;
  int? get rowSelectionAnchorIndex => selectionCtrl.rowSelectionAnchorIndex;

  // ── Own getters ─────────────────────────────────────────────────────────
  List<LogEntry> get logs => _logsBuffer.getLogs();

  set logs(List<LogEntry> value) {
    _replaceStoredLogs(value);
  }

  String get title {
    if (selectedDevice != null) return selectedDevice!.displayLabel.primary;
    if (_importedFileName != null) return _importedFileName!;
    if (_showGetStarted) return 'Get Started';
    return _title;
  }

  bool get showGetStarted => _showGetStarted;
  bool get editingLogLinesLimit => _editingLogLinesLimit;
  int get logViewerRevision => _logViewerRevision;
  bool get isReadingFromFile => _importedFileName != null;
  bool get isRunning => logcatState != LogcatState.stopped;
  bool get isPaused => logcatState == LogcatState.paused;
  bool get hasLogs => _logsBuffer.size > 0;
  bool get hasAnyCachedLogs => hasLogs || _pendingLogs.isNotEmpty;
  bool get hasSelectedDevice => selectedDevice != null;
  bool get hasConnectedSelectedDevice => selectedDevice?.isConnected == true;
  bool get hasVisibleWorkspace => hasSelectedDevice || hasLogs;
  int get totalLogsMemoryBytes => _logsMemoryBytes + _pendingLogsMemoryBytes;
  bool get isLoadingDevices => _deviceRepository.isLoading;
  bool get hasAttemptedDeviceLoad => _deviceRepository.hasAttemptedLoad;

  bool get wrapText => _settings.wrapText;
  bool get autoScroll => _settings.autoScroll;
  LogLevel get selectedLogLevel => _settings.selectedLogLevel;
  int get logLinesLimit => _settings.logLinesLimit;
  Set<String> get hiddenColumns => _settings.hiddenColumns;
  Map<String, double> get columnWidths => _settings.columnWidths;

  bool get isIosLogContext {
    if (selectedDevice is IosDevice) return true;
    if (selectedDevice is AndroidDevice) return false;

    final storedLogs = logs;
    final sampleLevel = storedLogs.firstWhereOrNull(
      (log) => log.level.trim().isNotEmpty,
    );
    return sampleLevel != null &&
        LogLevel.looksLikeIosStoredLevel(sampleLevel.level);
  }

  LogLevel get effectiveSelectedLogLevel => selectedLogLevel;

  // ── Notification plumbing ───────────────────────────────────────────────

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _onSubControllerChanged() {
    _syncLogBufferFilter();
    _invalidateFilteredLogs();
    _notify();
  }

  void _updateSettings(LogTabSettings settings) {
    _settings = settings;
    _notify();
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  void _exitGetStarted() {
    if (!_showGetStarted) return;
    _showGetStarted = false;
    onExitGetStarted?.call();
  }

  void _exitGetStartedIfWorkspaceReady() {
    if (selectedDevice != null || logs.isNotEmpty) {
      _exitGetStarted();
    }
  }

  Future<void> bootstrapInitialLoad() async {
    await loadDevices(autoStartSingleIfAvailable: true);
  }

  // ── Delegated filter methods ────────────────────────────────────────────

  void focusFilterInputs() => filterCtrl.focusFilterInputs();

  void clearFilter() {
    selectionCtrl.clearSelectedRows(notify: false);
    filterCtrl.clearFilter();
  }

  void onSearchChanged(String value) => filterCtrl.onSearchChanged(value);

  void onPackageFilterChanged(String value) =>
      filterCtrl.onPackageFilterChanged(value);

  void onPidTidFilterChanged(String value) =>
      filterCtrl.onPidTidFilterChanged(value);

  void onTagFilterChanged(String value) =>
      filterCtrl.onTagFilterChanged(value);

  void selectMessageFilterSuggestion(String value) =>
      filterCtrl.selectMessageFilterSuggestion(value);

  void selectPackageFilterSuggestion(String value) =>
      filterCtrl.selectPackageFilterSuggestion(value);

  void selectPidTidFilterSuggestion(String value) =>
      filterCtrl.selectPidTidFilterSuggestion(value);

  void selectTagFilterSuggestion(String value) =>
      filterCtrl.selectTagFilterSuggestion(value);

  void applyFiltersNow() => filterCtrl.applyFiltersNow();

  void setSelectedLogLevel(LogLevel level) {
    _updateSettings(_settings.copyWith(selectedLogLevel: level));
    filterCtrl.setSelectedLogLevel(level);
    selectionCtrl.clearSelectedRows(notify: false);
  }

  // ── Delegated inline search methods ─────────────────────────────────────

  void toggleSearchBar() => searchCtrl.toggleSearchBar();

  void openSearchBar({String? query}) => searchCtrl.openSearchBar(query: query);

  void closeSearchBar() => searchCtrl.closeSearchBar();

  void activateSearchFromSelection() {
    final selectedText = searchCtrl.selectedSearchText;
    if (selectedText != null) {
      unawaited(Clipboard.setData(ClipboardData(text: selectedText)));
      searchCtrl.openSearchBar(query: selectedText);
      return;
    }
    searchCtrl.openSearchBar();
  }

  void onInlineSearchChanged(String value) =>
      searchCtrl.onInlineSearchChanged(value);

  void setSearchCaseSensitive(bool value) =>
      searchCtrl.setSearchCaseSensitive(value);

  void setSearchWholeWord(bool value) => searchCtrl.setSearchWholeWord(value);

  void setSearchRegex(bool value) => searchCtrl.setSearchRegex(value);

  void onSearchNext() {
    // Ensure search matches are populated before navigating.
    searchCtrl.getSearchMatchIndices(filteredLogs, hiddenColumns);
    searchCtrl.onSearchNext();
  }

  void onSearchPrev() {
    searchCtrl.getSearchMatchIndices(filteredLogs, hiddenColumns);
    searchCtrl.onSearchPrev();
  }

  void setSelectedSearchText(String? value) =>
      searchCtrl.setSelectedSearchText(value);

  int currentSearchMatchLogIndex(List<int> matches) =>
      searchCtrl.currentSearchMatchLogIndex(matches);

  // ── Delegated row selection methods ─────────────────────────────────────

  void toggleRowSelectionMode() => selectionCtrl.toggleRowSelectionMode();

  void setRowSelectionMode(bool value) =>
      selectionCtrl.setRowSelectionMode(value);

  bool isRowSelected(int filteredIndex) =>
      selectionCtrl.isRowSelected(filteredIndex);

  bool? beginRowSelectionGesture(
    int filteredIndex, {
    bool shiftPressed = false,
  }) {
    return selectionCtrl.beginRowSelectionGesture(
      filteredIndex,
      shiftPressed: shiftPressed,
      filteredLogsProvider: () => filteredLogs,
    );
  }

  void setRowSelected(int filteredIndex, bool selected) {
    selectionCtrl.setRowSelected(
      filteredIndex,
      selected,
      filteredLogsProvider: () => filteredLogs,
    );
  }

  void setSelectedRows(Set<int> indices) {
    selectionCtrl.setSelectedRows(
      indices,
      filteredLogsProvider: () => filteredLogs,
    );
  }

  void selectRowRangeTo(int filteredIndex) {
    selectionCtrl.selectRowRangeTo(
      filteredIndex,
      filteredLogsProvider: () => filteredLogs,
    );
  }

  void clearSelectedRows({bool notify = true}) =>
      selectionCtrl.clearSelectedRows(notify: notify);

  Future<int> copyAllLogs() {
    return selectionCtrl.copyAllLogs(_currentLogsSnapshot);
  }

  Future<int> copyRowsForContextMenu({
    required int? clickedFilteredIndex,
    required LogCopyFormat format,
  }) {
    return selectionCtrl.copyRowsForContextMenu(
      clickedFilteredIndex: clickedFilteredIndex,
      format: format,
      filteredLogsProvider: () => filteredLogs,
    );
  }

  Future<int> copyFilteredRows(
    Iterable<int> filteredIndices, {
    required LogCopyFormat format,
  }) {
    return selectionCtrl.copyFilteredRows(
      filteredIndices,
      format: format,
      filteredLogsProvider: () => filteredLogs,
    );
  }

  String formatLogsForClipboard(
    Iterable<LogEntry> entries, {
    required LogCopyFormat format,
  }) {
    return selectionCtrl.formatLogsForClipboard(entries, format: format);
  }

  // ── Settings methods ────────────────────────────────────────────────────

  void toggleWrapText() {
    _logViewerRevision++;
    _updateSettings(_settings.copyWith(wrapText: !wrapText));
  }

  void toggleAutoScroll() {
    _updateSettings(_settings.copyWith(autoScroll: !autoScroll));
  }

  void disableAutoScroll() {
    if (!autoScroll) return;
    _updateSettings(_settings.copyWith(autoScroll: false));
  }

  void setHiddenColumns(Set<String> columns) {
    _logViewerRevision++;
    _updateSettings(_settings.copyWith(hiddenColumns: Set.of(columns)));
    searchCtrl.invalidateSearchMatches();
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
    final storedLogs = logs;
    final previousCount = storedLogs.length;
    _updateSettings(_settings.copyWith(logLinesLimit: parsed));

    _replaceStoredLogs(storedLogs);
    if (_logsBuffer.size < previousCount) {
      selectionCtrl.clearSelectedRows(notify: false);
    }

    _notify();
    return true;
  }

  void scrollToEnd() {
    if (!scrollController.hasClients) return;
    scrollController.animateTo(
      scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // ── Device management ───────────────────────────────────────────────────

  Future<void> loadDevices({bool autoStartSingleIfAvailable = false}) async {
    await _deviceRepository.refreshDevices(force: true, showLoading: true);
    if (_disposed) return;
    await _applyFetchedDevices(
      _deviceRepository.devices,
      autoStartSingleIfAvailable: autoStartSingleIfAvailable,
    );
    _notify();
  }

  Future<void> setSelectedDevice(Device? device) async {
    if (device == null) {
      if (selectedDevice == null) return;
      selectionCtrl.clearSelectedRows(notify: false);
      selectedDevice = null;
      if (isRunning) {
        await _stopLogcatInternal(resetState: true);
      }
      _notify();
      return;
    }
    await selectDeviceAndStart(device);
  }

  Future<void> selectDeviceAndStart(Device device) async {
    final sameDevice = selectedDevice?.id == device.id;
    _importedFileName = null;
    selectedDevice = device;
    _exitGetStarted();
    _notify();

    if (sameDevice && isRunning) return;
    await startLogcat();
  }

  // ── Log buffer & memory ─────────────────────────────────────────────────

  void clearLogs() {
    selectionCtrl.clearSelectedRows(notify: false);
    _clearStoredLogs();
    _pendingLogs.clear();
    _pendingLogsMemoryBytes = 0;
    _notify();
  }

  Future<LogExportResult> exportLogs() async {
    return LogFileService.exportLogs(logs, selectedDevice);
  }

  Future<LogImportResult> importLogs() async {
    final result = await LogFileService.importLogs();
    if (_disposed || !result.isSuccess || result.logs == null) return result;

    await _stopLogcatInternal(resetState: false);
    if (_disposed) return result;

    selectionCtrl.clearSelectedRows(notify: false);
    selectedDevice = null;
    _importedFileName = result.fileName;
    logs = result.logs!;
    _pendingLogs.clear();
    _pendingLogsMemoryBytes = 0;
    logcatState = LogcatState.stopped;
    _exitGetStarted();
    _notify();
    return result;
  }

  // ── Filtered logs (cached) ──────────────────────────────────────────────

  List<LogEntry> get filteredLogs {
    final appliedSearch = filterCtrl.appliedSearchQuery;
    final appliedPackage = filterCtrl.appliedPackageFilterQuery;
    final appliedPidTid = filterCtrl.appliedPidTidFilterQuery;
    final appliedTag = filterCtrl.appliedTagFilterQuery;
    final level = filterCtrl.selectedLogLevel;

    if (_cachedFilteredLogs != null &&
        _lastLogsLength == _logsBuffer.size &&
        _lastFilterQuery == appliedSearch &&
        _lastPackageFilterQuery == appliedPackage &&
        _lastPidTidFilterQuery == appliedPidTid &&
        _lastTagFilterQuery == appliedTag &&
        _lastLogLevel == level) {
      return _cachedFilteredLogs!;
    }

    _lastLogsLength = _logsBuffer.size;
    _lastFilterQuery = appliedSearch;
    _lastPackageFilterQuery = appliedPackage;
    _lastPidTidFilterQuery = appliedPidTid;
    _lastTagFilterQuery = appliedTag;
    _lastLogLevel = level;

    _cachedFilteredLogs = _logsBuffer.search(filterCtrl.matchesLogFilters);
    return _cachedFilteredLogs!;
  }

  List<int> get searchMatchIndices {
    return searchCtrl.getSearchMatchIndices(filteredLogs, hiddenColumns);
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

  // ── Logcat lifecycle ────────────────────────────────────────────────────

  Future<void> startLogcat() async {
    if (selectedDevice == null) return;
    _exitGetStartedIfWorkspaceReady();

    await _stopLogcatInternal(resetState: false);
    if (_disposed) return;

    selectionCtrl.clearSelectedRows(notify: false);
    _importedFileName = null;
    _clearStoredLogs();
    _pendingLogs.clear();
    _pendingLogsMemoryBytes = 0;
    logcatState = LogcatState.running;
    _appendSessionStateEntry(LogEntryType.started);
    _notify();

    _logSub = _deviceSessionService.startLogStream(selectedDevice!).listen((
      logEntry,
    ) {
      if (_disposed) return;
      if (logEntry.isSpecialEntry) {
        _appendImmediateLogEntry(logEntry);
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
      if (_logsMemoryBytes < 0) {
        _logsMemoryBytes = 0;
      }

      if (didEvictStoredLogs) {
        selectionCtrl.clearSelectedRows(notify: false);
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
    await _deviceSessionService.stopActiveLogStream();

    if (resetState && !_disposed) {
      logcatState = LogcatState.stopped;
      _appendSessionStateEntry(LogEntryType.stopped);
      _notify();
    }
  }

  void togglePauseResume() {
    if (!isRunning) return;
    final wasPaused = isPaused;
    logcatState = wasPaused ? LogcatState.running : LogcatState.paused;
    _appendSessionStateEntry(
      wasPaused ? LogEntryType.resumed : LogEntryType.paused,
    );
    _notify();
  }

  // ── Internal helpers ────────────────────────────────────────────────────

  void _invalidateFilteredLogs() {
    _cachedFilteredLogs = null;
    searchCtrl.invalidateSearchMatches();
  }

  void _syncLogBufferFilter() {
    _logsBuffer.setFilter(filterCtrl.retentionFilter);
  }

  void _replaceStoredLogs(Iterable<LogEntry> entries) {
    final nextBuffer = LogBuffer<LogEntry>(baseCapacity: logLinesLimit);
    nextBuffer.setFilter(filterCtrl.retentionFilter);
    for (final entry in entries) {
      nextBuffer.append(entry);
    }
    nextBuffer.trimToCapacity();
    _logsBuffer = nextBuffer;
    _logsMemoryBytes = _estimateLogsBytes(_logsBuffer.getLogs());
    _invalidateFilteredLogs();
  }

  void _clearStoredLogs() {
    _logsBuffer.clear();
    _logsMemoryBytes = 0;
    _invalidateFilteredLogs();
  }

  String _loggingSubjectLabel() {
    return selectedDevice?.displayLabel.primary ??
        selectedDevice?.displayName ??
        selectedDevice?.id ??
        'device';
  }

  LogEntry _buildSessionStateEntry(
    LogEntryType type, {
    String? message,
    String? tag,
  }) {
    final subject = _loggingSubjectLabel();
    final effectiveMessage = switch (type) {
      LogEntryType.started =>
        message ?? 'Started capturing logs for $subject.',
      LogEntryType.resumed =>
        message ?? 'Resumed live logging for $subject.',
      LogEntryType.paused => message ?? 'Paused live logging for $subject.',
      LogEntryType.stopped =>
        message ?? 'Stopped capturing logs for $subject.',
      LogEntryType.error =>
        message ?? 'A logging error occurred for $subject.',
      LogEntryType.notice =>
        message ?? 'Logging state updated for $subject.',
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

  void _appendImmediateLogEntry(LogEntry entry) {
    final evictedLogs = _logsBuffer.append(entry);
    final addedBytes = _estimateLogEntryBytes(entry);
    final evictedBytes = _estimateLogsBytes(evictedLogs);

    _logsMemoryBytes += addedBytes - evictedBytes;
    if (_logsMemoryBytes < 0) {
      _logsMemoryBytes = 0;
    }

    if (evictedLogs.isNotEmpty) {
      selectionCtrl.clearSelectedRows(notify: false);
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
  }

  void _appendSessionStateEntry(
    LogEntryType type, {
    String? message,
    String? tag,
  }) {
    _appendImmediateLogEntry(
      _buildSessionStateEntry(type, message: message, tag: tag),
    );
  }

  Future<void> _stopLogcatForDisconnectedDevice(Device device) async {
    if (!isRunning) return;

    await _stopLogcatInternal(resetState: false);
    if (_disposed) return;

    logcatState = LogcatState.stopped;
    _appendSessionStateEntry(
      LogEntryType.stopped,
      message:
          'Device disconnected; stopped capturing logs for ${device.displayName}.',
      tag: 'device connection',
    );
  }

  Future<void> _applyFetchedDevices(
    List<Device> fetchedDevices, {
    bool autoStartSingleIfAvailable = false,
  }) async {
    final currentSelectionId = selectedDevice?.id;
    final previousSelectedDevice = selectedDevice;
    devices = fetchedDevices;

    if (currentSelectionId != null) {
      selectedDevice = fetchedDevices.firstWhereOrNull(
        (device) => device.id == currentSelectionId,
      );
    }

    final selectedDeviceJustDisconnected = previousSelectedDevice != null &&
        previousSelectedDevice.isConnected &&
        selectedDevice != null &&
        selectedDevice!.isDisconnected;

    if (selectedDeviceJustDisconnected) {
      await _stopLogcatForDisconnectedDevice(selectedDevice!);
    }

    if (currentSelectionId != null && selectedDevice == null) {
      selectedDevice = null;
      await _stopLogcatInternal(resetState: true);
    }

    final shouldAutoStartSingleDevice = autoStartSingleIfAvailable &&
        !hasLogs &&
        selectedDevice == null &&
        fetchedDevices.where((device) => device.isConnected).length == 1 &&
        !(isDeviceSelectedInAnotherTab?.call(
              fetchedDevices.firstWhere((device) => device.isConnected).id,
            ) ??
            false);

    if (shouldAutoStartSingleDevice) {
      await selectDeviceAndStart(
        fetchedDevices.firstWhere((device) => device.isConnected),
      );
      return;
    }

    _exitGetStartedIfWorkspaceReady();
  }

  List<LogEntry> get _currentLogsSnapshot =>
      List<LogEntry>.unmodifiable([..._logsBuffer.getLogs(), ..._pendingLogs]);

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

  void _handleDeviceRepositoryChanged() {
    if (_disposed) return;

    final nextDevices = _deviceRepository.devices;
    if (const ListEquality<Device>().equals(devices, nextDevices)) {
      _notify();
      return;
    }

    unawaited(_applyRepositoryDevices(nextDevices));
  }

  Future<void> _applyRepositoryDevices(List<Device> nextDevices) async {
    await _applyFetchedDevices(nextDevices);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _deviceRepository.removeListener(_handleDeviceRepositoryChanged);
    _flushTimer?.cancel();
    filterCtrl.removeListener(_onSubControllerChanged);
    searchCtrl.removeListener(_onSubControllerChanged);
    selectionCtrl.removeListener(_onSubControllerChanged);
    filterCtrl.dispose();
    searchCtrl.dispose();
    selectionCtrl.dispose();
    wirelessController.dispose();
    unawaited(_logSub?.cancel());
    unawaited(_deviceSessionService.dispose());
    scrollController.dispose();
    logLinesController.dispose();
    super.dispose();
  }
}

