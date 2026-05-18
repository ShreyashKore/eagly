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
import '../../data/log_view_mode.dart';
import '../../services/device_repository.dart';
import '../../services/device_session_service.dart';
import '../../services/log_file_service.dart';
import '../../utils/log_buffer.dart';
import '../../utils/text_search_pattern.dart';
import '../wireless_connection/wireless_connection_controller.dart';
import 'components/inline_filter_bar.dart';

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
       _logsBuffer = LogBuffer<LogEntry>(
         baseCapacity: initialSettings.logLinesLimit,
       ),
       _deviceSessionService = deviceSessionService ?? DeviceSessionService() {
    _deviceSessionService.sessionLabel = id;
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
    inlineFilterController.text = _composeInlineFilterText();
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

  final ScrollController scrollController = ScrollController();
  final TextEditingController filterController = TextEditingController();
  final FocusNode filterFocusNode = FocusNode();
  final TextEditingController packageFilterController = TextEditingController();
  final FocusNode packageFilterFocusNode = FocusNode();
  final TextEditingController pidTidFilterController = TextEditingController();
  final FocusNode pidTidFilterFocusNode = FocusNode();
  final TextEditingController tagFilterController = TextEditingController();
  final FocusNode tagFilterFocusNode = FocusNode();
  final InlineFilterTextController inlineFilterController =
      InlineFilterTextController();
  final FocusNode inlineFilterFocusNode = FocusNode();
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  final TextEditingController logLinesController = TextEditingController();

  LogBuffer<LogEntry> _logsBuffer;
  final List<LogEntry> _pendingLogs = [];

  StreamSubscription<LogEntry>? _logSub;
  Timer? _flushTimer;
  Timer? _debounceTimer;
  Timer? _filterSaveDebounceTimer;
  Timer? _inlineSearchDebounce;

  var devices = <Device>[];
  Device? selectedDevice;

  var logcatState = LogcatState.stopped;
  var searchQuery = '';
  var packageFilterQuery = '';
  var pidTidFilterQuery = '';
  var tagFilterQuery = '';

  var _inlineFilterText = '';

  final List<String> _recentMessageFilters = [];
  final List<String> _recentPackageFilters = [];
  final List<String> _recentPidTidFilters = [];
  final List<String> _recentTagFilters = [];
  List<String> _knownInlinePackageFilters = const [];
  int _knownInlinePackageFingerprintLength = -1;
  int? _knownInlinePackageFingerprintFirstId;
  int? _knownInlinePackageFingerprintLastId;

  var _searchBarVisible = false;
  var _inlineSearch = const TextSearchConfig();
  var _appliedInlineSearch = const TextSearchConfig();
  var _searchCurrentMatchIndex = 0;
  String? _selectedSearchText;
  var _rowSelectionMode = false;
  final Set<int> _selectedRowIndices = <int>{};
  int? _rowSelectionAnchorIndex;

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
  String _lastAppliedFilterSignature = '';
  LogLevel _lastLogLevel = LogLevel.verbose;

  List<String> _appliedMessageTerms = const [];
  List<String> _appliedRawTerms = const [];
  List<String> _appliedPackageTerms = const [];
  List<String> _appliedPidTidTerms = const [];
  List<String> _appliedTagTerms = const [];

  List<int>? _cachedSearchMatchIndices;
  TextSearchConfig _smCacheSearch = const TextSearchConfig();
  Set<String> _smCacheHiddenCols = {};
  int _smCacheFilteredLen = -1;

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

  String get appLogSessionTag => id;

  bool get showGetStarted => _showGetStarted;
  bool get searchBarVisible => _searchBarVisible;
  bool get searchCaseSensitive => _inlineSearch.caseSensitive;
  bool get searchWholeWord => _inlineSearch.wholeWord;
  bool get searchRegex => _inlineSearch.regex;
  int get searchCurrentMatch => _searchCurrentMatchIndex;
  String? get selectedSearchText => _selectedSearchText;
  bool get rowSelectionMode => _rowSelectionMode;
  Set<int> get selectedRowIndices => Set.unmodifiable(_selectedRowIndices);
  bool get hasSelectedRows => _selectedRowIndices.isNotEmpty;
  int get selectedRowCount => _selectedRowIndices.length;
  int? get rowSelectionAnchorIndex => _rowSelectionAnchorIndex;
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
  String get appliedInlineSearchQuery => _appliedInlineSearch.query;
  String get inlineSearchQuery => _inlineSearch.query;
  TextSearchConfig get inlineSearch => _inlineSearch;
  TextSearchConfig get appliedInlineSearch => _appliedInlineSearch;
  TextSearchPattern get inlineSearchPattern =>
      TextSearchPattern.fromConfig(_appliedInlineSearch);
  bool get inlineSearchHasError => inlineSearchPattern.hasError;
  String? get inlineSearchErrorText => inlineSearchPattern.errorText;
  bool get isLoadingDevices => _deviceRepository.isLoading;
  bool get hasAttemptedDeviceLoad => _deviceRepository.hasAttemptedLoad;
  List<String> get recentMessageFilters =>
      List.unmodifiable(_recentMessageFilters);
  List<String> get recentPackageFilters =>
      List.unmodifiable(_recentPackageFilters);
  List<String> get recentPidTidFilters =>
      List.unmodifiable(_recentPidTidFilters);
  List<String> get recentTagFilters => List.unmodifiable(_recentTagFilters);
  List<String> get knownInlinePackageFilters {
    final storedLogs = logs;
    final firstId = storedLogs.firstOrNull?.id;
    final lastId = storedLogs.lastOrNull?.id;
    if (_knownInlinePackageFingerprintLength == storedLogs.length &&
        _knownInlinePackageFingerprintFirstId == firstId &&
        _knownInlinePackageFingerprintLastId == lastId) {
      return List.unmodifiable(_knownInlinePackageFilters);
    }

    final counts = <String, int>{};
    for (final log in storedLogs) {
      final value = _packageFilterValue(log).trim();
      if (value.isEmpty) continue;
      counts.update(value, (count) => count + 1, ifAbsent: () => 1);
    }

    final sortedValues = counts.keys.toList(growable: false)
      ..sort((left, right) {
        final countComparison = counts[right]!.compareTo(counts[left]!);
        if (countComparison != 0) return countComparison;
        return left.toLowerCase().compareTo(right.toLowerCase());
      });

    _knownInlinePackageFilters = sortedValues;
    _knownInlinePackageFingerprintLength = storedLogs.length;
    _knownInlinePackageFingerprintFirstId = firstId;
    _knownInlinePackageFingerprintLastId = lastId;
    return List.unmodifiable(_knownInlinePackageFilters);
  }

  bool get wrapText => _settings.wrapText;
  bool get autoScroll => _settings.autoScroll;
  LogLevel get selectedLogLevel => _settings.selectedLogLevel;
  LogFilterViewMode get filterViewMode => _settings.filterViewMode;
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

  bool _isSelectableFilteredIndex(
    int filteredIndex, [
    List<LogEntry>? snapshot,
  ]) {
    final filteredSnapshot = snapshot ?? filteredLogs;
    return filteredIndex >= 0 &&
        filteredIndex < filteredSnapshot.length &&
        filteredSnapshot[filteredIndex].isUserSelectable;
  }

  bool? beginRowSelectionGesture(
    int filteredIndex, {
    bool shiftPressed = false,
  }) {
    if (!_isSelectableFilteredIndex(filteredIndex)) return null;

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
    if (!_isSelectableFilteredIndex(filteredIndex)) return;

    final changed = selected
        ? _selectedRowIndices.add(filteredIndex)
        : _selectedRowIndices.remove(filteredIndex);
    if (changed) {
      _notify();
    }
  }

  void setSelectedRows(Set<int> indices) {
    final filteredSnapshot = filteredLogs;
    final next = indices
        .where((index) => _isSelectableFilteredIndex(index, filteredSnapshot))
        .toSet();
    if (const SetEquality<int>().equals(_selectedRowIndices, next)) {
      return;
    }

    _selectedRowIndices
      ..clear()
      ..addAll(next);
    _notify();
  }

  void selectRowRangeTo(int filteredIndex) {
    final filteredSnapshot = filteredLogs;
    if (!_isSelectableFilteredIndex(filteredIndex, filteredSnapshot)) return;

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
      if (!_isSelectableFilteredIndex(index, filteredSnapshot)) {
        continue;
      }
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
    _debounceTimer?.cancel();
    _filterSaveDebounceTimer?.cancel();
    clearSelectedRows(notify: false);
    final defaultLevel = LogLevel.defaultSelectionForPlatform(
      isIos: isIosLogContext,
    );
    filterController.clear();
    packageFilterController.clear();
    pidTidFilterController.clear();
    tagFilterController.clear();
    inlineFilterController.clear();
    _inlineFilterText = '';
    searchQuery = '';
    packageFilterQuery = '';
    pidTidFilterQuery = '';
    tagFilterQuery = '';
    _settings = _settings.copyWith(selectedLogLevel: defaultLevel);
    _appliedMessageTerms = const [];
    _appliedRawTerms = const [];
    _appliedPackageTerms = const [];
    _appliedPidTidTerms = const [];
    _appliedTagTerms = const [];
    _syncLogBufferFilter();
    _invalidateFilteredLogs();
    focusFilterInputs();
    _notify();
  }

  void onInlineFilterChanged(String value) {
    _inlineFilterText = value;
    if (inlineFilterController.text != value) {
      inlineFilterController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }

    _notify();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      _applyInlineFilters();
    });
  }

  void setInlineFilterText(
    String value, {
    TextSelection? selection,
    bool applyImmediately = false,
  }) {
    _inlineFilterText = value;
    inlineFilterController.value = TextEditingValue(
      text: value,
      selection: selection ?? TextSelection.collapsed(offset: value.length),
    );
    if (applyImmediately) {
      _debounceTimer?.cancel();
      _applyInlineFilters();
      return;
    }
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
    switch (filterViewMode) {
      case LogFilterViewMode.classic:
        _applyTextFilters();
      case LogFilterViewMode.inline:
        _applyInlineFilters();
    }
  }

  void setSelectedLogLevel(LogLevel level) {
    _updateSettings(_settings.copyWith(selectedLogLevel: level));
    clearSelectedRows(notify: false);
    _syncLogBufferFilter();
    _invalidateFilteredLogs();
    _syncInlineFilterText();
  }

  void setFilterViewMode(LogFilterViewMode mode) {
    if (mode == filterViewMode) return;
    _updateSettings(_settings.copyWith(filterViewMode: mode));
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
    final normalized = value?.trim();
    final nextValue = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    if (_selectedSearchText == nextValue) return;
    _selectedSearchText = nextValue;
    _notify();
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
    if (_searchBarVisible) {
      closeSearchBar();
    } else {
      openSearchBar();
    }
  }

  void openSearchBar({String? query}) {
    _inlineSearchDebounce?.cancel();
    disableAutoScroll();

    if (query != null) {
      updateInlineSearch(
        _inlineSearch.copyWith(query: query),
        applyImmediately: true,
      );
    }

    if (!_searchBarVisible) {
      _searchBarVisible = true;
      _notify();
    }

    _focusSearchField();
  }

  void closeSearchBar() {
    if (!_searchBarVisible) return;

    _inlineSearchDebounce?.cancel();
    _searchBarVisible = false;
    _inlineSearch = _inlineSearch.copyWith(query: '');
    _appliedInlineSearch = _appliedInlineSearch.copyWith(query: '');
    searchController.clear();
    _invalidateSearchMatches();
    _searchCurrentMatchIndex = 0;
    _notify();
  }

  void activateSearchFromSelection() {
    final selectedText = _selectedSearchText;
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
    updateInlineSearch(_inlineSearch.copyWith(query: value));
  }

  void setSearchCaseSensitive(bool value) {
    updateInlineSearch(
      _inlineSearch.copyWith(caseSensitive: value),
      applyImmediately: true,
    );
  }

  void setSearchWholeWord(bool value) {
    updateInlineSearch(
      _inlineSearch.copyWith(wholeWord: value),
      applyImmediately: true,
    );
  }

  void setSearchRegex(bool value) {
    updateInlineSearch(
      _inlineSearch.copyWith(regex: value),
      applyImmediately: true,
    );
  }

  void onSearchNext() {
    final matches = searchMatchIndices;
    if (matches.isEmpty) return;
    disableAutoScroll();
    _searchCurrentMatchIndex = (_searchCurrentMatchIndex + 1) % matches.length;
    _notify();
  }

  void onSearchPrev() {
    final matches = searchMatchIndices;
    if (matches.isEmpty) return;
    disableAutoScroll();
    _searchCurrentMatchIndex =
        (_searchCurrentMatchIndex - 1 + matches.length) % matches.length;
    _notify();
  }

  List<LogEntry> get filteredLogs {
    final appliedFilterSignature = _appliedFilterSignature;
    if (_cachedFilteredLogs != null &&
        _lastLogsLength == _logsBuffer.size &&
        _lastAppliedFilterSignature == appliedFilterSignature &&
        _lastLogLevel == selectedLogLevel) {
      return _cachedFilteredLogs!;
    }

    _lastLogsLength = _logsBuffer.size;
    _lastAppliedFilterSignature = appliedFilterSignature;
    _lastLogLevel = selectedLogLevel;

    _cachedFilteredLogs = _logsBuffer.search(_matchesLogFilters);

    return _cachedFilteredLogs!;
  }

  List<int> get searchMatchIndices {
    final filtered = filteredLogs;
    if (_cachedSearchMatchIndices != null &&
        _smCacheSearch == _appliedInlineSearch &&
        _smCacheHiddenCols.length == hiddenColumns.length &&
        _smCacheHiddenCols.containsAll(hiddenColumns) &&
        _smCacheFilteredLen == filtered.length) {
      return _cachedSearchMatchIndices!;
    }

    _smCacheSearch = _appliedInlineSearch;
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

  void updateInlineSearch(
    TextSearchConfig value, {
    bool applyImmediately = false,
  }) {
    final optionsChanged =
        value.caseSensitive != _inlineSearch.caseSensitive ||
        value.wholeWord != _inlineSearch.wholeWord ||
        value.regex != _inlineSearch.regex;
    final queryChanged = value.query != _inlineSearch.query;
    final appliedChanged = value != _appliedInlineSearch;
    if (!queryChanged &&
        !optionsChanged &&
        (!applyImmediately || !appliedChanged)) {
      return;
    }

    if (value.query.isNotEmpty || optionsChanged) {
      disableAutoScroll();
    }

    _inlineSearch = value;
    _searchCurrentMatchIndex = 0;

    if (searchController.text != value.query) {
      searchController.value = TextEditingValue(
        text: value.query,
        selection: TextSelection.collapsed(offset: value.query.length),
      );
    }

    _inlineSearchDebounce?.cancel();
    if (applyImmediately || optionsChanged) {
      _appliedInlineSearch = value;
      _invalidateSearchMatches();
      _notify();
      return;
    }

    _notify();
    _inlineSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      _appliedInlineSearch = value;
      _invalidateSearchMatches();
      _notify();
    });
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

    _syncInlineFilterText();

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
    _applyParsedFilters(_parsedFiltersFromClassicInputs());
  }

  void _applyInlineFilters() {
    final parsedFilters = _parseInlineFilters(
      _inlineFilterText,
      fallbackLevel: LogLevel.defaultSelectionForPlatform(
        isIos: isIosLogContext,
      ),
    );
    _applyInlineDraftFilters(parsedFilters);
    _applyParsedFilters(parsedFilters);
  }

  void _applyParsedFilters(_ParsedLogFilters parsedFilters) {
    _appliedMessageTerms = parsedFilters.messageTerms;
    _appliedRawTerms = parsedFilters.rawTerms;
    _appliedPackageTerms = parsedFilters.packageTerms;
    _appliedPidTidTerms = parsedFilters.pidTidTerms;
    _appliedTagTerms = parsedFilters.tagTerms;
    if (selectedLogLevel != parsedFilters.level) {
      _settings = _settings.copyWith(selectedLogLevel: parsedFilters.level);
    }
    clearSelectedRows(notify: false);

    _filterSaveDebounceTimer?.cancel();
    _filterSaveDebounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _rememberRecentFilterValues();
    });
    _syncLogBufferFilter();
    _invalidateFilteredLogs();
    _notify();
  }

  void _rememberRecentFilterValues() {
    for (final value in _appliedMessageTerms) {
      _rememberRecentFilterValue(_recentMessageFilters, value);
    }
    for (final value in _appliedPackageTerms) {
      _rememberRecentFilterValue(_recentPackageFilters, value);
    }
    for (final value in _appliedPidTidTerms) {
      _rememberRecentFilterValue(_recentPidTidFilters, value);
    }
    for (final value in _appliedTagTerms) {
      _rememberRecentFilterValue(_recentTagFilters, value);
    }
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

  _ParsedLogFilters _parsedFiltersFromClassicInputs() {
    return _ParsedLogFilters(
      messageText: searchQuery.trim(),
      packageText: packageFilterQuery.trim(),
      pidTidText: pidTidFilterQuery.trim(),
      tagText: tagFilterQuery.trim(),
      messageTerms: _singleTerm(searchQuery),
      rawTerms: const [],
      packageTerms: _singleTerm(packageFilterQuery),
      pidTidTerms: _singleTerm(pidTidFilterQuery),
      tagTerms: _singleTerm(tagFilterQuery),
      level: selectedLogLevel,
    );
  }

  void _applyInlineDraftFilters(_ParsedLogFilters parsedFilters) {
    searchQuery = parsedFilters.messageText;
    packageFilterQuery = parsedFilters.packageText;
    pidTidFilterQuery = parsedFilters.pidTidText;
    tagFilterQuery = parsedFilters.tagText;

    _setControllerTextIfNeeded(filterController, parsedFilters.messageText);
    _setControllerTextIfNeeded(
      packageFilterController,
      parsedFilters.packageText,
    );
    _setControllerTextIfNeeded(
      pidTidFilterController,
      parsedFilters.pidTidText,
    );
    _setControllerTextIfNeeded(tagFilterController, parsedFilters.tagText);
  }

  void _setControllerTextIfNeeded(
    TextEditingController controller,
    String value,
  ) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  List<String> _singleTerm(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? const [] : [normalized];
  }

  void _syncInlineFilterText() {
    final nextValue = _composeInlineFilterText();
    _inlineFilterText = nextValue;
    if (inlineFilterController.text == nextValue) return;
    inlineFilterController.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
    );
  }

  String _composeInlineFilterText() {
    final tokens = <String>[];
    final defaultLevel = LogLevel.defaultSelectionForPlatform(
      isIos: isIosLogContext,
    );
    if (selectedLogLevel != defaultLevel) {
      tokens.add(_serializeInlineToken('level', selectedLogLevel.code));
    }
    if (packageFilterQuery.trim().isNotEmpty) {
      tokens.add(_serializeInlineToken('package', packageFilterQuery.trim()));
    }
    if (pidTidFilterQuery.trim().isNotEmpty) {
      tokens.add(_serializeInlineToken('pid', pidTidFilterQuery.trim()));
    }
    if (tagFilterQuery.trim().isNotEmpty) {
      tokens.add(_serializeInlineToken('tag', tagFilterQuery.trim()));
    }
    if (searchQuery.trim().isNotEmpty) {
      tokens.add(_serializeInlineToken('message', searchQuery.trim()));
    }
    return tokens.join(' ');
  }

  String _serializeInlineToken(String key, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '';

    final needsQuotes =
        normalized.contains(RegExp(r'\s')) || normalized.contains('"');
    if (!needsQuotes) {
      return '$key:$normalized';
    }

    final escaped = normalized.replaceAll('"', r'\"');
    return '$key:"$escaped"';
  }

  _ParsedLogFilters _parseInlineFilters(
    String rawText, {
    required LogLevel fallbackLevel,
  }) {
    final messageTerms = <String>[];
    final rawTerms = <String>[];
    final packageTerms = <String>[];
    final pidTidTerms = <String>[];
    final tagTerms = <String>[];
    var parsedLevel = fallbackLevel;

    for (final token in _tokenizeInlineFilterText(rawText)) {
      final trimmedToken = token.trim();
      if (trimmedToken.isEmpty) continue;

      final colonIndex = trimmedToken.indexOf(':');
      if (colonIndex <= 0) {
        final messageValue = _normalizeInlineFilterValue(trimmedToken);
        if (messageValue.isNotEmpty) {
          rawTerms.add(messageValue);
        }
        continue;
      }

      final rawKey = trimmedToken.substring(0, colonIndex);
      final rawValue = trimmedToken.substring(colonIndex + 1);
      final key = _canonicalInlineFilterKey(rawKey);
      final value = _normalizeInlineFilterValue(rawValue);
      if (key == null || value.isEmpty) {
        final fallbackValue = _normalizeInlineFilterValue(trimmedToken);
        if (fallbackValue.isNotEmpty) {
          rawTerms.add(fallbackValue);
        }
        continue;
      }

      switch (key) {
        case _InlineFilterKey.message:
          messageTerms.add(value);
        case _InlineFilterKey.packageName:
          packageTerms.add(value);
        case _InlineFilterKey.pidTid:
          pidTidTerms.add(value.toLowerCase());
        case _InlineFilterKey.tag:
          tagTerms.add(value);
        case _InlineFilterKey.level:
          parsedLevel = LogLevel.fromStored(
            value,
          ).normalizeSelectionForPlatform(isIos: isIosLogContext);
      }
    }

    final messageFieldTerms = <String>[...rawTerms, ...messageTerms];
    return _ParsedLogFilters(
      messageText: messageFieldTerms.join(' '),
      packageText: packageTerms.join(' '),
      pidTidText: pidTidTerms.join(' '),
      tagText: tagTerms.join(' '),
      messageTerms: List.unmodifiable(messageTerms),
      rawTerms: List.unmodifiable(rawTerms),
      packageTerms: List.unmodifiable(packageTerms),
      pidTidTerms: List.unmodifiable(pidTidTerms),
      tagTerms: List.unmodifiable(tagTerms),
      level: parsedLevel,
    );
  }

  List<String> _tokenizeInlineFilterText(String rawText) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (final rune in rawText.runes) {
      final char = String.fromCharCode(rune);
      if (char == '"') {
        inQuotes = !inQuotes;
        buffer.write(char);
        continue;
      }
      if (!inQuotes && RegExp(r'\s').hasMatch(char)) {
        final token = buffer.toString().trim();
        if (token.isNotEmpty) {
          tokens.add(token);
        }
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }

    final finalToken = buffer.toString().trim();
    if (finalToken.isNotEmpty) {
      tokens.add(finalToken);
    }
    return tokens;
  }

  _InlineFilterKey? _canonicalInlineFilterKey(String rawKey) {
    return switch (rawKey.trim().toLowerCase()) {
      'message' || 'msg' || 'text' => _InlineFilterKey.message,
      'package' || 'pkg' || 'app' || 'process' => _InlineFilterKey.packageName,
      'pid' || 'tid' || 'thread' || 'pidtid' => _InlineFilterKey.pidTid,
      'tag' => _InlineFilterKey.tag,
      'level' || 'lvl' || 'priority' => _InlineFilterKey.level,
      _ => null,
    };
  }

  String _normalizeInlineFilterValue(String rawValue) {
    var normalized = rawValue.trim();
    if (normalized.length >= 2 &&
        normalized.startsWith('"') &&
        normalized.endsWith('"')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    return normalized.replaceAll(r'\"', '"').trim();
  }

  bool _matchesAllTerms(
    String candidate,
    List<String> terms, {
    required bool caseSensitive,
  }) {
    if (terms.isEmpty) return true;
    final normalizedCandidate = caseSensitive
        ? candidate
        : candidate.toLowerCase();
    return terms.every((term) {
      final normalizedTerm = caseSensitive ? term : term.toLowerCase();
      return normalizedCandidate.contains(normalizedTerm);
    });
  }

  String get _appliedFilterSignature => [
    selectedLogLevel.code,
    'm:${_appliedMessageTerms.join('\u0001')}',
    'r:${_appliedRawTerms.join('\u0001')}',
    'p:${_appliedPackageTerms.join('\u0001')}',
    'pt:${_appliedPidTidTerms.join('\u0001')}',
    't:${_appliedTagTerms.join('\u0001')}',
  ].join('\u0000');

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

  bool _matchesLogFilters(LogEntry log) {
    final selectedLevel = effectiveSelectedLogLevel;
    if (LogLevel.fromStored(log.level).hierarchy > selectedLevel.hierarchy) {
      return false;
    }

    if (!_matchesAllTerms(
      _packageFilterValue(log),
      _appliedPackageTerms,
      caseSensitive: false,
    )) {
      return false;
    }

    if (!_matchesAllTerms(
      log.lowercaseSearchable,
      _appliedRawTerms,
      caseSensitive: false,
    )) {
      return false;
    }

    if (_appliedPidTidTerms.any((query) => !_matchesPidTidFilter(log, query))) {
      return false;
    }

    if (!_matchesAllTerms(log.tag, _appliedTagTerms, caseSensitive: false)) {
      return false;
    }

    if (!_matchesAllTerms(
      log.message,
      _appliedMessageTerms,
      caseSensitive: false,
    )) {
      return false;
    }

    return true;
  }

  bool get _hasActiveRetentionFilter {
    final defaultLevel = LogLevel.defaultSelectionForPlatform(
      isIos: isIosLogContext,
    );
    return effectiveSelectedLogLevel.hierarchy < defaultLevel.hierarchy ||
        _appliedMessageTerms.isNotEmpty ||
        _appliedRawTerms.isNotEmpty ||
        _appliedPackageTerms.isNotEmpty ||
        _appliedPidTidTerms.isNotEmpty ||
        _appliedTagTerms.isNotEmpty;
  }

  LogFilter<LogEntry>? get _retentionFilter =>
      _hasActiveRetentionFilter ? _matchesLogFilters : null;

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
      tag: tag ?? 'eagly session',
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

  List<int> _computeSearchMatches(List<LogEntry> items) {
    final pattern = inlineSearchPattern;
    if (!pattern.isActive || !pattern.isValid) return [];

    final visibleColumns = LogColumn.values
        .where((column) => !hiddenColumns.contains(column.name))
        .toList();

    final result = <int>[];
    for (var index = 0; index < items.length; index++) {
      final log = items[index];
      if (log.isSpecialEntry) {
        if (pattern.matches(log.specialSearchableText)) {
          result.add(index);
        }
        continue;
      }
      for (final column in visibleColumns) {
        if (pattern.matches(log.valueForColumn(column))) {
          result.add(index);
          break;
        }
      }
    }
    return result;
  }

  List<LogEntry> get _currentLogsSnapshot =>
      List<LogEntry>.unmodifiable([..._logsBuffer.getLogs(), ..._pendingLogs]);

  List<int> _selectionTargetIndicesForCopy(int? clickedFilteredIndex) {
    final filteredSnapshot = filteredLogs;
    final selectedIndices =
        _selectedRowIndices
            .where(
              (index) => _isSelectableFilteredIndex(index, filteredSnapshot),
            )
            .toList()
          ..sort();

    if (clickedFilteredIndex == null) {
      return selectedIndices;
    }

    final clickedIsCopyable = _isSelectableFilteredIndex(
      clickedFilteredIndex,
      filteredSnapshot,
    );
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
    inlineFilterController.dispose();
    inlineFilterFocusNode.dispose();
    searchController.dispose();
    searchFocusNode.dispose();
    logLinesController.dispose();
    super.dispose();
  }
}

enum _LogFilterField { message, packageName, pidTid, tag }

enum _InlineFilterKey { message, packageName, pidTid, tag, level }

class _ParsedLogFilters {
  const _ParsedLogFilters({
    required this.messageText,
    required this.packageText,
    required this.pidTidText,
    required this.tagText,
    required this.messageTerms,
    required this.rawTerms,
    required this.packageTerms,
    required this.pidTidTerms,
    required this.tagTerms,
    required this.level,
  });

  final String messageText;
  final String packageText;
  final String pidTidText;
  final String tagText;
  final List<String> messageTerms;
  final List<String> rawTerms;
  final List<String> packageTerms;
  final List<String> pidTidTerms;
  final List<String> tagTerms;
  final LogLevel level;
}
