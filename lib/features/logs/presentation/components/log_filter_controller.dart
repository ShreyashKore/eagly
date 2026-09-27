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

/// Shared controller for the log filter bars (classic + inline).
///
/// Holds the current filter state as a [LogFilters], the suggestion sources,
/// the platform context, and the debounce→emit pipeline. The owner seeds the
/// initial state and receives updated state via [onStateChanged]; it can push
/// external changes back in with [updateState] (which never re-emits, avoiding
/// feedback loops).
///
/// Subclasses own the concrete text controllers / focus nodes for their layout
/// and translate between those widgets and [LogFilters].
abstract class LogFilterController extends ChangeNotifier {
  LogFilterController({
    required LogFilters initialState,
    required this.suggestions,
    required this.onStateChanged,
    required this.isIos,
    this.debounce = const Duration(milliseconds: 300),
  }) : _state = initialState;

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
  bool _suppressEmit = false;
  bool _disposed = false;

  // ── Subclass hooks ─────────────────────────────────────────────────────────

  /// Writes [state] into the subclass's text controllers. Always invoked inside
  /// [runSuppressed] so field listeners don't echo it back as a user edit.
  @protected
  void writeStateToFields();

  /// Requests focus for the bar's primary field and selects its contents.
  void focusPrimaryField();

  // ── Shared machinery ───────────────────────────────────────────────────────

  /// True while [writeStateToFields] is mutating controllers; subclass field
  /// listeners must ignore change events during this window.
  @protected
  bool get isSuppressed => _suppressEmit;

  /// Runs [action] with field listeners suppressed and pending debounce cleared.
  @protected
  void runSuppressed(VoidCallback action) {
    _suppressEmit = true;
    _debounceTimer?.cancel();
    action();
    _suppressEmit = false;
  }

  /// Called by subclasses when the user edits a field. Records [next] and emits
  /// it — debounced by default, or immediately when [immediate] is set.
  @protected
  void emitUserState(LogFilters next, {bool immediate = false}) {
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
    runSuppressed(writeStateToFields);
    notifyListeners();
    _debounceTimer?.cancel();
    _emit();
  }

  /// Reflects external filter state (a mode switch, a reset, or the sibling
  /// bar's edit) without re-emitting.
  void updateState(LogFilters next) {
    _state = next;
    runSuppressed(writeStateToFields);
    notifyListeners();
  }

  @protected
  void seedFields() => runSuppressed(writeStateToFields);

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// Drives the classic filter bar: a level dropdown, a quick message field, and
/// a list of [FilterCondition] pills — each a field, an operator (contains,
/// is, matches regex, or any of those negated) and a value.
///
/// The pills are the source of truth for everything the quick field doesn't
/// hold; [state] is rebuilt from them on every edit. External state is split
/// back into pills by [writeStateToFields]: the first plain message term goes
/// to the quick field, every other term becomes a pill.
class ClassicFilterController extends LogFilterController {
  ClassicFilterController({
    required super.initialState,
    required super.suggestions,
    required super.onStateChanged,
    required super.isIos,
    super.debounce,
  }) {
    seedFields();
    messageController.addListener(_handleFieldChanged);
  }

  /// The quick "message contains" field.
  final TextEditingController messageController = TextEditingController();
  final FocusNode messageFocusNode = FocusNode();

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

  /// Number of active pills (drafts excluded, age included), for the badge on
  /// the add-filter button.
  int get activeFilterCount =>
      _conditions.where((condition) => !condition.isDraft).length +
      (maxAge == null ? 0 : 1);

  /// Whether the pill [id] should open its editor as soon as it builds. True
  /// once, for the pill [addCondition] just created.
  bool takePendingEditor(int id) {
    if (_pendingEditorId != id) return false;
    _pendingEditorId = null;
    return true;
  }

  void _handleFieldChanged() {
    if (isSuppressed) return;
    emitUserState(_buildState());
  }

