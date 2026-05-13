import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/device.dart';
import 'data/models/log_column.dart';
import 'data/models/log_entry.dart';
import 'data/models/log_filters.dart';
import 'data/models/log_level.dart';
import 'data/models/log_tab_settings.dart';
import 'presentation/models/log_view_mode.dart';
import 'services/log_file_service.dart';
import '../../session/device_session_controller.dart';
import '../../session/feature_controller.dart';
import '../../utils/log_buffer.dart';
import '../../utils/log_entry_utils.dart';
import '../../utils/text_search_pattern.dart';
import 'presentation/components/inline_filter_bar.dart';

enum LogcatState { stopped, running, paused }

/// Per-device logging feature: captures logcat / syslog, buffers + filters +
/// searches log entries, and manages row selection / copy / export. Holds no
/// device-selection or mirror state.
class LogController extends FeatureController {
  static const int _maxRecentFilterValues = 8;

  /// Number of automatic recovery cycles attempted before the warning banner
  /// is surfaced for manual intervention.
  static const int _maxAutoRecoveryAttempts = 2;

  /// How long the live stream may go without emitting anything before the
  /// watchdog actively probes the device for liveness (Android only).
  @visibleForTesting
  static Duration streamStallThreshold = const Duration(seconds: 30);

  /// Watchdog poll interval while a tab is actively capturing.
  @visibleForTesting
  static Duration watchdogInterval = const Duration(seconds: 10);

  /// Delay before an automatic recovery attempt re-probes / re-attaches.
  @visibleForTesting
  static Duration recoveryBackoff = const Duration(seconds: 2);

  LogController(super.session, {required LogTabSettings initialSettings})
    : _settings = initialSettings,
      _logsBuffer = LogBuffer<LogEntry>(
        baseCapacity: initialSettings.logLinesLimit,
      ) {
    filterController.text = searchQuery;
    packageFilterController.text = packageFilterQuery;
    pidTidFilterController.text = pidTidFilterQuery;
    tagFilterController.text = tagFilterQuery;
    inlineFilterController.text = _composeInlineFilterText();
    logLinesController.text = logLinesLimit.toString();
    _syncLogBufferFilter();
  }

  /// Creates a controller pre-loaded with [entries] from a log file.
  /// Live capture, clear, and start/stop are disabled.
  factory LogController.imported(
    DeviceSessionController session, {
    required LogTabSettings initialSettings,
  }) {
    final ctrl = LogController(session, initialSettings: initialSettings);
    ctrl._isImported = true;
    return ctrl;
  }

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
  Timer? _watchdogTimer;
  Timer? _recoveryTimer;

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
  var _activated = false;
  var _isImported = false;

  /// Wall-clock time of the last entry received from the live stream. Drives
  /// the stall watchdog.
  DateTime? _lastStreamActivityAt;

  /// True when the live stream was lost and could not be resumed automatically;
  /// drives the warning banner.
  var _liveStreamInterrupted = false;

  /// True while an automatic recovery cycle is in flight.
  var _recovering = false;
  var _recoveryAttempts = 0;
  var _probeInFlight = false;
  String? _interruptionMessage;
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

  String get appLogSessionTag => device.id;
  bool get isImported => _isImported;
  String? get importedFileName => _importedFileName;

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
  bool get isRunning => logcatState != LogcatState.stopped;
  bool get isPaused => logcatState == LogcatState.paused;

  /// True when live capture was active but the stream dropped and could not be
  /// recovered automatically. The UI surfaces a warning banner while true.
  bool get liveLoggingInterrupted => _liveStreamInterrupted;

  /// True while the controller is automatically trying to re-establish a lost
  /// live stream.
  bool get isRecovering => _recovering;

  /// Human-readable explanation shown in the interruption banner.
  String? get liveLoggingInterruptionMessage => _interruptionMessage;

  bool get hasLogs => _logsBuffer.size > 0;
  bool get hasAnyCachedLogs => hasLogs || _pendingLogs.isNotEmpty;
  int get totalLogsMemoryBytes => _logsMemoryBytes + _pendingLogsMemoryBytes;
  String get appliedInlineSearchQuery => _appliedInlineSearch.query;
  String get inlineSearchQuery => _inlineSearch.query;
  TextSearchConfig get inlineSearch => _inlineSearch;
  TextSearchConfig get appliedInlineSearch => _appliedInlineSearch;
  TextSearchPattern get inlineSearchPattern =>
      TextSearchPattern.fromConfig(_appliedInlineSearch);
  bool get inlineSearchHasError => inlineSearchPattern.hasError;
  String? get inlineSearchErrorText => inlineSearchPattern.errorText;
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

