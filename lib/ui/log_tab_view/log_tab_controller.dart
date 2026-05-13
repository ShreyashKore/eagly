import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/device.dart';
import '../../data/log_column.dart';
import '../../data/log_entry.dart';
import '../../data/log_level.dart';
import '../../data/log_tab_settings.dart';
import '../../services/device_repository.dart';
import '../../services/device_session_service.dart';
import '../../services/log_file_service.dart';
import '../../utils/log_buffer.dart';
import '../../utils/text_search_pattern.dart';
import 'controllers/log_tab_filter_controller.dart';
import 'controllers/log_tab_search_controller.dart';
import 'controllers/log_tab_selection_controller.dart';
import '../wireless_connection/wireless_connection_controller.dart';

enum LogcatState { stopped, running, paused }

enum LogCopyFormat { messageOnly, timestampAndMessage, fullLine }

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
    _filterState = LogTabFilterController(
      onChanged: _notify,
      onFiltersApplied: () {
        _syncLogBufferFilter();
        _invalidateFilteredLogs();
      },
      onSelectionCleared: () => clearSelectedRows(notify: false),
      isDisposed: () => _disposed,
    );
    _searchState = LogTabSearchController(
      onChanged: _notify,
      onAutoScrollInterrupt: disableAutoScroll,
      isDisposed: () => _disposed,
    );
    _selectionState = LogTabSelectionController(
      onChanged: _notify,
      filteredLogsProvider: () => filteredLogs,
    );
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
  late final LogTabFilterController _filterState;
  late final LogTabSearchController _searchState;
  late final LogTabSelectionController _selectionState;
  late final WirelessConnectionController wirelessController;

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

  List<LogEntry>? _cachedFilteredLogs;
  int _lastLogsLength = 0;
  String _lastFilterQuery = '';
  String _lastPackageFilterQuery = '';
  String _lastPidTidFilterQuery = '';
  String _lastTagFilterQuery = '';
  LogLevel _lastLogLevel = LogLevel.verbose;

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
  TextEditingController get filterController => _filterState.messageController;
  FocusNode get filterFocusNode => _filterState.messageFocusNode;
  TextEditingController get packageFilterController =>
      _filterState.packageController;
  FocusNode get packageFilterFocusNode => _filterState.packageFocusNode;
  TextEditingController get pidTidFilterController =>
      _filterState.pidTidController;
  FocusNode get pidTidFilterFocusNode => _filterState.pidTidFocusNode;
  TextEditingController get tagFilterController => _filterState.tagController;
  FocusNode get tagFilterFocusNode => _filterState.tagFocusNode;
  TextEditingController get searchController => _searchState.searchController;
  FocusNode get searchFocusNode => _searchState.searchFocusNode;
  String get searchQuery => _filterState.searchQuery;
  String get packageFilterQuery => _filterState.packageFilterQuery;
  String get pidTidFilterQuery => _filterState.pidTidFilterQuery;
  String get tagFilterQuery => _filterState.tagFilterQuery;
  bool get searchBarVisible => _searchState.searchBarVisible;
  bool get searchCaseSensitive => _searchState.searchCaseSensitive;
  bool get searchWholeWord => _searchState.searchWholeWord;
  bool get searchRegex => _searchState.searchRegex;
  int get searchCurrentMatch => _searchState.searchCurrentMatch;
  String? get selectedSearchText => _searchState.selectedSearchText;
  bool get rowSelectionMode => _selectionState.rowSelectionMode;
  Set<int> get selectedRowIndices => _selectionState.selectedRowIndices;
  bool get hasSelectedRows => _selectionState.hasSelectedRows;
  int get selectedRowCount => _selectionState.selectedRowCount;
  int? get rowSelectionAnchorIndex => _selectionState.rowSelectionAnchorIndex;
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
  String get appliedInlineSearchQuery => _searchState.appliedInlineSearchQuery;
  String get inlineSearchQuery => _searchState.inlineSearchQuery;
  TextSearchPattern get inlineSearchPattern => _searchState.inlineSearchPattern;
  bool get inlineSearchHasError => _searchState.inlineSearchHasError;
  String? get inlineSearchErrorText => _searchState.inlineSearchErrorText;
  bool get isLoadingDevices => _deviceRepository.isLoading;
  bool get hasAttemptedDeviceLoad => _deviceRepository.hasAttemptedLoad;
  List<String> get recentMessageFilters => _filterState.recentMessageFilters;
  List<String> get recentPackageFilters => _filterState.recentPackageFilters;
  List<String> get recentPidTidFilters => _filterState.recentPidTidFilters;
  List<String> get recentTagFilters => _filterState.recentTagFilters;

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

  void _exitGetStartedIfWorkspaceReady() {
    if (selectedDevice != null || logs.isNotEmpty) {
      _exitGetStarted();
    }
  }

  Future<void> bootstrapInitialLoad() async {
    await loadDevices(autoStartSingleIfAvailable: true);
  }

  void focusFilterInputs() {
    _filterState.focusPrimaryField();
  }

  Future<void> loadDevices({bool autoStartSingleIfAvailable = false}) async {
    await _deviceRepository.refreshDevices(force: true, showLoading: true);
    if (_disposed) return;
    await _applyFetchedDevices(
      _deviceRepository.devices,
      autoStartSingleIfAvailable: autoStartSingleIfAvailable,
    );
    _notify();
  }

  void clearLogs() {
    clearSelectedRows(notify: false);
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

    clearSelectedRows(notify: false);
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

  void toggleRowSelectionMode() {
    _selectionState.toggleRowSelectionMode();
  }

  void setRowSelectionMode(bool value) {
    _selectionState.setRowSelectionMode(value);
  }

  bool isRowSelected(int filteredIndex) {
    return _selectionState.isRowSelected(filteredIndex);
  }

  bool? beginRowSelectionGesture(
    int filteredIndex, {
    bool shiftPressed = false,
  }) {
    return _selectionState.beginRowSelectionGesture(
      filteredIndex,
      shiftPressed: shiftPressed,
    );
  }

  void setRowSelected(int filteredIndex, bool selected) {
    _selectionState.setRowSelected(filteredIndex, selected);
  }

  void setSelectedRows(Set<int> indices) {
    _selectionState.setSelectedRows(indices);
  }

  void selectRowRangeTo(int filteredIndex) {
    _selectionState.selectRowRangeTo(filteredIndex);
  }

  void clearSelectedRows({bool notify = true}) {
    _selectionState.clearSelectedRows(notify: notify);
  }

  Future<int> copyAllLogs() {
    return _copyLogsToClipboard(
      _currentLogsSnapshot.where((entry) => entry.isCopyable),
      format: LogCopyFormat.fullLine,
    );
  }

  Future<int> copyRowsForContextMenu({
    required int? clickedFilteredIndex,
    required LogCopyFormat format,
  }) {
    final selectedIndices = _selectionState.selectionTargetIndicesForCopy(
      clickedFilteredIndex,
    );
    return copyFilteredRows(selectedIndices, format: format);
  }

  Future<int> copyFilteredRows(
    Iterable<int> filteredIndices, {
    required LogCopyFormat format,
  }) {
    final filteredSnapshot = List<LogEntry>.of(filteredLogs);
    final indices = filteredIndices.toSet().where((index) {
      return index >= 0 && index < filteredSnapshot.length;
    }).toList()..sort();

    if (indices.isEmpty) {
      return Future<int>.value(0);
    }

    final entries = [
      for (final index in indices)
        if (filteredSnapshot[index].isCopyable) filteredSnapshot[index],
    ];
    return _copyLogsToClipboard(entries, format: format);
  }

  String formatLogsForClipboard(
    Iterable<LogEntry> entries, {
    required LogCopyFormat format,
  }) {
    return entries
        .map((entry) => _formatLogEntryForCopy(entry, format))
        .join('\n');
  }

  void clearFilter() {
    _filterState.clear();
  }

  void onSearchChanged(String value) {
    _filterState.onSearchChanged(value);
  }

  void onPackageFilterChanged(String value) {
    _filterState.onPackageFilterChanged(value);
  }

  void onPidTidFilterChanged(String value) {
    _filterState.onPidTidFilterChanged(value);
  }

  void onTagFilterChanged(String value) {
    _filterState.onTagFilterChanged(value);
  }

  void selectMessageFilterSuggestion(String value) {
    _filterState.selectMessageFilterSuggestion(value);
  }

  void selectPackageFilterSuggestion(String value) {
    _filterState.selectPackageFilterSuggestion(value);
  }

  void selectPidTidFilterSuggestion(String value) {
    _filterState.selectPidTidFilterSuggestion(value);
  }

  void selectTagFilterSuggestion(String value) {
    _filterState.selectTagFilterSuggestion(value);
  }

  void applyFiltersNow() {
    _filterState.applyFiltersNow();
  }

  void setSelectedLogLevel(LogLevel level) {
    _updateSettings(_settings.copyWith(selectedLogLevel: level));
    clearSelectedRows(notify: false);
    _syncLogBufferFilter();
    _invalidateFilteredLogs();
  }

  void toggleWrapText() {
    _logViewerRevision++;
    _updateSettings(_settings.copyWith(wrapText: !wrapText));
  }

  void toggleAutoScroll() {
    _updateSettings(_settings.copyWith(autoScroll: !autoScroll));
  }

  void setSelectedSearchText(String? value) {
    _searchState.setSelectedSearchText(value);
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
    final storedLogs = logs;
    final previousCount = storedLogs.length;
    _updateSettings(_settings.copyWith(logLinesLimit: parsed));

    _replaceStoredLogs(storedLogs);
    if (_logsBuffer.size < previousCount) {
      clearSelectedRows(notify: false);
    }

    _notify();
    return true;
  }

  void toggleSearchBar() {
    _searchState.toggleSearchBar();
  }

  void openSearchBar({String? query}) {
    _searchState.openSearchBar(query: query);
  }

  void closeSearchBar() {
    _searchState.closeSearchBar();
  }

  void activateSearchFromSelection() {
    _searchState.activateSearchFromSelection();
  }

  void onInlineSearchChanged(String value) {
    _searchState.onInlineSearchChanged(value);
  }

  void setSearchCaseSensitive(bool value) {
    _searchState.setSearchCaseSensitive(value);
  }

  void setSearchWholeWord(bool value) {
    _searchState.setSearchWholeWord(value);
  }

  void setSearchRegex(bool value) {
    _searchState.setSearchRegex(value);
  }

  void onSearchNext() {
    final matches = searchMatchIndices;
    _searchState.onSearchNext(matches);
  }

  void onSearchPrev() {
    final matches = searchMatchIndices;
    _searchState.onSearchPrev(matches);
  }

  List<LogEntry> get filteredLogs {
    if (_cachedFilteredLogs != null &&
        _lastLogsLength == _logsBuffer.size &&
        _lastFilterQuery == _filterState.appliedSearchQuery &&
        _lastPackageFilterQuery == _filterState.appliedPackageFilterQuery &&
        _lastPidTidFilterQuery == _filterState.appliedPidTidFilterQuery &&
        _lastTagFilterQuery == _filterState.appliedTagFilterQuery &&
        _lastLogLevel == selectedLogLevel) {
      return _cachedFilteredLogs!;
    }

    _lastLogsLength = _logsBuffer.size;
    _lastFilterQuery = _filterState.appliedSearchQuery;
    _lastPackageFilterQuery = _filterState.appliedPackageFilterQuery;
    _lastPidTidFilterQuery = _filterState.appliedPidTidFilterQuery;
    _lastTagFilterQuery = _filterState.appliedTagFilterQuery;
    _lastLogLevel = selectedLogLevel;

    _cachedFilteredLogs = _logsBuffer.search(_matchesLogFilters);

    return _cachedFilteredLogs!;
  }

  List<int> get searchMatchIndices {
    return _searchState.searchMatchIndices(
      filteredLogs: filteredLogs,
      hiddenColumns: hiddenColumns,
    );
  }

  int currentSearchMatchLogIndex(List<int> matches) {
    return _searchState.currentSearchMatchLogIndex(matches);
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
    _searchState.invalidateSearchMatches();
  }

  bool _matchesLogFilters(LogEntry log) {
    return _filterState.matchesLog(
      log,
      selectedLevel: effectiveSelectedLogLevel,
    );
  }

  bool get _hasActiveRetentionFilter {
    return _filterState.hasActiveRetentionFilter(effectiveSelectedLogLevel);
  }

  LogFilter<LogEntry>? get _retentionFilter =>
      _filterState.retentionFilter(effectiveSelectedLogLevel);

  void _syncLogBufferFilter() {
    _logsBuffer.setFilter(_retentionFilter);
  }

  void _replaceStoredLogs(Iterable<LogEntry> entries) {
    final nextBuffer = LogBuffer<LogEntry>(baseCapacity: logLinesLimit);
    nextBuffer.setFilter(_retentionFilter);
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

  void _appendImmediateLogEntry(LogEntry entry) {
    final evictedLogs = _logsBuffer.append(entry);
    final addedBytes = _estimateLogEntryBytes(entry);
    final evictedBytes = _estimateLogsBytes(evictedLogs);

    _logsMemoryBytes += addedBytes - evictedBytes;
    if (_logsMemoryBytes < 0) {
      _logsMemoryBytes = 0;
    }

    if (evictedLogs.isNotEmpty) {
      clearSelectedRows(notify: false);
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

    final selectedDeviceJustDisconnected =
        previousSelectedDevice != null &&
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

    final shouldAutoStartSingleDevice =
        autoStartSingleIfAvailable &&
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

  Future<void> setSelectedDevice(Device? device) async {
    if (device == null) {
      if (selectedDevice == null) return;
      clearSelectedRows(notify: false);
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

  Future<void> startLogcat() async {
    if (selectedDevice == null) return;
    _exitGetStartedIfWorkspaceReady();

    await _stopLogcatInternal(resetState: false);
    if (_disposed) return;

    clearSelectedRows(notify: false);
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
        clearSelectedRows(notify: false);
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

  List<LogEntry> get _currentLogsSnapshot =>
      List<LogEntry>.unmodifiable([..._logsBuffer.getLogs(), ..._pendingLogs]);

  Future<int> _copyLogsToClipboard(
    Iterable<LogEntry> entries, {
    required LogCopyFormat format,
  }) async {
    final snapshot = List<LogEntry>.of(entries);
    if (snapshot.isEmpty) return 0;

    final text = formatLogsForClipboard(snapshot, format: format);
    await Clipboard.setData(ClipboardData(text: text));
    return snapshot.length;
  }

  String _formatLogEntryForCopy(LogEntry log, LogCopyFormat format) {
    return switch (format) {
      LogCopyFormat.messageOnly => log.message,
      LogCopyFormat.timestampAndMessage => '${log.timestamp} ${log.message}',
      LogCopyFormat.fullLine =>
        '${log.timestamp} ${log.packageName ?? log.pid} ${log.tid} ${log.level} ${log.tag}: ${log.message}',
    };
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
    wirelessController.dispose();
    _filterState.dispose();
    _searchState.dispose();
    unawaited(_logSub?.cancel());
    unawaited(_deviceSessionService.dispose());
    scrollController.dispose();
    logLinesController.dispose();
    super.dispose();
  }
}
