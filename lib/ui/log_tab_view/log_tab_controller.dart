import 'dart:async';
import 'dart:math' as math;

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
import '../wireless_connection/wireless_connection_controller.dart';

enum LogcatState { stopped, running, paused }

enum LogCopyFormat { messageOnly, timestampAndMessage, fullLine }

class LogTabController extends ChangeNotifier {
  static const int _maxRecentFilterValues = 8;

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
       _deviceSessionService = deviceSessionService ?? DeviceSessionService() {
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
    filterController.text = searchQuery;
    packageFilterController.text = packageFilterQuery;
    pidTidFilterController.text = pidTidFilterQuery;
    tagFilterController.text = tagFilterQuery;
    logLinesController.text = logLinesLimit.toString();
    devices = _deviceRepository.devices.toList(growable: false);
    _deviceRepository.addListener(_handleDeviceRepositoryChanged);
    unawaited(_deviceRepository.ensureStarted());
  }

  final String id;
  final VoidCallback? onExitGetStarted;
  final bool Function(String deviceId)? isDeviceSelectedInAnotherTab;
  final DeviceRepository _deviceRepository;
  final DeviceSessionService _deviceSessionService;
  late final WirelessConnectionController wirelessController;

  final ScrollController scrollController = ScrollController();
  final TextEditingController filterController = TextEditingController();
  final FocusNode filterFocusNode = FocusNode();
  final TextEditingController packageFilterController = TextEditingController();
  final FocusNode packageFilterFocusNode = FocusNode();
  final TextEditingController pidTidFilterController = TextEditingController();
  final FocusNode pidTidFilterFocusNode = FocusNode();
  final TextEditingController tagFilterController = TextEditingController();
  final FocusNode tagFilterFocusNode = FocusNode();
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  final TextEditingController logLinesController = TextEditingController();

  final List<LogEntry> _buffer = [];

  StreamSubscription<LogEntry>? _logSub;
  Timer? _flushTimer;
  Timer? _debounceTimer;
  Timer? _filterSaveDebounceTimer;
  Timer? _inlineSearchDebounce;

  var devices = <Device>[];
  Device? selectedDevice;
  var logs = <LogEntry>[];

  var logcatState = LogcatState.stopped;
  var searchQuery = '';
  var _appliedSearchQuery = '';
  var packageFilterQuery = '';
  var _appliedPackageFilterQuery = '';
  var pidTidFilterQuery = '';
  var _appliedPidTidFilterQuery = '';
  var tagFilterQuery = '';
  var _appliedTagFilterQuery = '';

  final List<String> _recentMessageFilters = [];
  final List<String> _recentPackageFilters = [];
  final List<String> _recentPidTidFilters = [];
  final List<String> _recentTagFilters = [];

  var _searchBarVisible = false;
  var _inlineSearchQuery = '';
  var _appliedInlineSearchQuery = '';
  var _searchCaseSensitive = false;
  var _searchCurrentMatchIndex = 0;
  var _rowSelectionMode = false;
  final Set<int> _selectedRowIndices = <int>{};
  int? _rowSelectionAnchorIndex;

  var _editingLogLinesLimit = false;
  var _logsMemoryBytes = 0;
  var _bufferMemoryBytes = 0;
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

  List<int>? _cachedSearchMatchIndices;
  String _smCacheQuery = '';
  bool _smCacheCaseSensitive = false;
  Set<String> _smCacheHiddenCols = {};
  int _smCacheFilteredLen = -1;

  String get title {
    if (selectedDevice != null) return selectedDevice!.displayLabel.primary;
    if (_importedFileName != null) return _importedFileName!;
    if (_showGetStarted) return 'Get Started';
    return _title;
  }

