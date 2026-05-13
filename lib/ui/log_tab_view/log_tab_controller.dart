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
import '../wireless_connection/wireless_connection_controller.dart';
import 'log_filter_controller.dart';
import 'log_inline_search_controller.dart';
import 'log_row_selection_controller.dart';
import 'log_stream_controller.dart';

export 'log_stream_controller.dart' show LogcatState;

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
       _deviceSessionService =
           deviceSessionService ?? DeviceSessionService() {
    filterCtrl = LogFilterController(
      selectedLogLevelProvider: () => selectedLogLevel,
    )..onFiltersApplied = _onFiltersApplied;

    streamCtrl = LogStreamController(
      initialLogLinesLimit: initialSettings.logLinesLimit,
      deviceSessionService: _deviceSessionService,
      retentionFilterProvider: () => _retentionFilter,
      scrollController: scrollController,
      autoScrollProvider: () => autoScroll,
      onRowsEvicted: () => rowSelectionCtrl.clearSelectedRows(notify: false),
      onLogsChanged: _invalidateFilteredLogs,
    );

    rowSelectionCtrl = LogRowSelectionController(
      filteredLogsProvider: () => filteredLogs,
    );

    inlineSearchCtrl = LogInlineSearchController(
      hiddenColumnsProvider: () => hiddenColumns,
      filteredLogsProvider: () => filteredLogs,
    )..onDisableAutoScroll = disableAutoScroll;

    filterCtrl.addListener(_notify);
    streamCtrl.addListener(_notify);
    rowSelectionCtrl.addListener(_notify);
    inlineSearchCtrl.addListener(_notify);

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

    filterCtrl.initFromSettings(
      searchQuery: '',
      packageFilterQuery: '',
      pidTidFilterQuery: '',
      tagFilterQuery: '',
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

  late final LogFilterController filterCtrl;
  late final LogStreamController streamCtrl;
  late final LogRowSelectionController rowSelectionCtrl;
  late final LogInlineSearchController inlineSearchCtrl;

  final ScrollController scrollController = ScrollController();
  final TextEditingController logLinesController = TextEditingController();

  var devices = <Device>[];
  var _editingLogLinesLimit = false;
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

  // ── filter forwarders ────────────────────────────────────────────────
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

  // ── inline search forwarders ─────────────────────────────────────────
  TextEditingController get searchController =>
      inlineSearchCtrl.searchController;
  FocusNode get searchFocusNode => inlineSearchCtrl.searchFocusNode;

  bool get searchBarVisible => inlineSearchCtrl.searchBarVisible;
  bool get searchCaseSensitive => inlineSearchCtrl.searchCaseSensitive;
  bool get searchWholeWord => inlineSearchCtrl.searchWholeWord;
  bool get searchRegex => inlineSearchCtrl.searchRegex;
  int get searchCurrentMatch => inlineSearchCtrl.searchCurrentMatch;
  String? get selectedSearchText => inlineSearchCtrl.selectedSearchText;
  String get appliedInlineSearchQuery =>
      inlineSearchCtrl.appliedInlineSearchQuery;
  String get inlineSearchQuery => inlineSearchCtrl.inlineSearchQuery;
  TextSearchPattern get inlineSearchPattern =>
      inlineSearchCtrl.inlineSearchPattern;
  bool get inlineSearchHasError => inlineSearchCtrl.inlineSearchHasError;
  String? get inlineSearchErrorText => inlineSearchCtrl.inlineSearchErrorText;

  // ── row selection forwarders ─────────────────────────────────────────
  bool get rowSelectionMode => rowSelectionCtrl.rowSelectionMode;
  Set<int> get selectedRowIndices => rowSelectionCtrl.selectedRowIndices;
  bool get hasSelectedRows => rowSelectionCtrl.hasSelectedRows;
  int get selectedRowCount => rowSelectionCtrl.selectedRowCount;
  int? get rowSelectionAnchorIndex => rowSelectionCtrl.rowSelectionAnchorIndex;

  // ── stream / logcat forwarders ───────────────────────────────────────
  LogcatState get logcatState => streamCtrl.logcatState;
  bool get isRunning => streamCtrl.isRunning;
  bool get isPaused => streamCtrl.isPaused;
  bool get hasLogs => streamCtrl.hasLogs;
  bool get hasAnyCachedLogs => streamCtrl.hasAnyCachedLogs;
  int get totalLogsMemoryBytes => streamCtrl.totalLogsMemoryBytes;

  Device? get selectedDevice => streamCtrl.selectedDevice;
  set selectedDevice(Device? v) => streamCtrl.selectedDevice = v;

  // ── settings ─────────────────────────────────────────────────────────
  bool get wrapText => _settings.wrapText;
  bool get autoScroll => _settings.autoScroll;
  LogLevel get selectedLogLevel => _settings.selectedLogLevel;
  int get logLinesLimit => _settings.logLinesLimit;
  Set<String> get hiddenColumns => _settings.hiddenColumns;
  Map<String, double> get columnWidths => _settings.columnWidths;

  bool get showGetStarted => _showGetStarted;
  bool get editingLogLinesLimit => _editingLogLinesLimit;
  int get logViewerRevision => _logViewerRevision;
  bool get isReadingFromFile => _importedFileName != null;
  bool get hasSelectedDevice => selectedDevice != null;
  bool get hasConnectedSelectedDevice => selectedDevice?.isConnected == true;
  bool get hasVisibleWorkspace => hasSelectedDevice || hasLogs;
  bool get isLoadingDevices => _deviceRepository.isLoading;
  bool get hasAttemptedDeviceLoad => _deviceRepository.hasAttemptedLoad;

  List<LogEntry> get logs => streamCtrl.getLogs();
  set logs(List<LogEntry> value) =>
      streamCtrl.replaceStoredLogs(value, logLinesLimit);

  String get title {
    if (selectedDevice != null) return selectedDevice!.displayLabel.primary;
    if (_importedFileName != null) return _importedFileName!;
    if (_showGetStarted) return 'Get Started';
    return _title;
  }

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
    if (!_disposed) notifyListeners();
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
    if (selectedDevice != null || logs.isNotEmpty) _exitGetStarted();
  }

  void _onFiltersApplied() {
    rowSelectionCtrl.clearSelectedRows(notify: false);
    _syncLogBufferFilter();
    _invalidateFilteredLogs();
  }

  LogFilter<LogEntry>? get _retentionFilter =>
      filterCtrl.hasActiveRetentionFilter ? filterCtrl.matchesLogFilters : null;

  void _syncLogBufferFilter() => streamCtrl.syncFilter();

  void _invalidateFilteredLogs() {
    _cachedFilteredLogs = null;
    inlineSearchCtrl.invalidateSearchMatches();
  }

  // ── public API ────────────────────────────────────────────────────────

  Future<void> bootstrapInitialLoad() async {
    await loadDevices(autoStartSingleIfAvailable: true);
  }

  void focusFilterInputs() => filterCtrl.focusFilterInputs();

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
    rowSelectionCtrl.clearSelectedRows(notify: false);
    streamCtrl.clearStoredLogs();
    streamCtrl.clearPendingLogs();
    _notify();
  }

  Future<LogExportResult> exportLogs() async {
    return LogFileService.exportLogs(logs, selectedDevice);
  }

  Future<LogImportResult> importLogs() async {
    final result = await LogFileService.importLogs();
    if (_disposed || !result.isSuccess || result.logs == null) return result;

    await streamCtrl.stopInternal(resetState: false);
    if (_disposed) return result;

    rowSelectionCtrl.clearSelectedRows(notify: false);
    selectedDevice = null;
    _importedFileName = result.fileName;
    logs = result.logs!;
    streamCtrl.clearPendingLogs();
    streamCtrl.logcatState = LogcatState.stopped;
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

  // row selection
  void toggleRowSelectionMode() => rowSelectionCtrl.toggleRowSelectionMode();
  void setRowSelectionMode(bool value) => rowSelectionCtrl.setRowSelectionMode(value);
  bool isRowSelected(int filteredIndex) => rowSelectionCtrl.isRowSelected(filteredIndex);
  bool? beginRowSelectionGesture(int filteredIndex, {bool shiftPressed = false}) =>
      rowSelectionCtrl.beginRowSelectionGesture(filteredIndex, shiftPressed: shiftPressed);
  void setRowSelected(int filteredIndex, bool selected) =>
      rowSelectionCtrl.setRowSelected(filteredIndex, selected);
  void setSelectedRows(Set<int> indices) => rowSelectionCtrl.setSelectedRows(indices);
  void selectRowRangeTo(int filteredIndex) => rowSelectionCtrl.selectRowRangeTo(filteredIndex);
  void clearSelectedRows({bool notify = true}) => rowSelectionCtrl.clearSelectedRows(notify: notify);

  // copy
  Future<int> copyAllLogs() {
    return _copyLogsToClipboard(
      streamCtrl.currentLogsSnapshot.where((entry) => entry.isCopyable),
      format: LogCopyFormat.fullLine,
    );
  }

  Future<int> copyRowsForContextMenu({
    required int? clickedFilteredIndex,
    required LogCopyFormat format,
  }) {
    return copyFilteredRows(
      _selectionTargetIndicesForCopy(clickedFilteredIndex),
      format: format,
    );
  }

  Future<int> copyFilteredRows(
    Iterable<int> filteredIndices, {
    required LogCopyFormat format,
  }) {
    final filteredSnapshot = List<LogEntry>.of(filteredLogs);
    final indices = filteredIndices.toSet().where((index) {
      return index >= 0 && index < filteredSnapshot.length;
    }).toList()
      ..sort();

    if (indices.isEmpty) return Future<int>.value(0);

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
    return entries.map((e) => _formatLogEntryForCopy(e, format)).join('\n');
  }

  // filter delegation
  void clearFilter() => filterCtrl.clearFilter();
  void onSearchChanged(String value) => filterCtrl.onSearchChanged(value);
  void onPackageFilterChanged(String value) => filterCtrl.onPackageFilterChanged(value);
  void onPidTidFilterChanged(String value) => filterCtrl.onPidTidFilterChanged(value);
  void onTagFilterChanged(String value) => filterCtrl.onTagFilterChanged(value);
  void selectMessageFilterSuggestion(String value) => filterCtrl.selectMessageFilterSuggestion(value);
  void selectPackageFilterSuggestion(String value) => filterCtrl.selectPackageFilterSuggestion(value);
  void selectPidTidFilterSuggestion(String value) => filterCtrl.selectPidTidFilterSuggestion(value);
  void selectTagFilterSuggestion(String value) => filterCtrl.selectTagFilterSuggestion(value);
  void applyFiltersNow() => filterCtrl.applyFiltersNow();

  void setSelectedLogLevel(LogLevel level) {
    _updateSettings(_settings.copyWith(selectedLogLevel: level));
    rowSelectionCtrl.clearSelectedRows(notify: false);
    _syncLogBufferFilter();
    _invalidateFilteredLogs();
  }

  void toggleWrapText() {
    _logViewerRevision++;
    _updateSettings(_settings.copyWith(wrapText: !wrapText));
  }

  void toggleAutoScroll() => _updateSettings(_settings.copyWith(autoScroll: !autoScroll));

  void setHiddenColumns(Set<String> columns) {
    _logViewerRevision++;
    _updateSettings(_settings.copyWith(hiddenColumns: Set.of(columns)));
    inlineSearchCtrl.invalidateSearchMatches();
  }

  void setColumnWidths(Map<String, double> widths) =>
      _updateSettings(_settings.copyWith(columnWidths: Map.of(widths)));

  void setEditingLogLinesLimit(bool value) {
    _editingLogLinesLimit = value;
    if (value) logLinesController.text = logLinesLimit.toString();
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
    streamCtrl.replaceStoredLogs(storedLogs, parsed);
    if (streamCtrl.getLogs().length < previousCount) {
      rowSelectionCtrl.clearSelectedRows(notify: false);
    }
    _notify();
    return true;
  }

  // inline search delegation
  void setSelectedSearchText(String? value) => inlineSearchCtrl.setSelectedSearchText(value);
  void toggleSearchBar() => inlineSearchCtrl.toggleSearchBar();
  void openSearchBar({String? query}) => inlineSearchCtrl.openSearchBar(query: query);
  void closeSearchBar() => inlineSearchCtrl.closeSearchBar();
  void activateSearchFromSelection() => inlineSearchCtrl.activateSearchFromSelection();
  void onInlineSearchChanged(String value) => inlineSearchCtrl.onInlineSearchChanged(value);
  void setSearchCaseSensitive(bool value) => inlineSearchCtrl.setSearchCaseSensitive(value);
  void setSearchWholeWord(bool value) => inlineSearchCtrl.setSearchWholeWord(value);
  void setSearchRegex(bool value) => inlineSearchCtrl.setSearchRegex(value);
  void onSearchNext() => inlineSearchCtrl.onSearchNext();
  void onSearchPrev() => inlineSearchCtrl.onSearchPrev();

  List<LogEntry> get filteredLogs {
    if (_cachedFilteredLogs != null &&
        _lastLogsLength == streamCtrl.logsBufferSize &&
        _lastFilterQuery == filterCtrl.appliedSearchQuery &&
        _lastPackageFilterQuery == filterCtrl.appliedPackageFilterQuery &&
        _lastPidTidFilterQuery == filterCtrl.appliedPidTidFilterQuery &&
        _lastTagFilterQuery == filterCtrl.appliedTagFilterQuery &&
        _lastLogLevel == selectedLogLevel) {
      return _cachedFilteredLogs!;
    }

    _lastLogsLength = streamCtrl.logsBufferSize;
    _lastFilterQuery = filterCtrl.appliedSearchQuery;
    _lastPackageFilterQuery = filterCtrl.appliedPackageFilterQuery;
    _lastPidTidFilterQuery = filterCtrl.appliedPidTidFilterQuery;
    _lastTagFilterQuery = filterCtrl.appliedTagFilterQuery;
    _lastLogLevel = selectedLogLevel;
    _cachedFilteredLogs = streamCtrl.searchLogs(filterCtrl.matchesLogFilters);
    return _cachedFilteredLogs!;
  }

  List<int> get searchMatchIndices => inlineSearchCtrl.searchMatchIndices;

  int currentSearchMatchLogIndex(List<int> matches) =>
      inlineSearchCtrl.currentSearchMatchLogIndex(matches);

  // logcat delegation
  Future<void> startLogcat() async {
    if (selectedDevice == null) return;
    _exitGetStartedIfWorkspaceReady();
    rowSelectionCtrl.clearSelectedRows(notify: false);
    _importedFileName = null;
    await streamCtrl.start();
  }

  Future<void> stopLogcat() => streamCtrl.stop();
  void togglePauseResume() => streamCtrl.togglePauseResume();

  Future<void> setSelectedDevice(Device? device) async {
    if (device == null) {
      if (selectedDevice == null) return;
      rowSelectionCtrl.clearSelectedRows(notify: false);
      selectedDevice = null;
      if (isRunning) await streamCtrl.stopInternal(resetState: true);
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
      await streamCtrl.stopInternal(resetState: true);
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

  Future<void> _stopLogcatForDisconnectedDevice(Device device) async {
    if (!isRunning) return;
    await streamCtrl.stopInternal(resetState: false);
    if (_disposed) return;
    streamCtrl.logcatState = LogcatState.stopped;
    streamCtrl.appendSessionStateEntry(
      LogEntryType.stopped,
      message:
          'Device disconnected; stopped capturing logs for ${device.displayName}.',
      tag: 'device connection',
    );
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

  List<int> _selectionTargetIndicesForCopy(int? clickedFilteredIndex) {
    final filteredSnapshot = filteredLogs;
    final selectedIndices = rowSelectionCtrl.selectedRowIndices
        .where((index) =>
            index >= 0 &&
            index < filteredSnapshot.length &&
            filteredSnapshot[index].isUserSelectable)
        .toList()
      ..sort();

    if (clickedFilteredIndex == null) return selectedIndices;

    final clickedIsCopyable = clickedFilteredIndex >= 0 &&
        clickedFilteredIndex < filteredSnapshot.length &&
        filteredSnapshot[clickedFilteredIndex].isUserSelectable;

    if (!clickedIsCopyable) return selectedIndices;
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

  @override
  void dispose() {
    _disposed = true;
    _deviceRepository.removeListener(_handleDeviceRepositoryChanged);
    wirelessController.dispose();
    filterCtrl.dispose();
    streamCtrl.dispose();
    rowSelectionCtrl.dispose();
    inlineSearchCtrl.dispose();
    unawaited(_deviceSessionService.dispose());
    scrollController.dispose();
    logLinesController.dispose();
    super.dispose();
  }
}

