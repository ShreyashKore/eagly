import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../presentation/components/app_icon_button.dart';
import '../../../../presentation/components/min_width_box.dart';
import '../../../../presentation/theme/app_theme.dart';
import '../../log_controller.dart';
import 'filter_bar_shared.dart';

/// The filter row's always-visible search: highlights and steps through
/// matching lines without hiding any (the Filter button is what hides).
///
/// Collapsed it shows its shortcut; focused, or holding a query, it widens to
/// show the match-case / whole-word / regex toggles, the match count and
/// previous / next. Escape (or ×) clears it. Narrower than [showOptionsWidth]
/// it leaves the three toggles out; narrower still, it clips its right edge.
class const LogSearchField({
  super.key,
  required final LogController controller,

  /// Take all the width offered instead of the collapsed / expanded widths —
  /// for a row of its own in the stacked narrow-window layout.
  final bool fillWidth = false,
}) extends StatefulWidget {
  /// Widths at 1× zoom; they scale with the zoom.
  static const double collapsedWidth = 240;
  static const double expandedWidth = 380;

  /// Below this width the match-case / whole-word / regex toggles are left
  /// out, keeping room for the count, previous / next and clear.
  static const double showOptionsWidth = 320;

  /// The narrowest the row's content lays out without overflowing — the
  /// icon, a sliver of text, and the trailing controls — collapsed, expanded
  /// without the toggles, and expanded with them.
  static const double _minCollapsedContent = 110;
  static const double _minExpandedContent = 216;
  static const double _optionsWidth = 84;

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

  static const EdgeInsets _padding = EdgeInsets.only(left: 12, right: 6);

  static String get _shortcutLabel =>
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘F' : 'Ctrl+F';

  @override
  Widget build(BuildContext context) {
    final style = FilterControlStyle.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasQuery = _text.text.isNotEmpty;
    final expanded = _focused || hasQuery;

    // The widths follow the app zoom, which scales the text and icons inside.
    final expandedWidth = context.scaled(LogSearchField.expandedWidth);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : expandedWidth;
        final width = widget.fillWidth
            ? maxWidth
            : (expanded
                      ? expandedWidth
                      : context.scaled(LogSearchField.collapsedWidth))
                  .clamp(0.0, maxWidth);
        final showOptions =
            width >= context.scaled(LogSearchField.showOptionsWidth);
        final borderWidth = _focused ? 1.5 : 1.0;
        // Laid out at the box's target width from the first frame, the
        // controls stay put while the expand animation reveals them instead
        // of reflowing (or overflowing) as the box grows.
        final targetContentWidth =
            width - _padding.horizontal - 2 * borderWidth;
        final minContentWidth = context.scaled(
          !expanded
              ? LogSearchField._minCollapsedContent
              : LogSearchField._minExpandedContent +
                    (showOptions ? LogSearchField._optionsWidth : 0),
        );
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
              height: context.filterControlHeight,
              padding: _padding,
              decoration: BoxDecoration(
                color: style.fill(hovered: _hovered && !_focused),
                borderRadius: BorderRadius.circular(kFilterControlRadius),
                border: Border.all(
                  color: style.border(focused: _focused, active: hasQuery),
                  width: borderWidth,
                ),
              ),
              child: MinWidthBox(
                minWidth: math.max(minContentWidth, targetContentWidth),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 16, color: style.icon),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Focus(
                        onKeyEvent: _onKey,
                        skipTraversal: true,
                        child: TextField(
                          controller: _text,
                          focusNode: _focusNode,
                          style: style.label,
                          cursorHeight: 14,
                          decoration: bareFilterInputDecoration(
                            hintText: 'Search logs',
                            hintStyle: style.hint,
                          ),
                          onChanged: _onChanged,
                        ),
                      ),
                    ),
                    if (!expanded)
                      FilterKeyHint(label: _shortcutLabel)
                    else
                      ..._buildActiveControls(
                        context,
                        colors,
                        showOptions: showOptions,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildActiveControls(
    BuildContext context,
    ColorScheme colors, {
    required bool showOptions,
  }) {
    final search = _log.inlineSearch;
    final hasQuery = _text.text.isNotEmpty;
    final matches = hasQuery ? _log.searchMatchIndices.length : 0;
    final eagly = context.eaglyTheme;
    final hasError = _log.inlineSearchHasError;
    return [
      if (showOptions) ...[
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
      ],
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
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: hasError
                  ? colors.error
                  : matches == 0
                  ? eagly.searchNoResultsTextColor
                  : eagly.secondaryTextColor,
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

class const _OptionToggle({
  required final String label,
  required final String tooltip,
  required final bool value,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
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
          width: 28,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: value ? colors.primary.withValues(alpha: 0.16) : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: value ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class const _IconAction({
  required final IconData icon,
  required final String tooltip,
  required final VoidCallback? onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      padding: 5,
    );
  }
}
