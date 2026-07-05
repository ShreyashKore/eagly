import 'dart:async';

import 'package:flutter/material.dart';

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

/// Drives the classic filter bar: separate message / package / pid-tid / tag
/// fields plus a level dropdown.
class ClassicFilterController extends LogFilterController {
  ClassicFilterController({
    required super.initialState,
    required super.suggestions,
    required super.onStateChanged,
    required super.isIos,
    super.debounce,
  }) {
    seedFields();
    for (final controller in _fieldControllers) {
      controller.addListener(_handleFieldChanged);
    }
  }

  final TextEditingController messageController = TextEditingController();
  final FocusNode messageFocusNode = FocusNode();
  final TextEditingController packageController = TextEditingController();
  final FocusNode packageFocusNode = FocusNode();
  final TextEditingController pidTidController = TextEditingController();
  final FocusNode pidTidFocusNode = FocusNode();
  final TextEditingController tagController = TextEditingController();
  final FocusNode tagFocusNode = FocusNode();

  late final List<TextEditingController> _fieldControllers = [
    messageController,
    packageController,
    pidTidController,
    tagController,
  ];

  TextEditingController _controllerFor(LogFilterField field) => switch (field) {
    LogFilterField.message => messageController,
    LogFilterField.packageName => packageController,
    LogFilterField.pidTid => pidTidController,
    LogFilterField.tag => tagController,
  };

  void _handleFieldChanged() {
    if (isSuppressed) return;
    emitUserState(_buildState());
  }

  LogFilters _buildState() => LogFilters.fromFields(
    level: state.level,
    message: messageController.text,
    package: packageController.text,
    pidTid: pidTidController.text,
    tag: tagController.text,
    // The classic bar has no age field, so carry the inline-set age through
    // rather than dropping it when the user edits a classic field.
    maxAge: state.maxAge,
  );

  void _setText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  /// Applies a suggestion chosen for [field]: sets the field and emits at once.
  void selectSuggestion(LogFilterField field, String value) {
    runSuppressed(() => _setText(_controllerFor(field), value));
    emitUserState(_buildState(), immediate: true);
  }

  /// Programmatic field input (tests / external callers). Debounced emit.
  void setFieldFromInput(LogFilterField field, String value) {
    final controller = _controllerFor(field);
    if (controller.text == value) {
      _handleFieldChanged();
      return;
    }
    _setText(controller, value);
  }

  @override
  void writeStateToFields() {
    _setText(messageController, state.messageText);
    _setText(packageController, state.packageText);
    _setText(pidTidController, state.pidTidText);
    _setText(tagController, state.tagText);
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
    for (final controller in _fieldControllers) {
      controller.removeListener(_handleFieldChanged);
    }
    messageController.dispose();
    messageFocusNode.dispose();
    packageController.dispose();
    packageFocusNode.dispose();
    pidTidController.dispose();
    pidTidFocusNode.dispose();
    tagController.dispose();
    tagFocusNode.dispose();
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
        children.add(
          TextSpan(
            style: baseStyle.copyWith(backgroundColor: backgroundColor),
            children: [
              TextSpan(
                text: keyText,
                style: baseStyle.copyWith(
                  backgroundColor: backgroundColor,
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: valueText,
                style: baseStyle.copyWith(
                  backgroundColor: backgroundColor,
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
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