  bool get isIosLogContext => device is IosDevice;

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

  /// Called when this device's tab is first activated. Starts log capture once.
  void activate() {
    if (_isImported || _disposed || _activated) return;
    _activated = true;
    if (isConnected) {
      unawaited(startLogcat());
    }
  }

  /// Replaces the log buffer with [entries] imported from a file.
  /// Only valid on controllers created via [LogController.imported].
  void loadImportedEntries(List<LogEntry> entries, String fileName) {
    assert(_isImported);
    _importedFileName = fileName;
    _replaceStoredLogs(entries);
    _notify();
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

  void clearLogs() {
    clearSelectedRows(notify: false);
    _clearStoredLogs();
    _pendingLogs.clear();
    _pendingLogsMemoryBytes = 0;
    _notify();
  }

  Future<LogExportResult> exportLogs() async {
    return LogFileService.exportLogs(logs, device);
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
    final modeChanged = _setRowSelectionModeInternal(value);
    if (!modeChanged) return;
    if (!value) {
      clearSelectedRows(notify: false);
    }
    _notify();
  }


  bool _setRowSelectionModeInternal(bool value) {
    if (_rowSelectionMode == value) return false;
    _rowSelectionMode = value;
    return true;
  }

  bool _enableRowSelectionMode() => _setRowSelectionModeInternal(true);

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

    final modeChanged = _enableRowSelectionMode();

    if (shiftPressed) {
      selectRowRangeTo(filteredIndex, modeChanged: modeChanged);
      return null;
    }

    final shouldSelect = !_selectedRowIndices.contains(filteredIndex);
    final anchorChanged = _rowSelectionAnchorIndex != filteredIndex;
    _rowSelectionAnchorIndex = filteredIndex;
    final changed = shouldSelect
        ? _selectedRowIndices.add(filteredIndex)
        : _selectedRowIndices.remove(filteredIndex);
    final clearedMode =
    !shouldSelect && _selectedRowIndices.isEmpty
        ? _setRowSelectionModeInternal(false)
        : false;
    if (changed || anchorChanged || modeChanged || clearedMode) {
      _notify();
    }
    return shouldSelect;
  }

  void setRowSelected(int filteredIndex, bool selected) {
    if (!_isSelectableFilteredIndex(filteredIndex)) return;

    final modeChanged = selected ? _enableRowSelectionMode() : false;

    final changed = selected
        ? _selectedRowIndices.add(filteredIndex)
        : _selectedRowIndices.remove(filteredIndex);
    final clearedMode =
    !selected && _selectedRowIndices.isEmpty
        ? _setRowSelectionModeInternal(false)
        : false;
    if (changed || modeChanged || clearedMode) {
      _notify();
    }
  }

  void setSelectedRows(Set<int> indices) {
    final filteredSnapshot = filteredLogs;
    final next = indices
        .where((index) => _isSelectableFilteredIndex(index, filteredSnapshot))
        .toSet();
    if (const SetEquality<int>().equals(_selectedRowIndices, next)) {
      final modeChanged = _setRowSelectionModeInternal(next.isNotEmpty);
      if (modeChanged) {
        _notify();
      }
      return;
    }

    _selectedRowIndices
      ..clear()
      ..addAll(next);
    _setRowSelectionModeInternal(next.isNotEmpty);
    _notify();
  }