  LogFilters _buildState() {
    final terms = {
      for (final field in FilterConditionField.values) field: <FilterTerm>[],
    };
    final quick = messageController.text.trim();
    // The quick term goes first so that splitting this state back into pills
    // hands the same value back to the quick field.
    if (quick.isNotEmpty) {
      terms[FilterConditionField.message]!.add(FilterTerm(quick));
    }
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
      maxAge: state.maxAge,
    );
  }

  void _setConditions(List<FilterCondition> next, {bool immediate = true}) {
    _conditions = List.unmodifiable(next);
    notifyListeners();
    emitUserState(_buildState(), immediate: immediate);
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
    final next = _buildState();
    emitUserState(
      LogFilters.fromTerms(
        level: next.level,
        messageTerms: next.messageTerms,
        rawTerms: next.rawTerms,
        packageTerms: next.packageTerms,
        pidTidTerms: next.pidTidTerms,
        tagTerms: next.tagTerms,
        maxAge: maxAge,
      ),
      immediate: true,
    );
    notifyListeners();
  }

  /// Removes every pill and the age limit; the level and quick field stay.
  void clearConditions() {
    _conditions = const [];
    _ageDraft = false;
    final next = _buildState();
    emitUserState(
      LogFilters.fromTerms(level: next.level, messageTerms: next.messageTerms),
      immediate: true,
    );
    notifyListeners();
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

  // ── Quick message field ────────────────────────────────────────────────────

  void _setText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  /// Applies a suggestion chosen for the quick field: sets it and emits at once.
  void selectMessageSuggestion(String value) {
    runSuppressed(() => _setText(messageController, value));
    emitUserState(_buildState(), immediate: true);
  }

  /// Programmatic quick-field input (tests / external callers). Debounced emit.
  void setMessageFromInput(String value) {
    if (messageController.text == value) {
      _handleFieldChanged();
      return;
    }
    _setText(messageController, value);
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

  @override
  void writeStateToFields() {
    if (_termsKey(_buildState()) == _termsKey(state)) return;

    final messageTerms = [...state.messageTerms];
    final quickIndex = messageTerms.indexWhere(
      (term) => term.mode == FilterMatchMode.contains && !term.negate,
    );
    final quick = quickIndex < 0 ? '' : messageTerms.removeAt(quickIndex).value;
    _setText(messageController, quick);

    FilterCondition pill(FilterConditionField field, FilterTerm term) =>
        FilterCondition(
          id: _nextConditionId++,
          field: field,
          operator: FilterOperator.of(term.mode, negate: term.negate),
          value: term.value,
        );
    _conditions = List.unmodifiable([
      for (final term in state.packageTerms)
        pill(FilterConditionField.packageName, term),
      for (final term in state.tagTerms) pill(FilterConditionField.tag, term),
      for (final term in state.pidTidTerms)
        pill(FilterConditionField.pidTid, term),
      for (final term in messageTerms) pill(FilterConditionField.message, term),
      for (final term in state.rawTerms)
        pill(FilterConditionField.anyField, term),
    ]);
  }

  @override
  void focusPrimaryField() {
    messageFocusNode.requestFocus();
    messageController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: messageController.text.length,
    );
  }

  @override
  void dispose() {
    messageController.removeListener(_handleFieldChanged);
    messageController.dispose();
    messageFocusNode.dispose();
    super.dispose();
  }
}

/// Drives the inline filter bar: a single Logcat-style `key:value` field plus a
/// level dropdown.
class InlineFilterController extends LogFilterController {
  InlineFilterController({
    required super.initialState,
    required super.suggestions,
    required super.onStateChanged,
    required super.isIos,
    String? initialText,
    super.debounce,
  }) {
    // Seed with the field text at creation so the controller's default (empty)
    // selection is preserved — the field only recomputes suggestions once the
    // caret actually moves into it.
    textController = InlineFilterTextController(
      text: initialText ?? _composeText(state),
    );
    textController.addListener(_handleTextChanged);
  }

