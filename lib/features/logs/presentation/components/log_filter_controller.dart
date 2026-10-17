import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/filter_condition.dart';
import '../../data/models/log_filters.dart';
import '../../data/models/log_level.dart';

/// Suggestion lists offered to a filter bar, keyed by field. Getters are pulled
/// lazily (only while a bar builds its suggestions) so the owner can back them
/// with live, cached data without paying a per-frame cost.
class LogFilterSuggestions {
  const LogFilterSuggestions({
    required this.recentMessageFilters,
    required this.recentPackageFilters,
    required this.knownPackageFilters,
    required this.recentPidTidFilters,
    required this.recentTagFilters,
  });

  final ValueGetter<List<String>> recentMessageFilters;
  final ValueGetter<List<String>> recentPackageFilters;
  final ValueGetter<List<String>> knownPackageFilters;
  final ValueGetter<List<String>> recentPidTidFilters;
  final ValueGetter<List<String>> recentTagFilters;

  static final LogFilterSuggestions empty = LogFilterSuggestions(
    recentMessageFilters: () => const [],
    recentPackageFilters: () => const [],
    knownPackageFilters: () => const [],
    recentPidTidFilters: () => const [],
    recentTagFilters: () => const [],
  );
}

/// Drives the log filter bar: a level threshold plus a list of
/// [FilterCondition] pills — each a field, an operator (contains, is, matches
/// regex, or any of those negated) and a value — and an optional age pill.
///
/// The pills are the source of truth; [state] is rebuilt from them on every
/// edit, and external state is split back into one pill per term by
/// [_syncPills]. The owner seeds the initial state and receives
/// updated state via [onStateChanged]; it can push external changes back in
/// with [updateState] (which never re-emits, avoiding feedback loops).
class LogFilterController extends ChangeNotifier {
  LogFilterController({
    required LogFilters initialState,
    required this.suggestions,
    required this.onStateChanged,
    required this.isIos,
    this.debounce = const Duration(milliseconds: 300),
  }) : _state = initialState {
    _syncPills();
  }

  /// Suggestion sources, pulled lazily while building suggestions.
  final LogFilterSuggestions suggestions;

  /// Invoked with the updated filter state whenever the user edits (debounced)
  /// or an immediate apply is requested.
  final ValueChanged<LogFilters> onStateChanged;

  /// Debounce applied to user edits before [onStateChanged] fires.
  final Duration debounce;

  /// Whether the hosting device is iOS (drives level labels + key names).
  final bool isIos;

  LogFilters _state;
  LogFilters get state => _state;

  LogLevel get selectedLevel => _state.level;
  LogLevel get defaultLevel =>
      LogLevel.defaultSelectionForPlatform(isIos: isIos);

  Timer? _debounceTimer;
  bool _disposed = false;

  // ── Emitting ───────────────────────────────────────────────────────────────

  /// Records a user edit's [next] state and emits it — debounced by default,
  /// or immediately when [immediate] is set.
  void _emitUserState(LogFilters next, {bool immediate = false}) {
    _state = next;
    _debounceTimer?.cancel();
    if (immediate) {
      _emit();
    } else {
      _debounceTimer = Timer(debounce, _emit);
    }
  }

  void _emit() {
    if (_disposed) return;
    onStateChanged(_state);
  }

  /// Applies the current state immediately (submit / Enter).
  void applyNow() {
    _debounceTimer?.cancel();
    _emit();
  }

  /// Applies a debounced edit now, if one is waiting; otherwise does nothing.
  void flushPending() {
    if (_debounceTimer?.isActive ?? false) applyNow();
  }

  /// Changes the log level from the bar's dropdown. Applied immediately.
  void setLevel(LogLevel level) {
    if (level == _state.level) return;
    _state = _state.copyWith(level: level);
    _syncPills();
    notifyListeners();
    _debounceTimer?.cancel();
    _emit();
  }

  /// Reflects external filter state (a reset, or filters applied from
  /// elsewhere) without re-emitting.
  void updateState(LogFilters next) {
    _state = next;
    _debounceTimer?.cancel();
    _syncPills();
    notifyListeners();
  }

  /// Focus for the bar's type-to-filter field, the bar's primary control
  /// (⌘L); focusing it opens the "Filter by…" menu.
  final FocusNode inputFocusNode = FocusNode();

