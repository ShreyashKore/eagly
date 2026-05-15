import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/device.dart';
import '../../data/log_entry.dart';
import '../../data/log_level.dart';
import '../../data/log_tab_settings.dart';
import '../../data/log_view_mode.dart';
import '../../services/device_repository.dart';
import '../../services/device_session_service.dart';
import '../../services/log_file_service.dart';
import '../../utils/text_search_pattern.dart';
import '../wireless_connection/wireless_connection_controller.dart';
import 'components/inline_filter_bar.dart';
import 'controllers/log_tab_filter_controller.dart';
import 'controllers/log_tab_log_store.dart';
import 'controllers/log_tab_search_controller.dart';
import 'controllers/log_tab_selection_controller.dart';

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
       _deviceSessionService = deviceSessionService ?? DeviceSessionService(),
       _logStore = LogTabLogStore(baseCapacity: initialSettings.logLinesLimit) {
    _filterController = LogTabFilterController(
      initialSelectedLogLevel: initialSettings.selectedLogLevel,
      initialFilterViewMode: initialSettings.filterViewMode,
      isIosContextProvider: () => isIosLogContext,
      onAppliedFiltersChanged: _handleAppliedFiltersChanged,
    );
    _searchController = LogTabSearchController();
    _selectionController = LogTabSelectionController();

    _filterController.addListener(_notify);
    _searchController.addListener(_notify);
    _selectionController.addListener(_notify);

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
  final LogTabLogStore _logStore;
  late final LogTabFilterController _filterController;
  late final LogTabSearchController _searchController;
  late final LogTabSelectionController _selectionController;
  late final WirelessConnectionController wirelessController;

  final ScrollController scrollController = ScrollController();
  final TextEditingController logLinesController = TextEditingController();

  StreamSubscription<LogEntry>? _logSub;
  Timer? _flushTimer;

  var devices = <Device>[];
  Device? selectedDevice;
  var logcatState = LogcatState.stopped;

  var _editingLogLinesLimit = false;
  var _logViewerRevision = 0;
  var _disposed = false;
  var _showGetStarted = true;
  final String _title;
  String? _importedFileName;
  LogTabSettings _settings;

  List<LogEntry>? _cachedFilteredLogs;
  int _lastLogsLength = 0;
  int? _lastLogsFirstId;
  int? _lastLogsLastId;
  String _lastAppliedFilterSignature = '';

  TextEditingController get filterController => _filterController.filterController;
  FocusNode get filterFocusNode => _filterController.filterFocusNode;
  TextEditingController get packageFilterController =>
      _filterController.packageFilterController;
  FocusNode get packageFilterFocusNode =>
      _filterController.packageFilterFocusNode;
  TextEditingController get pidTidFilterController =>
      _filterController.pidTidFilterController;
  FocusNode get pidTidFilterFocusNode =>
      _filterController.pidTidFilterFocusNode;
  TextEditingController get tagFilterController =>
      _filterController.tagFilterController;
  FocusNode get tagFilterFocusNode => _filterController.tagFilterFocusNode;
  InlineFilterTextController get inlineFilterController =>
      _filterController.inlineFilterController;
  FocusNode get inlineFilterFocusNode => _filterController.inlineFilterFocusNode;
  TextEditingController get searchController => _searchController.searchController;
  FocusNode get searchFocusNode => _searchController.searchFocusNode;

  List<LogEntry> get logs => _logStore.logs;

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
  bool get searchBarVisible => _searchController.searchBarVisible;
  bool get searchCaseSensitive => _searchController.searchCaseSensitive;
  bool get searchWholeWord => _searchController.searchWholeWord;
  bool get searchRegex => _searchController.searchRegex;
  int get searchCurrentMatch => _searchController.searchCurrentMatch;
  String? get selectedSearchText => _searchController.selectedSearchText;
  bool get rowSelectionMode => _selectionController.rowSelectionMode;
  Set<int> get selectedRowIndices => _selectionController.selectedRowIndices;
  bool get hasSelectedRows => _selectionController.hasSelectedRows;
  int get selectedRowCount => _selectionController.selectedRowCount;
  int? get rowSelectionAnchorIndex => _selectionController.rowSelectionAnchorIndex;
  bool get editingLogLinesLimit => _editingLogLinesLimit;
  int get logViewerRevision => _logViewerRevision;
  bool get isReadingFromFile => _importedFileName != null;
  bool get isRunning => logcatState != LogcatState.stopped;
  bool get isPaused => logcatState == LogcatState.paused;
  bool get hasLogs => _logStore.hasLogs;
  bool get hasAnyCachedLogs => _logStore.hasAnyCachedLogs;
  bool get hasSelectedDevice => selectedDevice != null;
  bool get hasConnectedSelectedDevice => selectedDevice?.isConnected == true;
  bool get hasVisibleWorkspace => hasSelectedDevice || hasLogs;
  int get totalLogsMemoryBytes => _logStore.totalMemoryBytes;
  String get appliedInlineSearchQuery => _searchController.appliedInlineSearchQuery;
  String get inlineSearchQuery => _searchController.inlineSearchQuery;
  TextSearchConfig get inlineSearch => _searchController.inlineSearch;
  TextSearchConfig get appliedInlineSearch => _searchController.appliedInlineSearch;
  TextSearchPattern get inlineSearchPattern => _searchController.inlineSearchPattern;
  bool get inlineSearchHasError => _searchController.inlineSearchHasError;
  String? get inlineSearchErrorText => _searchController.inlineSearchErrorText;
  bool get isLoadingDevices => _deviceRepository.isLoading;
  bool get hasAttemptedDeviceLoad => _deviceRepository.hasAttemptedLoad;
  List<String> get recentMessageFilters => _filterController.recentMessageFilters;
  List<String> get recentPackageFilters => _filterController.recentPackageFilters;
  List<String> get recentPidTidFilters => _filterController.recentPidTidFilters;
  List<String> get recentTagFilters => _filterController.recentTagFilters;
  List<String> get knownInlinePackageFilters =>
      _filterController.knownInlinePackageFilters(logs);

  bool get wrapText => _settings.wrapText;
  bool get autoScroll => _settings.autoScroll;
  LogLevel get selectedLogLevel => _filterController.selectedLogLevel;
  LogFilterViewMode get filterViewMode => _filterController.filterViewMode;
  int get logLinesLimit => _settings.logLinesLimit;
  Set<String> get hiddenColumns => _settings.hiddenColumns;
  Map<String, double> get columnWidths => _settings.columnWidths;

  bool get isIosLogContext {
    if (selectedDevice is IosDevice) return true;
    if (selectedDevice is AndroidDevice) return false;

    final sampleLevel = logs.firstWhereOrNull(
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

  void _syncSettingsFromFilters() {
    _settings = _settings.copyWith(
      selectedLogLevel: _filterController.selectedLogLevel,
      filterViewMode: _filterController.filterViewMode,
    );
  }

  void _handleAppliedFiltersChanged() {
    _syncSettingsFromFilters();
    _selectionController.clearSelectedRows(notify: false);
    _syncLogBufferFilter();
    _invalidateFilteredLogs();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      final focusNode = switch (filterViewMode) {
        LogFilterViewMode.inline => inlineFilterFocusNode,
        LogFilterViewMode.classic => filterFocusNode,
      };
      final textController = switch (filterViewMode) {
        LogFilterViewMode.inline => inlineFilterController,
        LogFilterViewMode.classic => filterController,
      };
      focusNode.requestFocus();
      textController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: textController.text.length,
      );
    });
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
    _selectionController.clearSelectedRows(notify: false);
    _logStore.clearAll();
    _invalidateFilteredLogs();
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

    _selectionController.clearSelectedRows(notify: false);
    selectedDevice = null;
    _importedFileName = result.fileName;
    logs = result.logs!;
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
    _selectionController.toggleRowSelectionMode();
  }

  void setRowSelectionMode(bool value) {
    _selectionController.setRowSelectionMode(value);
  }

  bool isRowSelected(int filteredIndex) {
    return _selectionController.isRowSelected(filteredIndex);
  }

  bool? beginRowSelectionGesture(
    int filteredIndex, {
    bool shiftPressed = false,
  }) {
    return _selectionController.beginRowSelectionGesture(
      filteredIndex,
      filteredLogs,
      shiftPressed: shiftPressed,
    );
  }

  void setRowSelected(int filteredIndex, bool selected) {
    _selectionController.setRowSelected(filteredIndex, selected, filteredLogs);
  }

  void setSelectedRows(Set<int> indices) {
    _selectionController.setSelectedRows(indices, filteredLogs);
  }

  void selectRowRangeTo(int filteredIndex) {
    _selectionController.selectRowRangeTo(filteredIndex, filteredLogs);
  }

  void clearSelectedRows({bool notify = true}) {
    _selectionController.clearSelectedRows(notify: notify);
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
    final selectedIndices = _selectionTargetIndicesForCopy(
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
    _filterController.clearFilter();
    focusFilterInputs();
  }

  void onInlineFilterChanged(String value) {
    _filterController.onInlineFilterChanged(value);
  }

  void setInlineFilterText(
    String value, {
    TextSelection? selection,
    bool applyImmediately = false,
  }) {
    _filterController.setInlineFilterText(
      value,
      selection: selection,
      applyImmediately: applyImmediately,
    );
  }

  void onSearchChanged(String value) {
    _filterController.onSearchChanged(value);
  }

  void onPackageFilterChanged(String value) {
    _filterController.onPackageFilterChanged(value);
  }

  void onPidTidFilterChanged(String value) {
    _filterController.onPidTidFilterChanged(value);
  }

  void onTagFilterChanged(String value) {
    _filterController.onTagFilterChanged(value);
  }

  void selectMessageFilterSuggestion(String value) {
    _filterController.selectMessageFilterSuggestion(value);
  }

  void selectPackageFilterSuggestion(String value) {
    _filterController.selectPackageFilterSuggestion(value);
  }

  void selectPidTidFilterSuggestion(String value) {
    _filterController.selectPidTidFilterSuggestion(value);
  }

  void selectTagFilterSuggestion(String value) {
    _filterController.selectTagFilterSuggestion(value);
  }

  void applyFiltersNow() {
    _filterController.applyFiltersNow();
  }

  void setSelectedLogLevel(LogLevel level) {
    _filterController.setSelectedLogLevel(level);
  }

  void setFilterViewMode(LogFilterViewMode mode) {
    _filterController.setFilterViewMode(mode);
    _syncSettingsFromFilters();
    focusFilterInputs();
  }

  void toggleWrapText() {
    _logViewerRevision++;
    _updateSettings(_settings.copyWith(wrapText: !wrapText));
  }

  void toggleAutoScroll() {
    _updateSettings(_settings.copyWith(autoScroll: !autoScroll));
  }

  void setSelectedSearchText(String? value) {
    _searchController.setSelectedSearchText(value);
  }

  void setHiddenColumns(Set<String> columns) {
    _logViewerRevision++;
    _searchController.invalidateSearchMatches();
    _updateSettings(_settings.copyWith(hiddenColumns: Set.of(columns)));
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
    _settings = _settings.copyWith(logLinesLimit: parsed);

    _replaceStoredLogs(storedLogs);
    if (_logStore.size < previousCount) {
      _selectionController.clearSelectedRows(notify: false);
    }

    _notify();
    return true;
  }

  void toggleSearchBar() {
    _searchController.toggleSearchBar(disableAutoScroll: disableAutoScroll);
    if (_searchController.searchBarVisible) {
      _focusSearchField();
    }
  }

  void openSearchBar({String? query}) {
    _searchController.openSearchBar(
      query: query,
      disableAutoScroll: disableAutoScroll,
    );
    _focusSearchField();
  }

  void closeSearchBar() {
    _searchController.closeSearchBar();
  }

  void activateSearchFromSelection() {
    final selectedText = _searchController.selectedSearchText;
    if (selectedText != null) {
      unawaited(Clipboard.setData(ClipboardData(text: selectedText)));
      openSearchBar(query: selectedText);
      return;
    }

    openSearchBar();
  }

  void _focusSearchField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      searchFocusNode.requestFocus();
      searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: searchController.text.length,
      );
    });
  }

  void onInlineSearchChanged(String value) {
    _searchController.onInlineSearchChanged(
      value,
      disableAutoScroll: disableAutoScroll,
    );
  }

  void setSearchCaseSensitive(bool value) {
    _searchController.setSearchCaseSensitive(
      value,
      disableAutoScroll: disableAutoScroll,
    );
  }

  void setSearchWholeWord(bool value) {
    _searchController.setSearchWholeWord(
      value,
      disableAutoScroll: disableAutoScroll,
    );
  }

  void setSearchRegex(bool value) {
    _searchController.setSearchRegex(
      value,
      disableAutoScroll: disableAutoScroll,
    );
  }

  void onSearchNext() {
    _searchController.onSearchNext(
      searchMatchIndices,
      disableAutoScroll: disableAutoScroll,
    );
  }

  void onSearchPrev() {
    _searchController.onSearchPrev(
      searchMatchIndices,
      disableAutoScroll: disableAutoScroll,
    );
  }

  List<LogEntry> get filteredLogs {
    final storedLogs = logs;
    final appliedFilterSignature = _filterController.appliedFilterSignature;
    final firstId = storedLogs.isEmpty ? null : storedLogs.first.id;
    final lastId = storedLogs.isEmpty ? null : storedLogs.last.id;
    if (_cachedFilteredLogs != null &&
        _lastLogsLength == storedLogs.length &&
        _lastLogsFirstId == firstId &&
        _lastLogsLastId == lastId &&
        _lastAppliedFilterSignature == appliedFilterSignature) {
      return _cachedFilteredLogs!;
    }

    _lastLogsLength = storedLogs.length;
    _lastLogsFirstId = firstId;
    _lastLogsLastId = lastId;
    _lastAppliedFilterSignature = appliedFilterSignature;
    _cachedFilteredLogs = _logStore.search(_filterController.matchesLogFilters);
    return _cachedFilteredLogs!;
  }

  List<int> get searchMatchIndices =>
      _searchController.searchMatchIndicesFor(filteredLogs, hiddenColumns);

  int currentSearchMatchLogIndex(List<int> matches) {
    return _searchController.currentSearchMatchLogIndex(matches);
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
    _searchController.invalidateSearchMatches();
  }

  void updateInlineSearch(
    TextSearchConfig value, {
    bool applyImmediately = false,
  }) {
    _searchController.updateInlineSearch(
      value,
      applyImmediately: applyImmediately,
      disableAutoScroll: disableAutoScroll,
    );
  }

  void _syncLogBufferFilter() {
    _logStore.setRetentionFilter(_filterController.retentionFilter);
  }

  void _replaceStoredLogs(Iterable<LogEntry> entries) {
    _logStore.replaceStoredLogs(
      entries,
      baseCapacity: logLinesLimit,
      retentionFilter: _filterController.retentionFilter,
    );
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
    final result = _logStore.appendImmediate(entry);
    if (result.didEvictStoredLogs) {
      _selectionController.clearSelectedRows(notify: false);
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
      _selectionController.clearSelectedRows(notify: false);
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

    _selectionController.clearSelectedRows(notify: false);
    _importedFileName = null;
    _logStore.clearAll();
    _invalidateFilteredLogs();
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
      _logStore.queuePendingLog(logEntry);
    });

    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_disposed) return;

      final flushResult = _logStore.flushPending();
      if (!flushResult.hadPendingLogs) return;

      if (flushResult.didEvictStoredLogs) {
        _selectionController.clearSelectedRows(notify: false);
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

  List<LogEntry> get _currentLogsSnapshot => _logStore.currentLogsSnapshot;

  List<int> _selectionTargetIndicesForCopy(int? clickedFilteredIndex) {
    final filteredSnapshot = filteredLogs;
    final selectedIndices =
        _selectionController.selectedRowIndices
            .where(
              (index) =>
                  index >= 0 &&
                  index < filteredSnapshot.length &&
                  filteredSnapshot[index].isUserSelectable,
            )
            .toList()
          ..sort();

    if (clickedFilteredIndex == null) {
      return selectedIndices;
    }

    final clickedIsCopyable = clickedFilteredIndex >= 0 &&
        clickedFilteredIndex < filteredSnapshot.length &&
        filteredSnapshot[clickedFilteredIndex].isUserSelectable;
    if (!clickedIsCopyable) {
      return selectedIndices;
    }

    if (selectedIndices.isNotEmpty &&
        selectedIndices.contains(clickedFilteredIndex)) {
      return selectedIndices;
    }
    return [clickedFilteredIndex];
  }

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
    unawaited(_logSub?.cancel());
    unawaited(_deviceSessionService.dispose());
    scrollController.dispose();
    logLinesController.dispose();
    _filterController
      ..removeListener(_notify)
      ..dispose();
    _searchController
      ..removeListener(_notify)
      ..dispose();
    _selectionController
      ..removeListener(_notify)
      ..dispose();
    super.dispose();
  }
}