  late final InlineFilterTextController textController;
  final FocusNode focusNode = FocusNode();

  void _handleTextChanged() {
    if (isSuppressed) return;
    emitUserState(_parse());
  }

  LogFilters _parse() => LogFilters.parse(
    textController.text,
    fallbackLevel: defaultLevel,
    isIosLogContext: isIos,
  );

  String _composeText(LogFilters state) =>
      LogFilters.compose(state, defaultLevel: defaultLevel, isIos: isIos);

  /// Programmatic text input (tests / external callers). Debounced emit.
  void setTextFromInput(String text) {
    if (textController.text == text) {
      _handleTextChanged();
      return;
    }
    textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Replaces the text from a user-selected suggestion. Emits immediately for a
  /// complete `key:value` ([applyImmediately]); a bare key stub (`level:`) is
  /// inserted without emitting — it waits for the user to supply a value.
  void applySuggestionText(
    String text, {
    required TextSelection selection,
    required bool applyImmediately,
  }) {
    runSuppressed(
      () => textController.value = TextEditingValue(
        text: text,
        selection: selection,
      ),
    );
    if (applyImmediately) {
      emitUserState(_parse(), immediate: true);
    }
  }

  @override
  void writeStateToFields() {
    final text = _composeText(state);
    if (textController.text == text) return;
    textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void focusPrimaryField() {
    focusNode.requestFocus();
    textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: textController.text.length,
    );
  }

  @override
  void dispose() {
    textController.removeListener(_handleTextChanged);
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}

/// A [TextEditingController] that syntax-highlights recognised `key:value`
/// tokens inside the inline filter field.
class InlineFilterTextController extends TextEditingController {
  InlineFilterTextController({super.text});

  static const Set<String> _knownAliases = {
    'package',
    'pkg',
    'app',
    'process',
    'tag',
    'category',
    'message',
    'msg',
    'text',
    'pid',
    'tid',
    'thread',
    'pidtid',
    'level',
    'lvl',
    'priority',
    'age',
    'maxage',
    'since',
  };

  static bool isKnownKeyValueToken(String token) {
    final colonIndex = token.indexOf(':');
    if (colonIndex <= 0 || colonIndex == token.length - 1) return false;
    var key = token.substring(0, colonIndex).trim().toLowerCase();
    // Peel the advanced-syntax decorations: a leading `-` (negation) and a
    // trailing `=`/`~` (exact/regex) still resolve to a known key.
    if (key.startsWith('-')) key = key.substring(1);
    if (key.endsWith('=') || key.endsWith('~')) {
      key = key.substring(0, key.length - 1);
    }
    return _knownAliases.contains(key);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final theme = Theme.of(context);
    final textValue = text;
    final tokens = InlineFilterEditContext.scanTokens(textValue);
    if (tokens.isEmpty) {
      return TextSpan(text: textValue, style: baseStyle);
    }

    // Token pills paint an opaque background as part of the text run itself,
    // which is drawn *after* (and so on top of) RenderEditable's own
    // selection-highlight background. Left alone, that hides the native
    // selection color wherever a pill sits. We work around it by pre-slicing
    // any pill text that overlaps the current selection and swapping in the
    // selection color for that slice, so selecting through a pill still
    // reads as selected.
    final selectionColor = _effectiveSelectionColor(context);

    final children = <InlineSpan>[];
    var cursor = 0;
    for (final token in tokens) {
      if (cursor < token.start) {
        children.add(
          TextSpan(
            text: textValue.substring(cursor, token.start),
            style: baseStyle,
          ),
        );
      }

      final tokenText = token.text;
      if (isKnownKeyValueToken(tokenText)) {
        final colonIndex = tokenText.indexOf(':');
        final keyText = tokenText.substring(0, colonIndex + 1);
        final valueText = tokenText.substring(colonIndex + 1);
        final backgroundColor = theme.colorScheme.primaryContainer.withValues(
          alpha: 0.9,
        );
        final keyStyle = baseStyle.copyWith(
          backgroundColor: backgroundColor,
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        );
        final valueStyle = baseStyle.copyWith(
          backgroundColor: backgroundColor,
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w500,
        );
        children.add(
          TextSpan(
            children: [
              ..._selectionAwareSpans(
                text: keyText,
                start: token.start,
                style: keyStyle,
                selectionColor: selectionColor,
              ),
              ..._selectionAwareSpans(
                text: valueText,
                start: token.start + colonIndex + 1,
                style: valueStyle,
                selectionColor: selectionColor,
              ),
            ],
          ),
        );
      } else {
        children.add(TextSpan(text: tokenText, style: baseStyle));
      }
      cursor = token.end;
    }

    if (cursor < textValue.length) {
      children.add(
        TextSpan(text: textValue.substring(cursor), style: baseStyle),
      );
    }

    return TextSpan(style: baseStyle, children: children);
  }

  /// Splits [text] (which starts at absolute offset [start] within the field)
  /// around the current selection, if any, so the sub-range that's actually
  /// selected can be painted with [selectionColor] instead of [style]'s own
  /// background.
  List<TextSpan> _selectionAwareSpans({
    required String text,
    required int start,
    required TextStyle style,
    required Color? selectionColor,
  }) {
    final end = start + text.length;
    final sel = selection;
    if (selectionColor == null ||
        !sel.isValid ||
        sel.isCollapsed ||
        sel.end <= start ||
        sel.start >= end) {
      return [TextSpan(text: text, style: style)];
    }

    final selStart = sel.start.clamp(start, end);
    final selEnd = sel.end.clamp(start, end);
    final spans = <TextSpan>[];
    if (selStart > start) {
      spans.add(
        TextSpan(text: text.substring(0, selStart - start), style: style),
      );
    }
    spans.add(
      TextSpan(
        text: text.substring(selStart - start, selEnd - start),
        style: style.copyWith(backgroundColor: selectionColor),
      ),
    );
    if (selEnd < end) {
      spans.add(TextSpan(text: text.substring(selEnd - start), style: style));
    }
    return spans;
  }

  Color? _effectiveSelectionColor(BuildContext context) {
    return TextSelectionTheme.of(context).selectionColor ??
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.40);
  }
}

/// The token under the cursor plus the cursor offset, used to decide which
/// suggestions to surface as the user types.
class InlineFilterEditContext {
  const InlineFilterEditContext({
    required this.activeToken,
    required this.cursorOffset,
  });

