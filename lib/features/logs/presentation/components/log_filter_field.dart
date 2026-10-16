import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../presentation/components/anchored_popover.dart';
import '../../data/models/log_filters.dart';
import 'filter_bar_shared.dart';
import 'log_filter_controller.dart';
import 'log_filter_menu.dart';
import 'log_filter_pill.dart';

String get _filterShortcutLabel =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘L' : 'Ctrl+L';

/// The bar's type-to-filter field: the active filters as pills, then the
/// text input, with the "Filter by…" menu ([FilterMenu]) under it while it
/// has focus.
class LogFilterField extends StatefulWidget {
  const LogFilterField({super.key, required this.controller});

  final LogFilterController controller;

  @override
  State<LogFilterField> createState() => _LogFilterFieldState();
}

class _LogFilterFieldState extends State<LogFilterField> {
  final TextEditingController _text = TextEditingController();
  final ValueNotifier<int> _highlight = ValueNotifier(0);
  final PopoverController _menu = PopoverController();

  /// Shared by the menu and the text field, so a click in the menu keeps the
  /// caret in the field.
  final Object _tapGroup = Object();
  bool _focused = false;
  bool _hovered = false;

  /// Set by a Backspace in the empty field: the last pill shows as marked,
  /// and a second Backspace removes it.
  bool _removalArmed = false;