  List<FilterCondition> _conditions = const [];
  List<FilterCondition> get conditions => _conditions;

  int _nextConditionId = 0;
  int? _pendingEditorId;

  /// The pill id the age limit uses with [takePendingEditor] and
  /// [commitCondition]; condition ids are never negative.
  static const int ageConditionId = -1;

  /// The age limit pill's value, if one is set.
  Duration? get maxAge => state.maxAge;

  bool _ageDraft = false;

  /// Whether the age pill is shown: a limit is set, or one is being chosen.
  bool get showsAgePill => _ageDraft || maxAge != null;

  /// Whether any pill (draft or not) is on show.
  bool get hasPills => _conditions.isNotEmpty || showsAgePill;

  /// Number of active pills (drafts excluded, age included), for the badge on
  /// the Filter button.
  int get activeFilterCount =>
      _conditions.where((condition) => !condition.isDraft).length +
      (maxAge == null ? 0 : 1);

  /// Whether the pill [id] should open its editor as soon as it builds. True
  /// once, for the pill [addCondition] / [addAgeCondition] just created.
  bool takePendingEditor(int id) {
    if (_pendingEditorId != id) return false;
    _pendingEditorId = null;
    return true;
  }

  /// The pill shown last — the one Backspace in the empty field removes —
  /// or null when there are none. The age pill leads the row.
  int? get lastPillId => _conditions.isNotEmpty
      ? _conditions.last.id
      : showsAgePill
      ? ageConditionId
      : null;

  LogFilters _buildState({Duration? maxAge, bool keepMaxAge = true}) {
    final terms = {
      for (final field in FilterConditionField.values) field: <FilterTerm>[],
    };
    for (final condition in _conditions) {
      final term = condition.toTerm();
      if (term != null) terms[condition.field]!.add(term);
    }
    return LogFilters.fromTerms(
      level: state.level,
      messageTerms: terms[FilterConditionField.message]!,
      rawTerms: terms[FilterConditionField.anyField]!,
      packageTerms: terms[FilterConditionField.packageName]!,
      pidTidTerms: terms[FilterConditionField.pidTid]!,
      tagTerms: terms[FilterConditionField.tag]!,
      maxAge: keepMaxAge ? state.maxAge : maxAge,
    );
  }

  void _setConditions(List<FilterCondition> next, {bool immediate = true}) {
    _conditions = List.unmodifiable(next);
    notifyListeners();
    _emitUserState(_buildState(), immediate: immediate);
  }

  // ── Pill editing ───────────────────────────────────────────────────────────

  /// Adds an empty (draft) pill for [field] and marks its editor to open. A
  /// draft filters nothing, so nothing is emitted until it gets a value.
  FilterCondition addCondition(FilterConditionField field) {
    final condition = FilterCondition(id: _nextConditionId++, field: field);
    _conditions = List.unmodifiable([..._conditions, condition]);
    _pendingEditorId = condition.id;
    notifyListeners();
    return condition;
  }

  /// Adds a complete pill and applies it at once — the "Filter by…" menu's
  /// "Tag contains auth" rows.
  void addConditionWithValue(
    FilterConditionField field,
    String value, {
    FilterOperator operator = FilterOperator.contains,
  }) {
    if (value.trim().isEmpty) return;
    _setConditions([
      ..._conditions,
      FilterCondition(
        id: _nextConditionId++,
        field: field,
        operator: operator,
        value: value.trim(),
      ),
    ]);
  }

  /// Changes pill [id]'s operator and/or value. A value edit is debounced like
  /// typing; an operator change applies at once.
  void updateCondition(int id, {FilterOperator? operator, String? value}) {
    final index = _conditions.indexWhere((condition) => condition.id == id);
    if (index < 0) return;
    final next = [..._conditions];
    next[index] = next[index].copyWith(operator: operator, value: value);
    _setConditions(next, immediate: value == null);
  }

  void removeCondition(int id) {
    _setConditions([
      for (final condition in _conditions)
        if (condition.id != id) condition,
    ]);
  }

  /// Shows an empty age pill and marks its editor to open.
  void addAgeCondition() {
    _ageDraft = true;
    _pendingEditorId = ageConditionId;
    notifyListeners();
  }