  final InlineFilterToken activeToken;
  final int cursorOffset;

  static InlineFilterEditContext fromEditingValue(TextEditingValue value) {
    final text = value.text;
    final cursor = value.selection.isValid
        ? value.selection.extentOffset.clamp(0, text.length)
        : text.length;
    final tokens = scanTokens(text);
    final activeToken = tokens.firstWhere(
      (token) => cursor >= token.start && cursor <= token.end,
      orElse: () => InlineFilterToken(start: cursor, end: cursor, text: ''),
    );
    return InlineFilterEditContext(
      activeToken: activeToken,
      cursorOffset: cursor,
    );
  }

  static List<InlineFilterToken> scanTokens(String text) {
    final tokens = <InlineFilterToken>[];
    var start = -1;
    var inQuotes = false;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char == '"') {
        inQuotes = !inQuotes;
      }
      if (!inQuotes && char.trim().isEmpty) {
        if (start >= 0) {
          tokens.add(
            InlineFilterToken(
              start: start,
              end: index,
              text: text.substring(start, index),
            ),
          );
          start = -1;
        }
        continue;
      }
      if (start < 0) {
        start = index;
      }
    }
    if (start >= 0) {
      tokens.add(
        InlineFilterToken(
          start: start,
          end: text.length,
          text: text.substring(start),
        ),
      );
    }
    return tokens;
  }
}

class InlineFilterToken {
  const InlineFilterToken({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;
}
