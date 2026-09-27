import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../presentation/theme/app_theme.dart';
import '../../log_controller.dart';
import 'filter_bar_shared.dart';

/// The filter row's always-visible search: highlights and steps through
/// matching lines without hiding any (the Filter button is what hides).
///
/// Collapsed it shows its shortcut; focused, or holding a query, it widens to
/// show the match-case / whole-word / regex toggles, the match count and
/// previous / next. Escape (or ×) clears it.
class LogSearchField extends StatefulWidget {
  const LogSearchField({super.key, required this.controller});

  final LogController controller;

  static const double collapsedWidth = 220;
  static const double expandedWidth = 400;

  @override
  State<LogSearchField> createState() => _LogSearchFieldState();
}

class _LogSearchFieldState extends State<LogSearchField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.inlineSearch.query,
  );
  bool _focused = false;
  bool _hovered = false;

  LogController get _log => widget.controller;
  FocusNode get _focusNode => _log.searchFocusNode;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant LogSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.searchFocusNode.removeListener(_handleFocusChange);
      _focusNode.addListener(_handleFocusChange);
    }
    // Follow queries set elsewhere: ⌘F on a selection, or a close.
    final query = _log.inlineSearch.query;
    if (query != _text.text) {
      _text.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _text.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
    // Leaving an empty field ends the search, so it collapses again.
    if (!_focusNode.hasFocus && _text.text.isEmpty) _log.closeSearchBar();
  }

  void _onChanged(String value) {
    if (!_log.searchBarVisible) _log.openSearchBar();
    _log.updateInlineSearch(_log.inlineSearch.copyWith(query: value));
  }

  void _close() {
    _log.closeSearchBar();
    _text.clear();
    _focusNode.unfocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      HardwareKeyboard.instance.isShiftPressed
          ? _log.onSearchPrev()
          : _log.onSearchNext();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _setOptions({bool? caseSensitive, bool? wholeWord, bool? regex}) {
    final search = _log.inlineSearch;
    _log.updateInlineSearch(
      search.copyWith(
        caseSensitive: caseSensitive ?? search.caseSensitive,
        wholeWord: wholeWord ?? search.wholeWord,
        regex: regex ?? search.regex,
      ),
      applyImmediately: true,
    );
  }

  static String get _shortcutLabel =>
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘F' : 'Ctrl+F';

  @override
  Widget build(BuildContext context) {
    final style = FilterControlStyle.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasQuery = _text.text.isNotEmpty;
    final expanded = _focused || hasQuery;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : LogSearchField.expandedWidth;
        final width =
            (expanded
                    ? LogSearchField.expandedWidth
                    : LogSearchField.collapsedWidth)
                .clamp(0.0, maxWidth);
        return MouseRegion(
          cursor: SystemMouseCursors.text,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: _focusNode.requestFocus,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: width,
              height: kFilterControlHeight,
              padding: const EdgeInsets.only(left: 10, right: 4),
              decoration: BoxDecoration(
                color: style.fill(hovered: _hovered && !_focused),
                borderRadius: BorderRadius.circular(kFilterControlRadius),
                border: Border.all(
                  color: style.border(focused: _focused, active: hasQuery),
                  width: _focused ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, size: 15, color: style.icon),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Focus(
                      onKeyEvent: _onKey,
                      skipTraversal: true,
                      child: TextField(
                        controller: _text,
                        focusNode: _focusNode,
                        style: style.label,
                        cursorHeight: 14,
                        decoration: InputDecoration(
                          hintText: 'Search logs',
                          hintStyle: style.hint,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: _onChanged,
                      ),
                    ),
                  ),
                  if (!expanded)
                    _KeyHint(label: _shortcutLabel)
                  else
                    ..._buildActiveControls(context, colors),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildActiveControls(BuildContext context, ColorScheme colors) {
    final search = _log.inlineSearch;
    final hasQuery = _text.text.isNotEmpty;
    final matches = hasQuery ? _log.searchMatchIndices.length : 0;
    final eagly = context.eaglyTheme;
    final hasError = _log.inlineSearchHasError;
    return [
      _OptionToggle(
        label: 'Aa',
        tooltip: 'Match case',
        value: search.caseSensitive,
        onPressed: () => _setOptions(caseSensitive: !search.caseSensitive),
      ),
      _OptionToggle(
        label: 'W',
        tooltip: 'Match whole word',
        value: search.wholeWord,
        onPressed: () => _setOptions(wholeWord: !search.wholeWord),
      ),
      _OptionToggle(
        label: '.*',
        tooltip: 'Use regular expression',
        value: search.regex,
        onPressed: () => _setOptions(regex: !search.regex),
      ),
      if (hasQuery) ...[
        const SizedBox(width: 6),
        Tooltip(
          message: hasError ? (_log.inlineSearchErrorText ?? '') : '',
          child: Text(
            hasError
                ? 'Invalid'
                : matches == 0
                ? 'No results'
                : '${_log.searchCurrentMatch + 1}/$matches',
            style: TextStyle(
              fontSize: 11.5,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: hasError
                  ? colors.error
                  : matches == 0
                  ? eagly.searchNoResultsTextColor
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
        _IconAction(
          icon: Icons.keyboard_arrow_up,
          tooltip: 'Previous match (⇧↵)',
          onPressed: matches > 0 ? _log.onSearchPrev : null,
        ),
        _IconAction(
          icon: Icons.keyboard_arrow_down,
          tooltip: 'Next match (↵)',
          onPressed: matches > 0 ? _log.onSearchNext : null,
        ),
      ],
      _IconAction(
        icon: Icons.close,
        tooltip: 'Clear search (Esc)',
        onPressed: _close,
      ),
    ];
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
      ),
    );
  }
}

class _OptionToggle extends StatelessWidget {
  const _OptionToggle({
    required this.label,
    required this.tooltip,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final bool value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: '$tooltip (${value ? 'on' : 'off'})',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(5),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 24,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: value ? colors.primary.withValues(alpha: 0.16) : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: value ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
    );
  }
}
