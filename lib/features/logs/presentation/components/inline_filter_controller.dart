import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/log_filters.dart';
import '../../data/models/log_level.dart';

/// Per-field suggestion providers for the inline filter bar. The bar pulls the
/// current lists lazily (only while building suggestions) so callers can back
/// these with live, cached data without paying a per-frame cost.
class InlineFilterSuggestionSources {
  const InlineFilterSuggestionSources({
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

  static final InlineFilterSuggestionSources empty =
      InlineFilterSuggestionSources(
        recentMessageFilters: () => const [],
        recentPackageFilters: () => const [],
        knownPackageFilters: () => const [],
        recentPidTidFilters: () => const [],
        recentTagFilters: () => const [],
      );
}

/// Drives the inline filter bar independently of the owning feature controller.
///
/// Owns the text controller + focus node, debounces user edits, and emits the
/// parsed [LogFilters] configuration through [onConfigChanged]. Because it is a
/// dedicated [ChangeNotifier], keystrokes rebuild only the bar rather than the
/// whole log view.
///
/// External state (a level change, a classic-field edit, or a filter reset) is
/// pushed back in via [setTextExternally], which updates the text *without*
/// re-emitting a config — preventing feedback loops with the owner.
class InlineFilterController extends ChangeNotifier {
  InlineFilterController({
    required bool isIos,
    required this.sources,
    required this.onConfigChanged,
    String initialText = '',
    this.debounce = const Duration(milliseconds: 300),
  }) : _isIos = isIos {
    textController = InlineFilterTextController(text: initialText);
    textController.addListener(_handleTextChanged);
  }

  /// Suggestion data sources, pulled lazily while building suggestions.
  final InlineFilterSuggestionSources sources;

  /// Called with the freshly parsed configuration whenever the user edits the
  /// text (debounced) or an immediate apply is requested.
  final ValueChanged<LogFilters> onConfigChanged;

  /// Debounce applied to user edits before [onConfigChanged] fires.
  final Duration debounce;

  late final InlineFilterTextController textController;
  final FocusNode focusNode = FocusNode();

  bool _isIos;
  bool get isIos => _isIos;

  Timer? _debounceTimer;
  bool _suppressEmit = false;
  bool _disposed = false;

  /// Updates the platform context (drives level labels + key display names).
  void updateIsIos(bool value) {
    if (_isIos == value) return;
    _isIos = value;
    notifyListeners();
  }

  /// Parses the current text into a filter configuration.
  LogFilters parseConfig() => LogFilters.parse(
    textController.text,
    fallbackLevel: LogLevel.defaultSelectionForPlatform(isIos: _isIos),
    isIosLogContext: _isIos,
  );

  void _handleTextChanged() {
    if (_suppressEmit) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _emit);
  }

  void _emit() {
    if (_disposed) return;
    onConfigChanged(parseConfig());
  }

  /// Applies the current text immediately, cancelling any pending debounce.
  /// Used for submit (Enter) and immediate suggestion application.
  void applyNow() {
    _debounceTimer?.cancel();
    _emit();
  }

  /// Simulates user input programmatically (used by tests and external
  /// entry points). Schedules the normal debounced emit.
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

  /// Replaces the text from a user-selected suggestion. Emits immediately when
  /// [applyImmediately] is set (a complete `key:value`). A bare key stub
  /// (`level:`) is inserted without emitting or debouncing — it waits for the
  /// user to supply a value.
  void applySuggestionText(
    String text, {
    required TextSelection selection,
    required bool applyImmediately,
  }) {
    _suppressEmit = true;
    _debounceTimer?.cancel();
    textController.value = TextEditingValue(text: text, selection: selection);
    _suppressEmit = false;
    if (applyImmediately) {
      _emit();
    }
  }

  /// Reflects external filter state without emitting a config. Used when the
  /// owner changes the filters through another surface (level dropdown, classic
  /// fields, clear).
  void setTextExternally(String text) {
    if (textController.text == text) return;
    _suppressEmit = true;
    _debounceTimer?.cancel();
    textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _suppressEmit = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
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
  };

  static bool isKnownKeyValueToken(String token) {
    final colonIndex = token.indexOf(':');
    if (colonIndex <= 0 || colonIndex == token.length - 1) return false;
    final key = token.substring(0, colonIndex).trim().toLowerCase();
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