  LogFilterController get _controller => widget.controller;
  FocusNode get _focusNode => _controller.inputFocusNode;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant LogFilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.inputFocusNode.removeListener(_handleFocusChange);
      _focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _text.dispose();
    _highlight.dispose();
    _menu.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    setState(() {
      _focused = focused;
      _removalArmed = false;
    });
    focused ? _menu.open() : _menu.close();
  }

  void _openMenu() {
    _focusNode.requestFocus();
    _menu.open();
  }

  void _onChanged(String value) {
    if (_removalArmed) setState(() => _removalArmed = false);
    // A space straight after a complete `key:value` commits it, so tokens can
    // be typed one after another.
    if (value.endsWith(' ') && _isCommittableToken(value)) {
      _commitTyped(value);
      return;
    }
    _highlight.value = 0;
    _menu.open();
  }

  static bool _isCommittableToken(String value) {
    if ('"'.allMatches(value).length.isOdd) return false; // Still quoting.
    final tokens = tokenizeFilterText(value);
    return tokens.length == 1 && parseKeyedFilterToken(tokens.single) != null;
  }

  void _commitTyped(String text) {
    _controller.applyTyped(text);
    _clearText();
    _menu.close();
  }

  void _clearText() {
    _text.clear();
    _highlight.value = 0;
  }

  void _select(FilterMenuOption option) {
    final insert = option.insertText;
    if (insert != null) {
      _text.value = TextEditingValue(
        text: insert,
        selection: TextSelection.collapsed(offset: insert.length),
      );
      _highlight.value = 0;
      _focusNode.requestFocus();
      return;
    }
    _clearText();
    _menu.close();
    // A new draft pill opens its editor, which takes the focus from here.
    option.onSelected?.call();
  }

  List<FilterMenuOption> _options(BuildContext context) => [
    for (final (_, items) in filterMenuSections(
      context,
      _controller,
      _text.text,
    ))
      ...items,
  ];

  KeyEventResult _onKey(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.backspace && _text.text.isEmpty) {
      // Held down, Backspace stops at the pills rather than eating them.
      if (event is KeyRepeatEvent || _controller.lastPillId == null) {
        return KeyEventResult.handled;
      }
      if (_removalArmed) _controller.removeLastPill();
      setState(() => _removalArmed = !_removalArmed);
      return KeyEventResult.handled;
    }
    if (_removalArmed) setState(() => _removalArmed = false);

    if (key == LogicalKeyboardKey.escape) {
      if (_text.text.isNotEmpty) {
        _clearText();
      } else if (_menu.isOpen) {
        _menu.close();
      } else {
        _focusNode.unfocus();
      }
      return KeyEventResult.handled;
    }

    // Built from the live text, not the last frame's menu: a fast
    // type-then-↵ lands before the rebuild.
    final options = _options(context);
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (!_menu.isOpen) {
        _menu.open();
      } else if (options.isNotEmpty) {
        final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
        _highlight.value = (_highlight.value + step) % options.length;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_menu.isOpen && options.isNotEmpty) {
        _select(options[_highlight.value.clamp(0, options.length - 1)]);
      } else if (_text.text.trim().isNotEmpty) {
        _commitTyped(_text.text);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final style = FilterControlStyle.of(context);
    final colors = Theme.of(context).colorScheme;
    final controller = _controller;
    final hasPills = controller.hasPills;
    final input = _buildInput(context, style, hasPills: hasPills);
    final borderWidth = _focused ? 1.5 : 1.0;

    return AnchoredPopover(
      controller: _menu,
      width: 360,
      tapGroupId: _tapGroup,
      popoverBuilder: (context) => ListenableBuilder(
        listenable: Listenable.merge([_text, _highlight, controller]),
        builder: (context, _) {
          final sections = filterMenuSections(context, controller, _text.text);
          final count = sections.fold(0, (n, section) => n + section.$2.length);
          return FilterMenu(
            sections: sections,
            highlighted: count == 0 ? -1 : _highlight.value.clamp(0, count - 1),
            isIos: controller.isIos,
            hasQuery: _text.text.trim().isNotEmpty,
            onHover: (index) => _highlight.value = index,
            onSelect: _select,
          );
        },
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _openMenu,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: kFilterControlHeight),
            // Lines are pill-high; the padding makes up the rest of the
            // row's height, less the (focus-thickened) border.
            padding: EdgeInsets.fromLTRB(
              12,
              _verticalInset - borderWidth,
              5,
              _verticalInset - borderWidth,
            ),
            decoration: BoxDecoration(
              color: style.fill(hovered: _hovered && !_focused),
              borderRadius: BorderRadius.circular(kFilterControlRadius),
              border: Border.all(
                color: style.border(focused: _focused, active: hasPills),
                width: borderWidth,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: kFilterPillHeight,
                  child: Icon(
                    Icons.filter_list_rounded,
                    size: 16,
                    color: hasPills ? colors.primary : style.icon,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: hasPills
                      ? LayoutBuilder(
                          builder: (context, constraints) => Wrap(
                            spacing: 5,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ...buildFilterPills(
                                context,
                                controller,
                                armedId: _removalArmed
                                    ? controller.lastPillId
                                    : null,
                              ),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: math.min(120, constraints.maxWidth),
                                  maxWidth: constraints.maxWidth,
                                ),
                                child: IntrinsicWidth(child: input),
                              ),
                            ],
                          ),
                        )
                      : input,
                ),
                if (!hasPills && !_focused)
                  SizedBox(
                    height: kFilterPillHeight,
                    child: Center(
                      child: FilterKeyHint(label: _filterShortcutLabel),
                    ),
                  )
                else if (hasPills)
                  SizedBox(
                    height: kFilterPillHeight,
                    child: Center(
                      child: _ClearFiltersButton(
                        onPressed: controller.clearConditions,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Border plus padding above (and below) a pill-high line, so one line of
  /// the field is exactly as tall as the row's other controls.
  static const double _verticalInset =
      (kFilterControlHeight - kFilterPillHeight) / 2;

  Widget _buildInput(
    BuildContext context,
    FilterControlStyle style, {
    required bool hasPills,
  }) {
    final tagKey = _controller.isIos ? 'category' : 'tag';
    return Focus(
      onKeyEvent: (node, event) => _onKey(context, event),
      skipTraversal: true,
      child: SizedBox(
        height: kFilterPillHeight,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: _text,
            focusNode: _focusNode,
            groupId: _tapGroup,
            contextMenuBuilder: AnchoredPopover.textContextMenuBuilder,
            style: style.label,
            cursorHeight: 14,
            onTap: _menu.open,
            decoration: bareFilterInputDecoration(
              hintText: hasPills
                  ? 'Add filter…'
                  : 'Filter logs — type text, or $tagKey:Auth  -message:noise  '
                        'level:e',
              hintStyle: style.hint,
            ),
            onChanged: _onChanged,
          ),
        ),
      ),
    );
  }
}

/// The field's "Clear filters" ×, a fixed 28 px. An [IconButton]
/// won't do: Material 3 keeps its minimum size over tight constraints, which
/// stretched the field and pushed the × off its line.
class _ClearFiltersButton extends StatelessWidget {
  const _ClearFiltersButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Clear filters',
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: 28,
          child: Icon(
            Icons.close,
            size: 16,
            color: FilterControlStyle.of(context).icon,
          ),
        ),
      ),
    );
  }
}
