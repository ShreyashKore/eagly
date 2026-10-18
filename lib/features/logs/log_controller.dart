import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:eagly/features/logs/data/models/recent_fliter_values.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../data/device.dart';
import '../../services/app_breadcrumbs.dart';
import 'data/models/log_entry.dart';
import 'data/models/log_filters.dart';
import 'data/models/log_level.dart';
import 'data/models/log_tab_settings.dart';
import 'services/filter_utils.dart';
import 'services/pid_package_index.dart';
import 'services/log_file_service.dart';
import '../../session/device_session_controller.dart';
import '../../session/feature_controller.dart';
import '../../utils/log_buffer.dart';
import '../../utils/log_entry_utils.dart';
import '../../utils/text_search_pattern.dart';
import 'presentation/components/log_filter_controller.dart';
import 'services/search_utils.dart';

enum LogcatState { stopped, running, paused }

/// Per-device logging feature: captures logcat / syslog, buffers + filters +
/// searches log entries, and manages row selection / copy / export. Holds no
/// device-selection or mirror state.
class LogController(super.session, {required LogTabSettings initialSettings})
    extends FeatureController {
  /// Upper bound for entries waiting for the next UI flush.  A full queue is
  /// flushed as one batch rather than appending the next entry immediately:
  /// immediate appends notify and rebuild the viewer once per log line.
  @visibleForTesting
  static int maxPendingLogs = 10000;

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

  this
    : _settings = initialSettings,
      _logsBuffer = LogBuffer<LogEntry>(
        baseCapacity: initialSettings.logLinesLimit,
      ) {
    final initialState = LogFilters.empty(selectedLogLevel);
    final suggestions = LogFilterSuggestions(
      recentMessageFilters: () => _recentFilters.message,
      recentPackageFilters: () => _recentFilters.package,
      knownPackageFilters: () => knownPackageFilters,
      recentPidTidFilters: () => _recentFilters.pidTid,
      recentTagFilters: () => _recentFilters.tag,
    );
    filter = LogFilterController(
      initialState: initialState,
      suggestions: suggestions,
      onStateChanged: _applyFilterConfig,
      isIos: isIosLogContext,
    );
    _syncLogBufferFilter();
    _pidPackageUpdatesSub = service.pidToPackageUpdates.listen(
      _learnRefreshedPidPackages,
    );
  }

  /// Creates a controller pre-loaded with [entries] from a log file.
  /// Live capture, clear, and start/stop are disabled.
  factory imported(
    DeviceSessionController session, {
    required LogTabSettings initialSettings,
  }) {
    final ctrl = LogController(session, initialSettings: initialSettings);
    ctrl._isImported = true;
    return ctrl;
  }

  final ScrollController scrollController = ScrollController();

  /// Item-level control of the log list, which measures rows lazily and only
  /// estimates the rest — so it can scroll to a row exactly where
  /// [scrollController] can only aim at an estimated offset. See
  /// [_followTail].
  final ListController listController = ListController();

  /// Focus for the filter row's search field, so ⌘F can jump into it.
  final FocusNode searchFocusNode = FocusNode();

  /// The filter bar's pills, focus and debounce. It emits updated
  /// [LogFilters] state through [_applyFilterConfig].
  late final LogFilterController filter;

  LogBuffer<LogEntry> _logsBuffer;
  final List<LogEntry> _pendingLogs = [];

  /// pid→package learned from entries that arrived with a resolved package, so
  /// a package filter still matches the entries whose mapping was missing.
  late final PidPackageIndex _pidPackages = PidPackageIndex(
    fallback: service.getProcessNameFromPid,
  );

  /// Bumped only when a newly learned pid→package mapping could change what the
  /// *active* package filter matches. Folded into the filter signature so the
  /// filtered list is rebuilt then — and, crucially, not on every unrelated
  /// mapping: a fresh stream learns hundreds of PIDs, and rebuilding a 50k
  /// buffer for each of them would cost a full rescan per frame.
  int _packageIndexRelevance = 0;

  /// Set when a learned mapping left the buffer's retention flags stale.
  /// Re-flagging rescans every stored entry, so it waits for the next append
  /// rather than running once per learned PID.
  bool _logBufferFilterDirty = false;

  /// PIDs [_requestPackageForUnknownPid] has already asked about. One refresh
  /// per PID: if that didn't resolve it — the process exited first, or the
  /// device's `ps` can't list it (older Androids reject `-A`) — asking again
  /// would only repeat the same `ps -A` every second for as long as it logs.
  final Set<String> _pidsAskedToResolve = {};

  StreamSubscription<LogEntry>? _logSub;
  StreamSubscription<Map<String, String>>? _pidPackageUpdatesSub;
  Timer? _flushTimer;
  Timer? _filterSaveDebounceTimer;
  Timer? _inlineSearchDebounce;
  Timer? _watchdogTimer;
  Timer? _recoveryTimer;

  /// Set while a [_notify] is queued for the end of the current frame.
  bool _notifyScheduled = false;

  var logcatState = LogcatState.stopped;

  final RecentFilterValues _recentFilters = RecentFilterValues();
  List<String> _knownPackageFilters = const [];
  int _knownPackageFingerprintLength = -1;
  int? _knownPackageFingerprintFirstId;
  int? _knownPackageFingerprintLastId;

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
  String _lastAppliedFilterSignature = '';
  LogLevel _lastLogLevel = LogLevel.verbose;

  /// The filter configuration currently applied to the log buffer. The level is
  /// tracked separately in [_settings]; only the term lists here drive matching.
  LogFilters _appliedFilters = LogFilters.empty(LogLevel.verbose);

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
  int get logCount => _logsBuffer.size;
  bool get hasAnyCachedLogs => hasLogs || _pendingLogs.isNotEmpty;
  int get totalLogsMemoryBytes => _logsMemoryBytes + _pendingLogsMemoryBytes;
  TextSearchConfig get inlineSearch => _inlineSearch;
  TextSearchConfig get appliedInlineSearch => _appliedInlineSearch;
  TextSearchPattern get inlineSearchPattern =>
      TextSearchPattern.fromConfig(_appliedInlineSearch);
  bool get inlineSearchHasError => inlineSearchPattern.hasError;
  String? get inlineSearchErrorText => inlineSearchPattern.errorText;

  /// Recently applied filter values, surfaced as autocomplete suggestions via
  /// the [LogFilterSuggestions] passed to the filter controllers.
  @visibleForTesting
  RecentFilterValues get recentFilters => _recentFilters;

  List<String> get knownPackageFilters {
    final storedLogs = logs;
    final firstId = storedLogs.firstOrNull?.id;
    final lastId = storedLogs.lastOrNull?.id;
    if (_knownPackageFingerprintLength == storedLogs.length &&
        _knownPackageFingerprintFirstId == firstId &&
        _knownPackageFingerprintLastId == lastId) {
      return List.unmodifiable(_knownPackageFilters);
    }

    final counts = <String, int>{};
    for (final log in storedLogs) {
      final value = packageFilterValue(log).trim();
      if (value.isEmpty) continue;
      counts.update(value, (count) => count + 1, ifAbsent: () => 1);
    }

    final sortedValues = counts.keys.toList(growable: false)
      ..sort((left, right) {
        final countComparison = counts[right]!.compareTo(counts[left]!);
        if (countComparison != 0) return countComparison;
        return left.toLowerCase().compareTo(right.toLowerCase());
      });

    _knownPackageFilters = sortedValues;
    _knownPackageFingerprintLength = storedLogs.length;
    _knownPackageFingerprintFirstId = firstId;
    _knownPackageFingerprintLastId = lastId;
    return List.unmodifiable(_knownPackageFilters);
  }

  bool get wrapText => _settings.wrapText;
  bool get autoScroll => _settings.autoScroll;
  LogLevel get selectedLogLevel => _settings.selectedLogLevel;
  int get logLinesLimit => _settings.logLinesLimit;
  Set<String> get hiddenColumns => _settings.hiddenColumns;
  Map<String, double> get columnWidths => _settings.columnWidths;

  bool get isIosLogContext => device is IosDevice;

  /// Notifies listeners, deferring to the end of the frame when we are inside
  /// one.
  ///
  /// Views call back into the controller from build-phase code paths (a
  /// [State.dispose] during `finalizeTree`, a `didUpdateWidget`, a selection
  /// callback fired from layout). Notifying there `setState()`s a locked or
  /// mid-build tree, which throws and — worse — loses the rebuild the
  /// notification was for.
  void _notify() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
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

  /// Sets the package/process filter to [packageName] and applies it
  /// immediately — used by the
  /// Apps feature's "View logs" action to jump straight to one app's lines.
  void applyPackageFilter(String packageName) {
    filter.setPackageFilter(packageName);
  }

  /// ⌘L: puts the caret in the filter field, which also opens its "Filter
  /// by…" menu.
  void activateFilterInput() => focusFilterInputs();

  void focusFilterInputs() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      filter.focusPrimaryField();
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
    if (!scrollController.hasClients || !listController.isAttached) return;
    final count = listController.numberOfItems;
    if (count == 0) return;
    // Not animateTo(maxScrollExtent): far from the end that extent is mostly
    // estimate, and the animation would overshoot into blank space as the
    // rows it passes get measured.
    listController.animateToItem(
      index: count - 1,
      scrollController: scrollController,
      alignment: 1.0,
      duration: (_) => const Duration(milliseconds: 300),
      curve: (_) => Curves.easeOut,
    );
  }

  /// Keeps the newest row in view after an append, while auto-scroll is on.
  ///
  /// The list estimates the height of every row it has not laid out yet, so
  /// right after a burst `maxScrollExtent` is largely a guess. Animating to it
  /// overshot the real end, showed the blank pane behind the list, then
  /// snapped back once the rows were measured. [ListController.jumpToItem]
  /// pins the last row to the bottom edge and corrects itself on the next
  /// layout instead.
  void _followTail() {
    if (!autoScroll || !scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !autoScroll) return;
      if (!scrollController.hasClients || !listController.isAttached) return;
      final count = listController.numberOfItems;
      if (count == 0) return;
      listController.jumpToItem(
        index: count - 1,
        scrollController: scrollController,
        alignment: 1.0,
      );
    });
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
    final clearedMode = !shouldSelect && _selectedRowIndices.isEmpty
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
    final clearedMode = !selected && _selectedRowIndices.isEmpty
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
    _filterSaveDebounceTimer?.cancel();
    clearSelectedRows(notify: false);
    final defaultLevel = LogLevel.defaultSelectionForPlatform(
      isIos: isIosLogContext,
    );
    final cleared = LogFilters.empty(defaultLevel);
    filter.updateState(cleared);
    _settings = _settings.copyWith(selectedLogLevel: defaultLevel);
    _appliedFilters = cleared;
    _syncLogBufferFilter();
    _invalidateFilteredLogs();
    focusFilterInputs();
    _notify();
  }

  /// Applies a complete filter [configuration], updating the filter bar and
  /// the active filter. Interactive edits normally flow through the filter
  /// controllers; this is the single entry point for driving filters
  /// programmatically (tests / external callers).
  @visibleForTesting
  void applyFilters(LogFilters configuration) {
    filter.updateState(configuration);
    _applyFilterConfig(configuration);
  }

  void setSelectedLogLevel(LogLevel level) => filter.setLevel(level);

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
    if (const SetEquality<String>().equals(hiddenColumns, columns)) return;
    _logViewerRevision++;
    _updateSettings(_settings.copyWith(hiddenColumns: Set.of(columns)));
    _invalidateSearchMatches();
  }

  void setColumnWidths(Map<String, double> widths) {
    if (const MapEquality<String, double>().equals(columnWidths, widths)) {
      return;
    }
    _updateSettings(_settings.copyWith(columnWidths: Map.of(widths)));
  }

  void setEditingLogLinesLimit(bool value) {
    _editingLogLinesLimit = value;
    _notify();
  }

  bool submitLogLinesLimit(int value) {
    if (value < 1000) {
      _editingLogLinesLimit = false;
      _notify();
      return false;
    }

    _editingLogLinesLimit = false;
    final storedLogs = logs;
    final previousCount = storedLogs.length;
    _updateSettings(_settings.copyWith(logLinesLimit: value));

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && !searchFocusNode.hasFocus) {
        searchFocusNode.requestFocus();
      }
    });
  }

  void closeSearchBar() {
    if (!_searchBarVisible) return;

    _inlineSearchDebounce?.cancel();
    _searchBarVisible = false;
    _inlineSearch = _inlineSearch.copyWith(query: '');
    _appliedInlineSearch = _appliedInlineSearch.copyWith(query: '');
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

  @visibleForTesting
  void onInlineSearchOptionsChanged(TextSearchConfig value) {
    updateInlineSearch(
      _inlineSearch.copyWith(
        caseSensitive: value.caseSensitive,
        wholeWord: value.wholeWord,
        regex: value.regex,
      ),
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
        _lastAppliedFilterSignature == appliedFilterSignature &&
        _lastLogLevel == selectedLogLevel) {
      return _cachedFilteredLogs!;
    }

    _lastAppliedFilterSignature = appliedFilterSignature;
    _lastLogLevel = selectedLogLevel;

    _cachedFilteredLogs = _logsBuffer.search(_matchesLogFilters);

    return _cachedFilteredLogs!;
  }

  /// Incrementally updates [_cachedFilteredLogs] after an append (and any
  /// eviction it triggered) instead of invalidating it, so a live-tail flush
  /// doesn't force a full rescan of the whole buffer. No-ops when the cache
  /// is already stale (filter/level changed since it was built) or unbuilt —
  /// the next [filteredLogs] access rebuilds it from scratch in that case.
  void _reconcileFilteredCache(LogEntry? added, List<LogEntry> evicted) {
    final cached = _cachedFilteredLogs;
    if (cached == null) return;
    if (_lastAppliedFilterSignature != _appliedFilterSignature ||
        _lastLogLevel != selectedLogLevel) {
      return;
    }

    if (evicted.isNotEmpty) {
      final evictedIds = evicted.map((entry) => entry.id).toSet();
      cached.removeWhere((entry) => evictedIds.contains(entry.id));
    }

    if (added != null && _matchesLogFilters(added)) {
      cached.add(added);
    }
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
    _cachedSearchMatchIndices = computeSearchMatches(
      filtered,
      hiddenColumns,
      isIosLogContext,
      inlineSearchPattern,
    );
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

  /// Records the applied terms/level, schedules recording of recent values, and
  /// refreshes the filtered view. Does not touch the filter bars.
  void _applyFilterConfig(LogFilters configuration) {
    final packageTermsChanged =
        configuration.packageSignature != _appliedFilters.packageSignature;
    _appliedFilters = configuration;
    if (selectedLogLevel != configuration.level) {
      _settings = _settings.copyWith(selectedLogLevel: configuration.level);
    }
    clearSelectedRows(notify: false);

    _filterSaveDebounceTimer?.cancel();
    _filterSaveDebounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _recentFilters.rememberFrom(configuration);
    });
    _syncLogBufferFilter();
    _invalidateFilteredLogs();
    _notify();

    // A package filter that just settled resolves against the processes
    // running now, rather than at the next poll or the next unresolved line.
    if (packageTermsChanged &&
        configuration.packageTerms.isNotEmpty &&
        isRunning) {
      service.requestPidToPackageRefresh();
    }
  }

  /// The applied filter's signature, extended with the pid→package index
  /// version while a package filter is active: learning a new mapping can make
  /// the same filter match entries it previously missed, so the cached filtered
  /// list has to be rebuilt.
  String get _appliedFilterSignature {
    final signature = _appliedFilters.signature;
    if (_appliedFilters.packageTerms.isEmpty) return signature;
    return '$signature|pp:$_packageIndexRelevance';
  }

  /// Records what [entry] teaches us about its PID, and marks the filtered list
  /// stale only when that mapping bears on the package terms in force — for a
  /// negated term too, where learning a mapping *hides* entries rather than
  /// revealing them.
  void _learnPidPackage(LogEntry entry) {
    final learned = _pidPackages.record(entry);
    if (learned != null && _bearsOnPackageFilter(learned)) {
      _packageIndexRelevance++;
      _logBufferFilterDirty = true;
    }
  }

  /// The same, for the mappings a device-side refresh added or changed. Unlike
  /// [_learnPidPackage] nothing else notifies afterwards, so this does.
  void _learnRefreshedPidPackages(Map<String, String> updates) {
    if (_disposed) return;
    var relevant = false;
    for (final MapEntry(key: pid, value: package) in updates.entries) {
      final learned = _pidPackages.learn(pid, package);
      if (learned != null && _bearsOnPackageFilter(learned)) relevant = true;
    }
    if (!relevant) return;
    _applyRelevantPidPackage();
    _notify();
  }

  bool _bearsOnPackageFilter(String learned) => _appliedFilters.packageTerms
      .any((term) => term.matches(learned) != term.matches(''));

  void _applyRelevantPidPackage() {
    _packageIndexRelevance++;
    // The buffer flagged stored entries before this mapping was known; ones
    // it now matches would otherwise be evicted first. Same filter, so
    // capacity is unchanged and this only re-flags — it never evicts.
    _syncLogBufferFilter();
  }

  /// While a package filter is active, a line from a PID nothing has resolved
  /// asks the device for a fresh pid→package map instead of waiting for the
  /// next poll — the usual case being the filtered app (re)launching.
  void _requestPackageForUnknownPid(LogEntry entry) {
    if (_appliedFilters.packageTerms.isEmpty) return;
    final pid = entry.pid.trim();
    if (pid.isEmpty || packageFilterValue(entry).isNotEmpty) return;
    if (_pidPackages.packageForPid(pid) != null) return;
    // Capped; clearing only risks one more ask per PID.
    if (_pidsAskedToResolve.length >= 4096) _pidsAskedToResolve.clear();
    if (!_pidsAskedToResolve.add(pid)) return;
    service.requestPidToPackageRefresh();
  }

  bool _matchesLogFilters(LogEntry log) {
    return matchesLogFilters(
      log,
      _appliedFilters,
      selectedLogLevel,
      packageForPid: _pidPackages.packageForPid,
    );
  }

  bool get _hasActiveRetentionFilter =>
      _appliedFilters.hasActiveRetentionFilter(isIosLogContext);

  LogFilter<LogEntry>? get _retentionFilter =>
      _hasActiveRetentionFilter ? _matchesLogFilters : null;

  void _syncLogBufferFilter() {
    _logBufferFilterDirty = false;
    _logsBuffer.setFilter(_retentionFilter);
  }

  /// Re-flags stored entries before an append can evict by stale flags.
  void _syncLogBufferFilterIfDirty() {
    if (_logBufferFilterDirty) _syncLogBufferFilter();
  }

  void _replaceStoredLogs(Iterable<LogEntry> entries) {
    for (final entry in entries) {
      _pidPackages.record(entry);
    }
    final nextBuffer = LogBuffer<LogEntry>(baseCapacity: logLinesLimit);
    nextBuffer.setFilter(_retentionFilter);
    for (final entry in entries) {
      nextBuffer.append(entry);
    }
    nextBuffer.trimToCapacity();
    _logsBuffer = nextBuffer;
    _logsMemoryBytes = estimateLogsBytes(_logsBuffer.getLogs());
    _invalidateFilteredLogs();
  }

  void _clearStoredLogs() {
    _logsBuffer.clear();
    _pidPackages.clear();
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
    // Entries still queued for the periodic flush arrived first; appending
    // around them would put a separator or session marker ("paused",
    // "stopped") ahead of up to one flush interval of earlier logs — and
    // after a stop, whose flush timer is already gone, strand them.
    _flushPendingLogs();

    _syncLogBufferFilterIfDirty();
    final evictedLogs = _logsBuffer.append(entry);
    final addedBytes = estimateLogEntryBytes(entry);
    final evictedBytes = estimateLogsBytes(evictedLogs);

    _logsMemoryBytes += addedBytes - evictedBytes;
    if (_logsMemoryBytes < 0) {
      _logsMemoryBytes = 0;
    }

    if (evictedLogs.isNotEmpty) {
      clearSelectedRows(notify: false);
    }

    _reconcileFilteredCache(entry, evictedLogs);
    _invalidateSearchMatches();
    _notify();

    _followTail();
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
    AppBreadcrumbs.action(
      'Started live logging for ${device.displayName}',
      category: 'logs.stream',
      data: {'deviceId': device.id},
    );

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
        _learnPidPackage(logEntry);
        if (logEntry.isSpecialEntry) {
          _appendImmediateLogEntry(logEntry);
          return;
        }
        if (logcatState == LogcatState.paused) return;
        _requestPackageForUnknownPid(logEntry);
        if (_pendingLogs.length >= maxPendingLogs) {
          // High-volume streams can fill this queue before the periodic
          // flush. Flush the whole queue once, rather than falling back to an
          // immediate append (and a widget rebuild) for every subsequent log.
          _flushPendingLogs();
        }
        _pendingLogs.add(logEntry);
        _pendingLogsMemoryBytes += estimateLogEntryBytes(logEntry);
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
    _syncLogBufferFilterIfDirty();

    var evictedMemoryBytes = 0;
    var didEvictStoredLogs = false;
    for (final logEntry in pendingLogs) {
      final evictedLogs = _logsBuffer.append(logEntry);
      _reconcileFilteredCache(logEntry, evictedLogs);
      if (evictedLogs.isEmpty) continue;
      didEvictStoredLogs = true;
      evictedMemoryBytes += estimateLogsBytes(evictedLogs);
    }

    _logsMemoryBytes += pendingLogsMemoryBytes - evictedMemoryBytes;
    if (_logsMemoryBytes < 0) {
      _logsMemoryBytes = 0;
    }

    if (didEvictStoredLogs) {
      clearSelectedRows(notify: false);
    }

    _invalidateSearchMatches();
    _notify();

    _followTail();
  }

  Future<void> stopLogcat() => _stopLogcatInternal(resetState: true);

  Future<void> _stopLogcatInternal({required bool resetState}) async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;

    // Cancelling our own subscription tears down just this tab's stream (its
    // tool process + the shared PID-cache poll's ref-count). Other live tabs on
    // the same device are untouched.
    await _logSub?.cancel();
    _logSub = null;

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
    AppBreadcrumbs.action(
      'Live log stream lost for ${device.displayName}',
      category: 'logs.stream',
      level: SentryLevel.warning,
      data: {
        if (reason != null) 'reason': reason,
        'stalled': stalled,
        'attempt': _recoveryAttempts,
      },
    );

    _flushTimer?.cancel();
    _flushTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _flushPendingLogs();
    await _logSub?.cancel();
    _logSub = null;
    if (_disposed || logcatState == LogcatState.stopped) return;

    if (!isConnected) {
      _enterInterruptedState(
        '${device.displayName} disconnected. Reconnect it, then restart '
        'logging or open a new tab.',
      );
      return;
    }

    if (logcatState == LogcatState.paused) {
      _enterInterruptedState(
        'The stream dropped while paused. Resume to reconnect, or open a '
        'new tab.',
      );
      return;
    }

    if (_recoveryAttempts >= _maxAutoRecoveryAttempts) {
      _enterInterruptedState(
        'It could not be resumed automatically. Restart logging or open a '
        'new tab.',
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
    AppBreadcrumbs.action(
      'Scheduling log recovery (attempt $_recoveryAttempts) for '
      '${device.displayName}',
      category: 'logs.stream',
      data: {'reconnect': reconnect, 'attempt': _recoveryAttempts},
    );
    _notify();

    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(recoveryBackoff, () async {
      if (_disposed || logcatState == LogcatState.stopped) return;
      if (!isConnected) {
        _enterInterruptedState(
          '${device.displayName} disconnected. Reconnect it, then restart '
          'logging or open a new tab.',
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
            '${device.displayName} is not responding. '
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
    AppBreadcrumbs.action(
      'Live log stream recovered for ${device.displayName}',
      category: 'logs.stream',
    );
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
    AppBreadcrumbs.action(
      'Log recovery gave up for ${device.displayName}',
      category: 'logs.stream',
      level: SentryLevel.error,
      data: {'message': message},
    );
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

    _flushPendingLogs();
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
    _filterSaveDebounceTimer?.cancel();
    _inlineSearchDebounce?.cancel();
    unawaited(_logSub?.cancel());
    unawaited(_pidPackageUpdatesSub?.cancel());
    _pendingLogs.clear();
    _pendingLogsMemoryBytes = 0;
    scrollController.dispose();
    listController.dispose();
    searchFocusNode.dispose();
    filter.dispose();
    super.dispose();
  }
}

/// --- Helpers

extension on LogFilters {
  /// A cheap change-detection key: two filters with the same signature
  /// filter identically. Terms carry mode + negation, so those are folded
  /// in. Fields, and terms within a field, are joined with distinct control
  /// chars that can't appear in a filter value, so filters never collide.
  String get signature => [
    level.code,
    'a:${maxAge?.inMilliseconds ?? ''}',
    'm:${_termSignatures(messageTerms)}',
    'r:${_termSignatures(rawTerms)}',
    'p:${_termSignatures(packageTerms)}',
    'pt:${_termSignatures(pidTidTerms)}',
    't:${_termSignatures(tagTerms)}',
  ].join('\u0000');

  String get packageSignature => _termSignatures(packageTerms);

  static String _termSignatures(List<FilterTerm> terms) =>
      terms.map((term) => term.signature).join('\u0001');

  bool hasActiveRetentionFilter(bool isIosLogContext) {
    final defaultLevel = LogLevel.defaultSelectionForPlatform(
      isIos: isIosLogContext,
    );
    return level.hierarchy < defaultLevel.hierarchy ||
        messageTerms.isNotEmpty ||
        rawTerms.isNotEmpty ||
        packageTerms.isNotEmpty ||
        pidTidTerms.isNotEmpty ||
        tagTerms.isNotEmpty ||
        maxAge != null;
  }
}