  bool get showGetStarted => _showGetStarted;
  bool get searchBarVisible => _searchBarVisible;
  bool get searchCaseSensitive => _searchCaseSensitive;
  int get searchCurrentMatch => _searchCurrentMatchIndex;
  bool get rowSelectionMode => _rowSelectionMode;
  Set<int> get selectedRowIndices => Set.unmodifiable(_selectedRowIndices);
  bool get hasSelectedRows => _selectedRowIndices.isNotEmpty;
  int get selectedRowCount => _selectedRowIndices.length;
  int? get rowSelectionAnchorIndex => _rowSelectionAnchorIndex;
  bool get editingLogLinesLimit => _editingLogLinesLimit;
  int get logViewerRevision => _logViewerRevision;
  bool get isRunning => logcatState != LogcatState.stopped;
  bool get isPaused => logcatState == LogcatState.paused;
  bool get hasLogs => logs.isNotEmpty;
  bool get hasAnyCachedLogs => logs.isNotEmpty || _buffer.isNotEmpty;
  bool get hasSelectedDevice => selectedDevice != null;
  bool get hasConnectedSelectedDevice => selectedDevice?.isConnected == true;
  bool get hasVisibleWorkspace => hasSelectedDevice || hasLogs;
  int get totalLogsMemoryBytes => _logsMemoryBytes + _bufferMemoryBytes;
  String get appliedInlineSearchQuery => _appliedInlineSearchQuery;
  String get inlineSearchQuery => _inlineSearchQuery;
  bool get isLoadingDevices => _deviceRepository.isLoading;
  bool get hasAttemptedDeviceLoad => _deviceRepository.hasAttemptedLoad;
  List<String> get recentMessageFilters =>
      List.unmodifiable(_recentMessageFilters);
  List<String> get recentPackageFilters =>
      List.unmodifiable(_recentPackageFilters);
  List<String> get recentPidTidFilters =>
      List.unmodifiable(_recentPidTidFilters);
  List<String> get recentTagFilters => List.unmodifiable(_recentTagFilters);

  bool get wrapText => _settings.wrapText;
  bool get autoScroll => _settings.autoScroll;
  LogLevel get selectedLogLevel => _settings.selectedLogLevel;
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
      filterFocusNode.requestFocus();
      filterController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: filterController.text.length,
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
    clearSelectedRows(notify: false);
    logs = [];
    _buffer.clear();
    _logsMemoryBytes = 0;
    _bufferMemoryBytes = 0;
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