  /// Called when pill [id]'s editor closes: drops it if still a draft, else
  /// applies any edit still waiting on the debounce.
  void commitCondition(int id) {
    if (id == ageConditionId) {
      _ageDraft = false;
      notifyListeners();
      return;
    }
    final condition = _conditions.where((c) => c.id == id).firstOrNull;
    if (condition == null) return;
    if (condition.isDraft) {
      _conditions = List.unmodifiable(
        _conditions.where((c) => c.id != id).toList(),
      );
      notifyListeners();
      return;
    }
    flushPending();
  }

  /// Sets (or, with null, removes) the age limit. Applied immediately.
  void setMaxAge(Duration? maxAge) {
    if (maxAge == state.maxAge) return;
    _emitUserState(
      _buildState(maxAge: maxAge, keepMaxAge: false),
      immediate: true,
    );
    notifyListeners();
  }

  /// Removes every pill and the age limit; the level stays.
  void clearConditions() {
    _conditions = const [];
    _ageDraft = false;
    _emitUserState(_buildState(keepMaxAge: false), immediate: true);
    notifyListeners();
  }

  /// Applies typed filter syntax at once: every `[-]key[=|~]:value` token
  /// becomes a pill (or sets the level / age limit), and bare words become
  /// "Any field" pills — [LogFilters.parse]'s rules, so typing `tag:Auth
  /// -message:noise` builds the filter it reads as.
  void applyTyped(String text) {
    final parsed = LogFilters.parse(
      text,
      fallbackLevel: state.level,
      isIosLogContext: isIos,
    );
    _conditions = List.unmodifiable([..._conditions, ..._pillsFor(parsed)]);
    final maxAge = parsed.maxAge ?? state.maxAge;
    _emitUserState(
      _buildState(
        maxAge: maxAge,
        keepMaxAge: false,
      ).copyWith(level: parsed.level),
      immediate: true,
    );
    notifyListeners();
  }

  /// Removes the pill [lastPillId] names, if any.
  void removeLastPill() {
    final id = lastPillId;
    if (id == null) return;
    if (id == ageConditionId) {
      _ageDraft = false;
      if (maxAge == null) {
        notifyListeners();
      } else {
        setMaxAge(null);
      }
      return;
    }
    removeCondition(id);
  }

  /// Replaces any package pills with one `Package contains [packageName]` and
  /// applies it immediately.
  void setPackageFilter(String packageName) {
    _setConditions([
      for (final condition in _conditions)
        if (condition.field != FilterConditionField.packageName) condition,
      FilterCondition(
        id: _nextConditionId++,
        field: FilterConditionField.packageName,
        value: packageName,
      ),
    ]);
  }

  // ── State ⇄ pills ──────────────────────────────────────────────────────────

  /// Everything but the level, for telling whether [state] says something the
  /// pills don't already (a level change alone must not rebuild them, or an
  /// open editor would lose its pill).
  String _termsKey(LogFilters filters) => LogFilters.compose(
    filters.copyWith(level: defaultLevel),
    defaultLevel: defaultLevel,
    isIos: isIos,
  );

  /// Splits [state] into pills, unless the pills already say the same.
  void _syncPills() {
    if (_termsKey(_buildState()) == _termsKey(state)) return;
    _conditions = List.unmodifiable(_pillsFor(state));
  }

  /// One new pill per term of [filters], in the order the bar shows them.
  List<FilterCondition> _pillsFor(LogFilters filters) {
    FilterCondition pill(FilterConditionField field, FilterTerm term) =>
        FilterCondition(
          id: _nextConditionId++,
          field: field,
          operator: FilterOperator.of(term.mode, negate: term.negate),
          value: term.value,
        );
    return [
      for (final term in filters.packageTerms)
        pill(FilterConditionField.packageName, term),
      for (final term in filters.tagTerms) pill(FilterConditionField.tag, term),
      for (final term in filters.pidTidTerms)
        pill(FilterConditionField.pidTid, term),
      for (final term in filters.messageTerms)
        pill(FilterConditionField.message, term),
      for (final term in filters.rawTerms)
        pill(FilterConditionField.anyField, term),
    ];
  }

  /// Focuses the type-to-filter field, which opens its menu.
  void focusPrimaryField() => inputFocusNode.requestFocus();

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    inputFocusNode.dispose();
    super.dispose();
  }
}