  void selectRowRangeTo(int filteredIndex, {bool modeChanged = false}) {
    final filteredSnapshot = filteredLogs;
    if (!_isSelectableFilteredIndex(filteredIndex, filteredSnapshot)) return;

    modeChanged = _enableRowSelectionMode() || modeChanged;

    if (_rowSelectionAnchorIndex == null) {
      final anchorChanged = _rowSelectionAnchorIndex != filteredIndex;
      _rowSelectionAnchorIndex = filteredIndex;
      final changed = _selectedRowIndices.add(filteredIndex);
      if (changed || anchorChanged || modeChanged) {
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
    if (changed || modeChanged) {
      _notify();
    }
  }

  void clearSelectedRows({bool notify = true}) {
    final changed =
        _selectedRowIndices.isNotEmpty ||
            _rowSelectionAnchorIndex != null ||
            _rowSelectionMode;
    if (!changed) return;
    _selectedRowIndices.clear();
    _rowSelectionAnchorIndex = null;
    _rowSelectionMode = false;
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
    _setFilterField(LogFilterField.message, value);
  }

  void onPackageFilterChanged(String value) {
    _setFilterField(LogFilterField.packageName, value);
  }

  void onPidTidFilterChanged(String value) {
    _setFilterField(LogFilterField.pidTid, value);
  }

  void onTagFilterChanged(String value) {
    _setFilterField(LogFilterField.tag, value);
  }

  void selectMessageFilterSuggestion(String value) {
    _setFilterField(LogFilterField.message, value, applyImmediately: true);
  }

  void selectPackageFilterSuggestion(String value) {
    _setFilterField(LogFilterField.packageName, value, applyImmediately: true);
  }

  void selectPidTidFilterSuggestion(String value) {
    _setFilterField(LogFilterField.pidTid, value, applyImmediately: true);
  }

  void selectTagFilterSuggestion(String value) {
    _setFilterField(LogFilterField.tag, value, applyImmediately: true);
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
    LogFilterField field,
    String value, {
    bool applyImmediately = false,
  }) {
    final selection = TextSelection.collapsed(offset: value.length);

    switch (field) {
      case LogFilterField.message:
        searchQuery = value;
        if (filterController.text != value) {
          filterController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
      case LogFilterField.packageName:
        packageFilterQuery = value;
        if (packageFilterController.text != value) {
          packageFilterController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
      case LogFilterField.pidTid:
        pidTidFilterQuery = value;
        if (pidTidFilterController.text != value) {
          pidTidFilterController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
      case LogFilterField.tag:
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
    final parsedFilters = LogFilters.parse(
      _inlineFilterText,
      fallbackLevel: LogLevel.defaultSelectionForPlatform(
        isIos: isIosLogContext,
      ),
      isIosLogContext: isIosLogContext,
    );
    _applyInlineDraftFilters(parsedFilters);
    _applyParsedFilters(parsedFilters);
  }

  void _applyParsedFilters(LogFilters parsedFilters) {
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

  LogFilters _parsedFiltersFromClassicInputs() {
    return LogFilters(
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

  void _applyInlineDraftFilters(LogFilters parsedFilters) {
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
    'm:${_appliedMessageTerms.join('')}',
    'r:${_appliedRawTerms.join('')}',
    'p:${_appliedPackageTerms.join('')}',
    'pt:${_appliedPidTidTerms.join('')}',
    't:${_appliedTagTerms.join('')}',
  ].join(' ');

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
    return device.displayLabel.primary;
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

    return LogEntryUtils.buildLoggingState(
      type: type,
      tag: tag ?? 'eagly session',
      message: effectiveMessage,
      packageName: device.id,
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

  Future<void> startLogcat() async {
    if (!isConnected) return;

    await _stopLogcatInternal(resetState: false);
    if (_disposed) return;

    clearSelectedRows(notify: false);
    _clearStoredLogs();
    _pendingLogs.clear();
    _pendingLogsMemoryBytes = 0;
    logcatState = LogcatState.running;
    _liveStreamInterrupted = false;
    _recovering = false;
    _recoveryAttempts = 0;
    _interruptionMessage = null;
    _lastStreamActivityAt = DateTime.now();
    _appendSessionStateEntry(LogEntryType.started);
    _notify();

    _attachLogStream();
    _startFlushTimer();
    _startWatchdog();
  }

  /// Subscribes to a fresh live stream. The subscription is captured so that
  /// late `onDone` / `onError` callbacks from a stream we have already replaced
  /// (or cancelled ourselves) are ignored.
  void _attachLogStream() {
    late final StreamSubscription<LogEntry> sub;
    sub = service.startLogStream().listen(
      (logEntry) {
        if (_disposed) return;
        _lastStreamActivityAt = DateTime.now();
        if (_liveStreamInterrupted || _recovering || _recoveryAttempts > 0) {
          _markStreamRecovered();
        }
        if (logEntry.isSpecialEntry) {
          _appendImmediateLogEntry(logEntry);
          return;
        }
        if (logcatState == LogcatState.paused) return;
        _pendingLogs.add(logEntry);
        _pendingLogsMemoryBytes += _estimateLogEntryBytes(logEntry);
      },
      onError: (Object error, StackTrace _) {
        if (_disposed || !identical(_logSub, sub)) return;
        unawaited(_onLiveStreamLost(reason: error.toString()));
      },
      onDone: () {
        if (_disposed || !identical(_logSub, sub)) return;
        unawaited(_onLiveStreamLost());
      },
      cancelOnError: true,
    );
    _logSub = sub;
  }

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      _flushPendingLogs();
    });
  }

  void _flushPendingLogs() {
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
  }

  Future<void> stopLogcat() => _stopLogcatInternal(resetState: true);

  Future<void> _stopLogcatInternal({required bool resetState}) async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;

    await _logSub?.cancel();
    _logSub = null;
    await service.stopActiveLogStream();

    if (resetState && !_disposed) {
      logcatState = LogcatState.stopped;
      _liveStreamInterrupted = false;
      _recovering = false;
      _recoveryAttempts = 0;
      _interruptionMessage = null;
      _appendSessionStateEntry(LogEntryType.stopped);
      _notify();
    }
  }

  // ── Stall detection & recovery ─────────────────────────────────────────────

  bool get _supportsStallWatchdog => device is AndroidDevice;

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    if (!_supportsStallWatchdog) return;
    _watchdogTimer = Timer.periodic(watchdogInterval, (_) {
      unawaited(_checkStreamLiveness());
    });
  }

  /// Periodically verifies that a silently-idle live stream still has a
  /// responsive device behind it. A wedged adb transport keeps the device
  /// listed as connected while no logs (and no end-of-stream) ever arrive, so
  /// an active probe is the only reliable signal.
  Future<void> _checkStreamLiveness() async {
    if (_disposed || _probeInFlight) return;
    if (logcatState != LogcatState.running) return;
    if (_liveStreamInterrupted || _recovering) return;
    final lastActivity = _lastStreamActivityAt;
    if (lastActivity == null) return;
    if (DateTime.now().difference(lastActivity) < streamStallThreshold) return;

    _probeInFlight = true;
    try {
      final alive = await service.pingDevice();
      if (_disposed || logcatState != LogcatState.running) return;
      if (_liveStreamInterrupted || _recovering) return;
      if (alive) {
        // Healthy but genuinely idle — reset the baseline so we don't re-probe
        // every tick.
        _lastStreamActivityAt = DateTime.now();
        return;
      }
      await _onLiveStreamLost(stalled: true, reason: 'no response from device');
    } finally {
      _probeInFlight = false;
    }
  }

  /// Handles a live stream that ended/errored unexpectedly, or one the watchdog
  /// found wedged. Tears down the stream while preserving captured logs, then
  /// either schedules automatic recovery or surfaces the warning banner.
  Future<void> _onLiveStreamLost({String? reason, bool stalled = false}) async {
    if (_disposed || logcatState == LogcatState.stopped) return;

    _flushTimer?.cancel();
    _flushTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _flushPendingLogs();
    await _logSub?.cancel();
    _logSub = null;
    await service.stopActiveLogStream();
    if (_disposed || logcatState == LogcatState.stopped) return;

    if (!isConnected) {
      _enterInterruptedState(
        'Live logging stopped — ${device.displayName} disconnected. '
        'Reconnect the device, then restart logging or open a new tab.',
      );
      return;
    }

    if (logcatState == LogcatState.paused) {
      _enterInterruptedState(
        'Live logging stopped while paused. Resume to reconnect, or open a '
        'new tab.',
      );
      return;
    }

    if (_recoveryAttempts >= _maxAutoRecoveryAttempts) {
      _enterInterruptedState(
        'Live logging stopped and could not be resumed automatically. '
        'Restart logging or open a new tab.',
      );
      return;
    }

    // Tiered recovery: a gentle stream restart first, escalating to an
    // `adb reconnect` once the gentle attempt has been tried (or immediately
    // for a watchdog-detected stall, which is always a wedged transport).
    _scheduleRecovery(reconnect: stalled || _recoveryAttempts >= 1);
  }

  void _scheduleRecovery({required bool reconnect}) {
    _recovering = true;
    _recoveryAttempts++;
    _interruptionMessage = null;
    _notify();

    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(recoveryBackoff, () async {
      if (_disposed || logcatState == LogcatState.stopped) return;
      if (!isConnected) {
        _enterInterruptedState(
          'Live logging stopped — ${device.displayName} disconnected.',
        );
        return;
      }

      if (reconnect) {
        await service.recoverConnection();
        if (_disposed || logcatState == LogcatState.stopped) return;
      }

      final alive = await service.pingDevice();
      if (_disposed || logcatState == LogcatState.stopped) return;
      if (!alive) {
        if (_recoveryAttempts < _maxAutoRecoveryAttempts) {
          _scheduleRecovery(reconnect: true);
        } else {
          _enterInterruptedState(
            'Live logging stopped — ${device.displayName} is not responding. '
            'Restart logging or open a new tab.',
          );
        }
        return;
      }

      _recovering = false;
      _lastStreamActivityAt = DateTime.now();
      _appendSessionStateEntry(
        LogEntryType.notice,
        message: 'Reconnecting live logging for ${device.displayName}…',
        tag: 'device connection',
      );
      _attachLogStream();
      _startFlushTimer();
      _startWatchdog();
    });
  }

  /// Called when activity resumes on a stream that had dropped. Clears the
  /// recovery/interruption state and (if a banner was showing) notes the resume.
  void _markStreamRecovered() {
    if (!_liveStreamInterrupted && !_recovering && _recoveryAttempts == 0) {
      return;
    }
    final wasInterrupted = _liveStreamInterrupted;
    _liveStreamInterrupted = false;
    _recovering = false;
    _recoveryAttempts = 0;
    _interruptionMessage = null;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    if (wasInterrupted) {
      _appendSessionStateEntry(
        LogEntryType.resumed,
        message: 'Live logging resumed for ${device.displayName}.',
        tag: 'device connection',
      );
    } else {
      _notify();
    }
  }

  void _enterInterruptedState(String message) {
    _recovering = false;
    _liveStreamInterrupted = true;
    _interruptionMessage = message;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _appendSessionStateEntry(
      LogEntryType.error,
      message: message,
      tag: 'device connection',
    );
  }

  /// Re-attaches the live stream while preserving captured logs. Used by the
  /// device-reconnect hook and the manual "Restart logging" banner action.
  Future<void> _resumeLiveStream({
    bool reconnect = false,
    String? message,
  }) async {
    if (_disposed || _isImported || !isConnected) return;

    await _stopLogcatInternal(resetState: false);
    if (_disposed) return;

    logcatState = LogcatState.running;
    _recovering = false;
    _recoveryAttempts = 0;
    _notify();

    if (reconnect) {
      await service.recoverConnection();
      if (_disposed || !isConnected) return;
    }

    _liveStreamInterrupted = false;
    _interruptionMessage = null;
    _lastStreamActivityAt = DateTime.now();
    _appendSessionStateEntry(
      LogEntryType.resumed,
      message: message,
      tag: message == null ? null : 'device connection',
    );
    _attachLogStream();
    _startFlushTimer();
    _startWatchdog();
  }

  /// Manual recovery triggered from the interruption banner. Preserves captured
  /// logs and forces an `adb reconnect` before re-attaching.
  Future<void> resumeLiveLogging() async {
    if (_disposed || _isImported || !isConnected) return;
    _recoveryAttempts = 0;
    await _resumeLiveStream(
      reconnect: true,
      message: 'Restarting live logging for ${device.displayName}…',
    );
  }

  void togglePauseResume() {
    if (logcatState == LogcatState.stopped) return;
    if (isPaused) {
      logcatState = LogcatState.running;
      // If the stream dropped while paused, re-attach (preserving logs) instead
      // of merely flipping the flag.
      if (_liveStreamInterrupted || _logSub == null) {
        unawaited(_resumeLiveStream());
        return;
      }
      _appendSessionStateEntry(LogEntryType.resumed);
      _notify();
    } else {
      logcatState = LogcatState.paused;
      _appendSessionStateEntry(LogEntryType.paused);
      _notify();
    }
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
        if (pattern.matches(
          log.valueForColumn(column, isIos: isIosLogContext),
        )) {
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

    final text = snapshot.formatForCopy(format);
    await Clipboard.setData(ClipboardData(text: text));
    return snapshot.length;
  }

  @override
  void onDeviceDisconnected() {
    if (_isImported) return;
    // Stopped tabs have no live capture to interrupt. For running/paused tabs
    // the intent is preserved so logging can resume on reconnect.
    if (logcatState == LogcatState.stopped) return;
    unawaited(_onLiveStreamLost(reason: '${device.displayName} disconnected'));
  }

  @override
  void onDeviceConnected() {
    if (_isImported) return;
    // Only running/paused tabs carry live-capture intent worth resuming; a
    // stopped tab falls through the switch and does nothing.
    switch (logcatState) {
      case LogcatState.running:
        unawaited(
          _resumeLiveStream(
            message:
                'Device reconnected: ${device.displayName}. Resumed live logging.',
          ),
        );
      case LogcatState.paused:
        // Keep the user's pause; clear the disconnect banner and let the manual
        // resume re-attach the stream.
        _liveStreamInterrupted = false;
        _interruptionMessage = null;
        _appendSessionStateEntry(
          LogEntryType.notice,
          message:
              'Device reconnected: ${device.displayName}. Resume to continue logging.',
          tag: 'device connection',
        );
      case LogcatState.stopped:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _watchdogTimer?.cancel();
    _recoveryTimer?.cancel();
    _debounceTimer?.cancel();
    _filterSaveDebounceTimer?.cancel();
    _inlineSearchDebounce?.cancel();
    unawaited(_logSub?.cancel());
    unawaited(service.stopActiveLogStream());
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

// -- Log Entry utils

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