    clearSelectedRows(notify: false);
    selectedDevice = null;
    _importedFileName = result.fileName;
    logs = result.logs!;
    _buffer.clear();
    _logsMemoryBytes = _estimateLogsBytes(logs);
    _bufferMemoryBytes = 0;
    logcatState = LogcatState.stopped;
    _exitGetStarted();
    _invalidateFilteredLogs();
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
    setRowSelectionMode(!rowSelectionMode);
  }

  void setRowSelectionMode(bool value) {
    if (_rowSelectionMode == value) return;

    _rowSelectionMode = value;
    if (!value) {
      clearSelectedRows(notify: false);
    }
    _notify();
  }

  bool isRowSelected(int filteredIndex) {
    return _selectedRowIndices.contains(filteredIndex);
  }

  bool? beginRowSelectionGesture(
    int filteredIndex, {
    bool shiftPressed = false,
  }) {
    if (filteredIndex < 0) return null;

    if (shiftPressed) {
      selectRowRangeTo(filteredIndex);
      return null;
    }

    final shouldSelect = !_selectedRowIndices.contains(filteredIndex);
    final anchorChanged = _rowSelectionAnchorIndex != filteredIndex;
    _rowSelectionAnchorIndex = filteredIndex;
    final changed = shouldSelect
        ? _selectedRowIndices.add(filteredIndex)
        : _selectedRowIndices.remove(filteredIndex);
    if (changed || anchorChanged) {
      _notify();
    }
    return shouldSelect;
  }

  void setRowSelected(int filteredIndex, bool selected) {
    if (filteredIndex < 0) return;

    final changed = selected
        ? _selectedRowIndices.add(filteredIndex)
        : _selectedRowIndices.remove(filteredIndex);
    if (changed) {
      _notify();
    }
  }

  void setSelectedRows(Set<int> indices) {
    final next = indices.where((index) => index >= 0).toSet();
    if (const SetEquality<int>().equals(_selectedRowIndices, next)) {
      return;
    }

    _selectedRowIndices
      ..clear()
      ..addAll(next);
    _notify();
  }

  void selectRowRangeTo(int filteredIndex) {
    if (filteredIndex < 0) return;

    if (_rowSelectionAnchorIndex == null) {
      final anchorChanged = _rowSelectionAnchorIndex != filteredIndex;
      _rowSelectionAnchorIndex = filteredIndex;
      final changed = _selectedRowIndices.add(filteredIndex);
      if (changed || anchorChanged) {
        _notify();
      }
      return;
    }

    final start = math.min(_rowSelectionAnchorIndex!, filteredIndex);
    final end = math.max(_rowSelectionAnchorIndex!, filteredIndex);
    var changed = false;
    for (var index = start; index <= end; index++) {
      changed = _selectedRowIndices.add(index) || changed;
    }
    if (changed) {
      _notify();
    }
  }

  void clearSelectedRows({bool notify = true}) {
    final changed =
        _selectedRowIndices.isNotEmpty || _rowSelectionAnchorIndex != null;
    if (!changed) return;
    _selectedRowIndices.clear();
    _rowSelectionAnchorIndex = null;
    if (notify) {
      _notify();
    }
  }

  Future<int> copyAllLogs() {
    return _copyLogsToClipboard(
      _currentLogsSnapshot,
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

    final entries = [for (final index in indices) filteredSnapshot[index]];
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
    _debounceTimer?.cancel();
    _filterSaveDebounceTimer?.cancel();
    clearSelectedRows(notify: false);
    filterController.clear();
    packageFilterController.clear();
    pidTidFilterController.clear();
    tagFilterController.clear();
    searchQuery = '';
    _appliedSearchQuery = '';
    packageFilterQuery = '';
    _appliedPackageFilterQuery = '';
    pidTidFilterQuery = '';
    _appliedPidTidFilterQuery = '';
    tagFilterQuery = '';
    _appliedTagFilterQuery = '';
    _invalidateFilteredLogs();
    focusFilterInputs();
    _notify();
  }

  void onSearchChanged(String value) {
    _setFilterField(_LogFilterField.message, value);
  }

  void onPackageFilterChanged(String value) {
    _setFilterField(_LogFilterField.packageName, value);
  }

  void onPidTidFilterChanged(String value) {
    _setFilterField(_LogFilterField.pidTid, value);
  }

  void onTagFilterChanged(String value) {
    _setFilterField(_LogFilterField.tag, value);
  }

  void selectMessageFilterSuggestion(String value) {
    _setFilterField(_LogFilterField.message, value, applyImmediately: true);
  }

  void selectPackageFilterSuggestion(String value) {
    _setFilterField(_LogFilterField.packageName, value, applyImmediately: true);
  }

  void selectPidTidFilterSuggestion(String value) {
    _setFilterField(_LogFilterField.pidTid, value, applyImmediately: true);
  }

  void selectTagFilterSuggestion(String value) {
    _setFilterField(_LogFilterField.tag, value, applyImmediately: true);
  }

  void applyFiltersNow() {
    _debounceTimer?.cancel();
    _applyTextFilters();
  }

  void setSelectedLogLevel(LogLevel level) {
    _updateSettings(_settings.copyWith(selectedLogLevel: level));
    clearSelectedRows(notify: false);
    _invalidateFilteredLogs();
  }

  void toggleWrapText() {
    _logViewerRevision++;
    _updateSettings(_settings.copyWith(wrapText: !wrapText));
  }

  void toggleAutoScroll() {
    _updateSettings(_settings.copyWith(autoScroll: !autoScroll));
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
      clearSelectedRows(notify: false);
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
    final selectedLevel = effectiveSelectedLogLevel;

    if (_cachedFilteredLogs != null &&
        _lastLogsLength == logs.length &&
        _lastFilterQuery == _appliedSearchQuery &&
        _lastPackageFilterQuery == _appliedPackageFilterQuery &&
        _lastPidTidFilterQuery == _appliedPidTidFilterQuery &&
        _lastTagFilterQuery == _appliedTagFilterQuery &&
        _lastLogLevel == selectedLogLevel) {
      return _cachedFilteredLogs!;
    }

    _lastLogsLength = logs.length;
    _lastFilterQuery = _appliedSearchQuery;
    _lastPackageFilterQuery = _appliedPackageFilterQuery;
    _lastPidTidFilterQuery = _appliedPidTidFilterQuery;
    _lastTagFilterQuery = _appliedTagFilterQuery;
    _lastLogLevel = selectedLogLevel;

    final messageQuery = _appliedSearchQuery.toLowerCase();
    final packageQuery = _appliedPackageFilterQuery.toLowerCase();
    final pidTidQuery = _appliedPidTidFilterQuery.toLowerCase();
    final tagQuery = _appliedTagFilterQuery.toLowerCase();
    _cachedFilteredLogs = logs.where((log) {
      if (LogLevel.fromStored(log.level).hierarchy > selectedLevel.hierarchy) {
        return false;
      }
      if (packageQuery.isNotEmpty &&
          !_packageFilterValue(log).toLowerCase().contains(packageQuery)) {
        return false;
      }
      if (pidTidQuery.isNotEmpty && !_matchesPidTidFilter(log, pidTidQuery)) {
        return false;
      }
      if (tagQuery.isNotEmpty && !log.tag.toLowerCase().contains(tagQuery)) {
        return false;
      }
      if (messageQuery.isNotEmpty &&
          !log.message.toLowerCase().contains(messageQuery)) {
        return false;
      }
      return true;
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

  void _setFilterField(
    _LogFilterField field,
    String value, {
    bool applyImmediately = false,
  }) {
    final selection = TextSelection.collapsed(offset: value.length);

    switch (field) {
      case _LogFilterField.message:
        searchQuery = value;
        if (filterController.text != value) {
          filterController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
      case _LogFilterField.packageName:
        packageFilterQuery = value;
        if (packageFilterController.text != value) {
          packageFilterController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
      case _LogFilterField.pidTid:
        pidTidFilterQuery = value;
        if (pidTidFilterController.text != value) {
          pidTidFilterController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
      case _LogFilterField.tag:
        tagFilterQuery = value;
        if (tagFilterController.text != value) {
          tagFilterController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
    }

    if (applyImmediately) {
      _applyTextFilters();
      return;
    }

    _notify();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      _applyTextFilters();
    });
  }

  void _applyTextFilters() {
    _appliedSearchQuery = searchQuery.trim();
    _appliedPackageFilterQuery = packageFilterQuery.trim();
    _appliedPidTidFilterQuery = pidTidFilterQuery.trim();
    _appliedTagFilterQuery = tagFilterQuery.trim();
    clearSelectedRows(notify: false);

    _filterSaveDebounceTimer?.cancel();
    _filterSaveDebounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _rememberRecentFilterValues();
    });
    _invalidateFilteredLogs();
    _notify();
  }

  void _rememberRecentFilterValues() {
    _rememberRecentFilterValue(_recentMessageFilters, _appliedSearchQuery);
    _rememberRecentFilterValue(
      _recentPackageFilters,
      _appliedPackageFilterQuery,
    );
    _rememberRecentFilterValue(_recentPidTidFilters, _appliedPidTidFilterQuery);
    _rememberRecentFilterValue(_recentTagFilters, _appliedTagFilterQuery);
  }

  void _rememberRecentFilterValue(List<String> recentValues, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return;

    recentValues.removeWhere(
      (existing) => existing.toLowerCase() == normalized.toLowerCase(),
    );
    recentValues.insert(0, normalized);

    if (recentValues.length > _maxRecentFilterValues) {
      recentValues.removeRange(_maxRecentFilterValues, recentValues.length);
    }
  }

  String _packageFilterValue(LogEntry log) {
    final packageName = log.packageName?.trim();
    if (packageName != null && packageName.isNotEmpty) return packageName;

    final processName = log.processName?.trim();
    if (processName != null && processName.isNotEmpty) return processName;

    return '';
  }

  bool _matchesPidTidFilter(LogEntry log, String query) {
    final pid = log.pid.toLowerCase();
    final tid = log.tid.toLowerCase();
    return pid.contains(query) ||
        tid.contains(query) ||
        '$pid/$tid'.contains(query) ||
        '$pid:$tid'.contains(query);
  }

  Future<void> _applyFetchedDevices(
    List<Device> fetchedDevices, {
    bool autoStartSingleIfAvailable = false,
  }) async {
    final currentSelectionId = selectedDevice?.id;
    devices = fetchedDevices;

    if (currentSelectionId != null) {
      selectedDevice = fetchedDevices.firstWhereOrNull(
        (device) => device.id == currentSelectionId,
      );
    }

    if (currentSelectionId != null && selectedDevice == null) {
      selectedDevice = null;
      await _stopLogcatInternal(resetState: true);
    }

    final shouldAutoStartSingleDevice =
        autoStartSingleIfAvailable &&
        logs.isEmpty &&
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
    logs = [];
    _buffer.clear();
    _logsMemoryBytes = 0;
    _bufferMemoryBytes = 0;
    _invalidateFilteredLogs();
    logcatState = LogcatState.running;
    _notify();

    _logSub = _deviceSessionService.startLogStream(selectedDevice!).listen((
      logEntry,
    ) {
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
        clearSelectedRows(notify: false);
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
    await _deviceSessionService.stopActiveLogStream();

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

  List<LogEntry> get _currentLogsSnapshot =>
      List<LogEntry>.unmodifiable([...logs, ..._buffer]);

  List<int> _selectionTargetIndicesForCopy(int? clickedFilteredIndex) {
    if (clickedFilteredIndex == null || _selectedRowIndices.isNotEmpty &&
        _selectedRowIndices.contains(clickedFilteredIndex)) {
      return _selectedRowIndices.toList()..sort();
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
    _debounceTimer?.cancel();
    _inlineSearchDebounce?.cancel();
    wirelessController.dispose();
    unawaited(_logSub?.cancel());
    unawaited(_deviceSessionService.dispose());
    scrollController.dispose();
    filterController.dispose();
    filterFocusNode.dispose();
    packageFilterController.dispose();
    packageFilterFocusNode.dispose();
    pidTidFilterController.dispose();
    pidTidFilterFocusNode.dispose();
    tagFilterController.dispose();
    tagFilterFocusNode.dispose();
    searchController.dispose();
    searchFocusNode.dispose();
    logLinesController.dispose();
    super.dispose();
  }
}

enum _LogFilterField { message, packageName, pidTid, tag }
