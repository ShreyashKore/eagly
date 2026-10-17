import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../presentation/components/anchored_popover.dart';
import '../../../../presentation/components/app_icon_button.dart';
import '../../../../presentation/components/package_icon.dart';
import '../../../../presentation/theme/app_theme.dart';
import '../../../../presentation/theme/log_level_presentation.dart';
import '../../data/models/filter_condition.dart';
import '../../data/models/log_filters.dart';
import '../../data/models/log_level.dart';
import 'filter_bar_shared.dart';
import 'log_filter_controller.dart';

export 'filter_bar_shared.dart' show filterInputDecoration, kFilterFieldHeight;
export 'log_filter_controller.dart'
    show LogFilterController, LogFilterSuggestions;

/// The log filter bar: one type-to-filter field that holds the active
/// filters as pills, then a **Level** button.
///
/// Two ways in, one result:
/// * click the field and pick a field from its "Filter by…" menu — the new
///   pill opens its editor (field, operator, value);
/// * or just type: `tag:Auth`, `-message:noise`, `pid~:^12`, `level:e`,
///   `age:5m`. Space or ↵ turns each token into a pill, and plain text + ↵
///   adds the highlighted "Message contains …". Backspace in the empty field
///   marks the last pill, a second Backspace removes it.
///
/// Fully driven by a [LogFilterController]; it owns no filter state.
class LogFilterBar extends StatelessWidget {
  const LogFilterBar({
    super.key,
    required this.controller,
    this.showLevel = true,
  });

  final LogFilterController controller;

  /// False when the host lays the [LogLevelButton] out elsewhere — the
  /// stacked narrow-window layout puts it beside search.
  final bool showLevel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _FilterField(controller: controller)),
          if (showLevel) ...[
            const SizedBox(width: 6),
            _LevelButton(controller: controller),
          ],
        ],
      ),
    );
  }
}

/// The filter bar's **Level** button on its own, for a host that places it
/// apart from the filter field.
class LogLevelButton extends StatelessWidget {
  const LogLevelButton({super.key, required this.controller});

  final LogFilterController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _LevelButton(controller: controller),
  );
}

IconData _fieldIcon(FilterConditionField field) => switch (field) {
  FilterConditionField.packageName => Icons.apps_outlined,
  FilterConditionField.tag => Icons.sell_outlined,
  FilterConditionField.pidTid => Icons.numbers,
  FilterConditionField.message => Icons.notes_rounded,
  FilterConditionField.anyField => Icons.manage_search,
};

/// The fields in the order the menu offers them — most-used first, so a bare
/// ↵ after typing filters the message.
const List<FilterConditionField> _menuFieldOrder = [
  FilterConditionField.message,
  FilterConditionField.packageName,
  FilterConditionField.tag,
  FilterConditionField.pidTid,
  FilterConditionField.anyField,
];

/// The pill field a typed `key:` fills in; level and age have no pill field.
FilterConditionField? _fieldForKey(FilterKey key) => switch (key) {
  FilterKey.message => FilterConditionField.message,
  FilterKey.packageName => FilterConditionField.packageName,
  FilterKey.pidTid => FilterConditionField.pidTid,
  FilterKey.tag => FilterConditionField.tag,
  FilterKey.level || FilterKey.age => null,
};

/// Recent and known values for [field] that contain [query] (all of them when
/// it is blank), word-boundary matches first.
List<String> _suggestedValues(
  LogFilterController controller,
  FilterConditionField field,
  String query, {
  int limit = 6,
}) {
  final sources = controller.suggestions;
  final values = deduplicateFilterValues(switch (field) {
    FilterConditionField.packageName => [
      ...sources.recentPackageFilters(),
      ...sources.knownPackageFilters(),
    ],
    FilterConditionField.tag => sources.recentTagFilters(),
    FilterConditionField.pidTid => sources.recentPidTidFilters(),
    FilterConditionField.message ||
    FilterConditionField.anyField => sources.recentMessageFilters(),
  });
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return values.take(limit).toList();
  final preferred = <String>[];
  final secondary = <String>[];
  for (final value in values) {
    final normalized = value.toLowerCase();
    if (normalized == q || !normalized.contains(q)) continue;
    (filterBoundaryMatch(normalized, q) ? preferred : secondary).add(value);
  }
  return [...preferred, ...secondary].take(limit).toList();
}

/// Whether [field]'s suggestions lead with the app's launcher icon: Android
/// packages only, read from the cache the Apps pane fills ([PackageIcon]).
bool _showsAppIcons(
  LogFilterController controller,
  FilterConditionField field,
) => field == FilterConditionField.packageName && !controller.isIos;

String get _filterShortcutLabel =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘L' : 'Ctrl+L';

// ── The field ────────────────────────────────────────────────────────────────

class _FilterField extends StatefulWidget {
  const _FilterField({required this.controller});

  final LogFilterController controller;

  @override
  State<_FilterField> createState() => _FilterFieldState();
}

class _FilterFieldState extends State<_FilterField> {
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
  void didUpdateWidget(covariant _FilterField oldWidget) {
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

  void _select(_MenuOption option) {
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

  List<_MenuOption> _options(BuildContext context) => [
    for (final (_, items) in _menuSections(context, _controller, _text.text))
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
          final sections = _menuSections(context, controller, _text.text);
          final count = sections.fold(0, (n, section) => n + section.$2.length);
          return _FilterMenu(
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
                              ..._buildPills(
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

/// The active filters as pills — the age limit first, then one per condition.
List<Widget> _buildPills(
  BuildContext context,
  LogFilterController controller, {
  int? armedId,
}) {
  final isIos = controller.isIos;
  final maxAge = controller.maxAge;
  return [
    if (controller.showsAgePill)
      _FilterPill(
        key: const ValueKey('age-pill'),
        fieldLabel: 'Age',
        operatorLabel: 'within last',
        description: maxAge == null
            ? 'Age within last …'
            : 'Age within last ${formatMaxAge(maxAge)}',
        value: maxAge == null ? '' : formatMaxAge(maxAge),
        armed: armedId == LogFilterController.ageConditionId,
        openOnMount: controller.takePendingEditor(
          LogFilterController.ageConditionId,
        ),
        onRemove: () {
          controller.setMaxAge(null);
          controller.commitCondition(LogFilterController.ageConditionId);
        },
        onEditorClosed: () =>
            controller.commitCondition(LogFilterController.ageConditionId),
        editorBuilder: (context, close) => _AgeEditor(
          controller: controller,
          onDone: close,
          onRemove: () {
            close();
            controller.setMaxAge(null);
          },
        ),
      ),
    for (final condition in controller.conditions)
      _FilterPill(
        key: ValueKey(condition.id),
        fieldLabel: condition.field.label(isIos: isIos),
        operatorLabel: condition.operator.shortLabel,
        description:
            '${condition.field.label(isIos: isIos)} '
            '${condition.operator.label} '
            '${condition.isDraft ? '…' : condition.value.trim()}',
        value: condition.value.trim(),
        negated: condition.operator.negate,
        armed: armedId == condition.id,
        error: condition.toTerm()?.hasInvalidRegex ?? false
            ? 'Invalid regular expression — this filter matches '
                  '${condition.operator.negate ? 'every' : 'no'} line.'
            : null,
        openOnMount: controller.takePendingEditor(condition.id),
        onRemove: () => controller.removeCondition(condition.id),
        onEditorClosed: () => controller.commitCondition(condition.id),
        editorBuilder: (context, close) => _ConditionEditor(
          controller: controller,
          conditionId: condition.id,
          onDone: close,
          onRemove: () {
            close();
            controller.removeCondition(condition.id);
          },
        ),
      ),
  ];
}

// ── The "Filter by…" menu ────────────────────────────────────────────────────

/// One selectable row in the menu: it either runs [onSelected] (adding or
/// applying something) or, with [insertText], completes the typed text.
class _MenuOption {
  const _MenuOption({
    required this.icon,
    required this.label,
    this.packageName,
    this.onSelected,
    this.insertText,
  });

  final IconData icon;
  final InlineSpan label;

  /// Set on an Android package value, whose row then shows the app's icon
  /// (when the Apps pane has cached one) in place of [icon].
  final String? packageName;
  final VoidCallback? onSelected;
  final String? insertText;
}

/// The menu's sections for [rawQuery], the field's current text; flattened,
/// their options are the keyboard order.
List<(String, List<_MenuOption>)> _menuSections(
  BuildContext context,
  LogFilterController controller,
  String rawQuery,
) {
  final isIos = controller.isIos;
  final colors = Theme.of(context).colorScheme;
  final valueStyle = TextStyle(
    fontWeight: FontWeight.w600,
    color: colors.onSurface,
  );
  final mutedStyle = TextStyle(color: colors.onSurfaceVariant);
  final negatedStyle = TextStyle(
    color: colors.error,
    fontWeight: FontWeight.w600,
  );
  InlineSpan phrase(String field, String operator, String value, bool neg) =>
      TextSpan(
        children: [
          TextSpan(text: field),
          TextSpan(text: ' $operator ', style: neg ? negatedStyle : mutedStyle),
          TextSpan(text: value, style: valueStyle),
        ],
      );
  InlineSpan condition(
    FilterConditionField field,
    FilterOperator operator,
    String value,
  ) =>
      phrase(field.label(isIos: isIos), operator.label, value, operator.negate);
  String? packageOf(FilterConditionField field, String value) =>
      _showsAppIcons(controller, field) ? value : null;

  final query = rawQuery.trim();
  if (query.isEmpty) {
    return [
      (
        'Filter by',
        [
          for (final field in _menuFieldOrder)
            _MenuOption(
              icon: _fieldIcon(field),
              label: TextSpan(text: field.label(isIos: isIos)),
              onSelected: () => controller.addCondition(field),
            ),
          if (!controller.showsAgePill)
            _MenuOption(
              icon: Icons.schedule,
              label: const TextSpan(text: 'Age'),
              onSelected: controller.addAgeCondition,
            ),
        ],
      ),
    ];
  }

  final tokens = tokenizeFilterText(query);

  // One `key:value` being typed: offer exactly that filter, and values for it.
  if (tokens.length == 1) {
    final token = parseKeyedFilterToken(tokens.single, allowEmptyValue: true);
    if (token != null) {
      final value = token.value;
      switch (token.key) {
        case FilterKey.level:
          final q = value.toLowerCase();
          final levels = isIos ? LogLevel.iosValues : LogLevel.androidValues;
          return [
            (
              'Level',
              [
                for (final level in levels)
                  if (q.isEmpty ||
                      level.label.toLowerCase().startsWith(q) ||
                      level.code.toLowerCase().startsWith(q) ||
                      level.androidCode.toLowerCase() == q)
                    _MenuOption(
                      icon: Icons.signal_cellular_alt_rounded,
                      label: phrase(
                        'Level',
                        'is',
                        '${level.label} and above',
                        false,
                      ),
                      onSelected: () => controller.setLevel(level),
                    ),
              ],
            ),
          ];
        case FilterKey.age:
          final age = parseMaxAge(value);
          final presets = age == null
              ? const [
                  Duration(minutes: 1),
                  Duration(minutes: 5),
                  Duration(minutes: 15),
                  Duration(hours: 1),
                ]
              : [age];
          return [
            (
              'Age',
              [
                for (final preset in presets)
                  _MenuOption(
                    icon: Icons.schedule,
                    label: phrase(
                      'Age',
                      'within last',
                      formatMaxAge(preset),
                      false,
                    ),
                    onSelected: () => controller.setMaxAge(preset),
                  ),
              ],
            ),
          ];
        case FilterKey.message:
        case FilterKey.packageName:
        case FilterKey.pidTid:
        case FilterKey.tag:
          final field = _fieldForKey(token.key)!;
          final operator = FilterOperator.of(token.mode, negate: token.negate);
          final suggestions = _suggestedValues(controller, field, value);
          return [
            if (value.isNotEmpty)
              (
                'Add filter',
                [
                  _MenuOption(
                    icon: _fieldIcon(field),
                    label: condition(field, operator, value),
                    onSelected: () => controller.addConditionWithValue(
                      field,
                      value,
                      operator: operator,
                    ),
                  ),
                ],
              ),
            if (suggestions.isNotEmpty)
              (
                'Suggestions',
                [
                  for (final suggestion in suggestions)
                    _MenuOption(
                      icon: _fieldIcon(field),
                      label: condition(field, operator, suggestion),
                      packageName: packageOf(field, suggestion),
                      onSelected: () => controller.addConditionWithValue(
                        field,
                        suggestion,
                        operator: operator,
                      ),
                    ),
                ],
              ),
          ];
      }
    }
  }

  // Several tokens, some keyed: one row applies them all.
  if (tokens.any((token) => parseKeyedFilterToken(token) != null)) {
    return [
      (
        'Add filters',
        [
          _MenuOption(
            icon: Icons.filter_list_rounded,
            label: TextSpan(
              children: [
                TextSpan(text: 'Add ${tokens.length} filters  '),
                TextSpan(text: query, style: mutedStyle),
              ],
            ),
            onSelected: () => controller.applyTyped(query),
          ),
        ],
      ),
    ];
  }

  // Plain text: "<field> contains <text>" for every field, a leading `-`
  // making it "does not contain".
  final negate =
      tokens.length == 1 && query.length > 1 && query.startsWith('-');
  final text = negate ? query.substring(1) : query;
  final contains = FilterOperator.of(FilterMatchMode.contains, negate: negate);
  final age = parseMaxAge(query);

  final suggestions = <_MenuOption>[];
  for (final field in const [
    FilterConditionField.packageName,
    FilterConditionField.tag,
    FilterConditionField.message,
  ]) {
    for (final value in _suggestedValues(controller, field, text)) {
      suggestions.add(
        _MenuOption(
          icon: _fieldIcon(field),
          label: condition(field, contains, value),
          packageName: packageOf(field, value),
          onSelected: () => controller.addConditionWithValue(
            field,
            value,
            operator: contains,
          ),
        ),
      );
    }
  }

  // `ta` → `tag:` — the keys, for anyone learning the syntax.
  final keyPrefix = (negate ? text : query).toLowerCase();
  final keys = tokens.length == 1 && !query.contains(':')
      ? [
          for (final (key, label) in [
            ('message', 'Message'),
            ('package', 'Package'),
            (isIos ? 'category' : 'tag', isIos ? 'Category' : 'Tag'),
            ('pid', 'PID / TID'),
            ('level', 'Level'),
            ('age', 'Age'),
          ])
            if (key.startsWith(keyPrefix) && key != keyPrefix)
              _MenuOption(
                icon: Icons.keyboard_outlined,
                label: TextSpan(
                  children: [
                    TextSpan(
                      text: '${negate ? '-' : ''}$key:',
                      style: valueStyle,
                    ),
                    TextSpan(text: '  filter by $label', style: mutedStyle),
                  ],
                ),
                insertText: '${negate ? '-' : ''}$key:',
              ),
        ]
      : const <_MenuOption>[];

  return [
    (
      'Add filter',
      [
        for (final field in _menuFieldOrder)
          if (!negate || field.operators.contains(contains))
            _MenuOption(
              icon: _fieldIcon(field),
              label: condition(field, contains, text),
              onSelected: () => controller.addConditionWithValue(
                field,
                text,
                operator: contains,
              ),
            ),
        if (age != null && !controller.showsAgePill)
          _MenuOption(
            icon: Icons.schedule,
            label: phrase('Age', 'within last', formatMaxAge(age), false),
            onSelected: () => controller.setMaxAge(age),
          ),
      ],
    ),
    if (suggestions.isNotEmpty) ('Suggestions', suggestions.take(6).toList()),
    if (keys.isNotEmpty) ('Keys', keys),
  ];
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.sections,
    required this.highlighted,
    required this.isIos,
    required this.hasQuery,
    required this.onHover,
    required this.onSelect,
  });

  final List<(String, List<_MenuOption>)> sections;
  final int highlighted;
  final bool isIos;
  final bool hasQuery;
  final ValueChanged<int> onHover;
  final ValueChanged<_MenuOption> onSelect;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    var index = 0;
    for (final (title, items) in sections) {
      rows.add(_MenuSectionLabel(title));
      for (final option in items) {
        final i = index++;
        rows.add(
          _MenuRow(
            icon: option.icon,
            packageName: option.packageName,
            highlighted: i == highlighted,
            trailing: i == highlighted ? const _EnterHint() : null,
            onHover: () => onHover(i),
            onTap: () => onSelect(option),
            child: Text.rich(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }
    if (rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Text(
            'Type a value, then press ↵',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
            children: rows,
          ),
        ),
        Divider(
          height: 1,
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        _SyntaxHint(isIos: isIos),
      ],
    );
  }
}

/// The menu's footer: the typed syntax, so the shortcut is one glance away.
class _SyntaxHint extends StatelessWidget {
  const _SyntaxHint({required this.isIos});

  final bool isIos;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tag = isIos ? 'category' : 'tag';
    final muted = TextStyle(fontSize: 11, color: colors.onSurfaceVariant);
    Widget code(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: context.eaglyTheme.monoStyle.copyWith(
          fontSize: 11,
          color: colors.onSurface,
        ),
      ),
    );
    Widget item(String syntax, String meaning) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        code(syntax),
        const SizedBox(width: 4),
        Text(meaning, style: muted),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          item('$tag:Auth', 'contains'),
          item('-$tag:', 'not'),
          item('$tag=:', 'is'),
          item('$tag~:', 'regex'),
          item('level:e', 'level'),
          item('age:5m', 'age'),
        ],
      ),
    );
  }
}

// ── Level button ─────────────────────────────────────────────────────────────

class _LevelButton extends StatefulWidget {
  const _LevelButton({required this.controller});

  final LogFilterController controller;

  @override
  State<_LevelButton> createState() => _LevelButtonState();
}

class _LevelButtonState extends State<_LevelButton> {
  final PopoverController _popover = PopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final isIos = controller.isIos;
    final level = controller.selectedLevel.normalizeSelectionForPlatform(
      isIos: isIos,
    );
    final style = FilterControlStyle.of(context);
    final levels = isIos ? LogLevel.iosValues : LogLevel.androidValues;
    return AnchoredPopover(
      controller: _popover,
      width: 220,
      popoverBuilder: (context) => Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _MenuSectionLabel('Show this level and above'),
            for (final option in levels)
              _MenuRow(
                highlighted: option == level,
                trailing: option == level
                    ? Icon(
                        Icons.check,
                        size: 15,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  _popover.close();
                  controller.setLevel(option);
                },
                child: LogLevelLabel(
                  level: option,
                  isIos: isIos,
                  includeValueInLabel: true,
                  compact: true,
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
              ),
          ],
        ),
      ),
      child: FilterControlButton(
        icon: Icons.signal_cellular_alt_rounded,
        active: level != controller.defaultLevel,
        tooltip: 'Minimum log level',
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Level', style: style.hint),
            const SizedBox(width: 6),
            LogLevelLabel(
              level: level,
              isIos: isIos,
              compact: true,
              textStyle: style.label,
            ),
          ],
        ),
        trailing: Icon(Icons.expand_more, size: 16, color: style.icon),
        onPressed: _popover.toggle,
      ),
    );
  }
}

// ── Pill ─────────────────────────────────────────────────────────────────────

/// One active filter as a compact two-line chip: a small label naming the
/// field and how it matches ("Tag · excludes") floats over the value
/// ("Chatty"), so a chip is as wide as the longer of the two rather than the
/// whole sentence. Clicking it opens [editorBuilder] in a popover underneath.
class _FilterPill extends StatefulWidget {
  const _FilterPill({
    super.key,
    required this.fieldLabel,
    required this.operatorLabel,
    required this.description,
    required this.value,
    required this.onRemove,
    required this.onEditorClosed,
    required this.editorBuilder,
    this.negated = false,
    this.armed = false,
    this.error,
    this.openOnMount = false,
  });

  final String fieldLabel;

  /// The operator's short form, for the label line.
  final String operatorLabel;

  /// The filter as a sentence ("Tag does not contain Chatty"), which is what
  /// assistive technology reads for the chip.
  final String description;

  /// Blank while the pill is a draft.
  final String value;
  final bool negated;

  /// Marked by a first Backspace in the filter field: the next one removes it.
  final bool armed;

  /// Why the pill doesn't filter the way it reads, if it doesn't.
  final String? error;
  final bool openOnMount;
  final VoidCallback onRemove;
  final VoidCallback onEditorClosed;
  final Widget Function(BuildContext context, VoidCallback close) editorBuilder;

  @override
  State<_FilterPill> createState() => _FilterPillState();
}

class _FilterPillState extends State<_FilterPill> {
  final PopoverController _popover = PopoverController();
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    // Open before listening: a listener's setState can't run in initState.
    if (widget.openOnMount) _popover.open();
    _popover.addListener(_rebuild);
  }

  @override
  void dispose() {
    _popover.removeListener(_rebuild);
    _popover.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return AnchoredPopover(
      controller: _popover,
      width: 300,
      onClosed: widget.onEditorClosed,
      popoverBuilder: (context) => Padding(
        padding: const EdgeInsets.all(12),
        child: widget.editorBuilder(context, _popover.close),
      ),
      child: _buildPill(context),
    );
  }

  Widget _buildPill(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isOpen = _popover.isOpen;
    final lit = isOpen || widget.armed;
    final error = widget.error;
    final isDraft = widget.value.isEmpty;
    final accent = error != null ? colors.error : colors.primary;
    final labelStyle = TextStyle(
      fontSize: 10,
      height: 1.2,
      letterSpacing: 0.1,
      color: colors.onSurfaceVariant,
    );

    final pill = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: accent.withValues(
          alpha: widget.armed
              ? 0.24
              : _hovered || isOpen
              ? 0.20
              : 0.14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kFilterControlRadius - 1),
          // A hairline tint at rest; the fill carries the chip. Open or
          // marked for removal, it firms up to show which chip that is.
          side: BorderSide(
            color: accent.withValues(
              alpha: lit
                  ? 0.6
                  : _hovered
                  ? 0.22
                  : 0.12,
            ),
            width: widget.armed ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _popover.toggle,
          child: SizedBox(
            height: kFilterPillHeight,
            child: Padding(
              padding: const EdgeInsets.only(left: 9, right: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: widget.description,
                    excludeSemantics: true,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: widget.fieldLabel,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: accent,
                                  ),
                                ),
                                const TextSpan(text: ' · '),
                                TextSpan(
                                  text: widget.operatorLabel,
                                  style: widget.negated
                                      ? TextStyle(
                                          color: colors.error,
                                          fontWeight: FontWeight.w600,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle,
                          ),
                          Text(
                            isDraft ? 'Add a value…' : widget.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.2,
                              fontWeight: isDraft
                                  ? FontWeight.w400
                                  : FontWeight.w500,
                              color: isDraft
                                  ? colors.onSurfaceVariant
                                  : colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  SizedBox.square(
                    dimension: 18,
                    child: _hovered
                        ? Tooltip(
                            message: 'Remove filter',
                            child: InkWell(
                              onTap: widget.onRemove,
                              customBorder: const CircleBorder(),
                              child: Icon(
                                Icons.close,
                                size: 13,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.expand_more,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return error == null ? pill : Tooltip(message: error, child: pill);
  }
}

// ── Editors ──────────────────────────────────────────────────────────────────

/// Edits one [FilterCondition]: "Package  contains ▾  🗑" over the value
/// field. The operator opens as a list inside the card (popovers don't nest);
/// otherwise the card lists recent and known values for the field.
class _ConditionEditor extends StatefulWidget {
  const _ConditionEditor({
    required this.controller,
    required this.conditionId,
    required this.onDone,
    required this.onRemove,
  });

  final LogFilterController controller;
  final int conditionId;
  final VoidCallback onDone;
  final VoidCallback onRemove;

  @override
  State<_ConditionEditor> createState() => _ConditionEditorState();
}

class _ConditionEditorState extends State<_ConditionEditor> {
  late final TextEditingController _text = TextEditingController(
    text: _condition?.value ?? '',
  );
  final FocusNode _textFocus = FocusNode();
  bool _choosingOperator = false;

  FilterCondition? get _condition => widget.controller.conditions
      .where((condition) => condition.id == widget.conditionId)
      .firstOrNull;

  @override
  void dispose() {
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final condition = _condition;
        if (condition == null) return const SizedBox.shrink();
        return _buildEditor(context, condition);
      },
    );
  }

  Widget _buildEditor(BuildContext context, FilterCondition condition) {
    final field = condition.field;
    final operator = condition.operator;
    final canChooseOperator = field.operators.length > 1;
    final invalidRegex = condition.toTerm()?.hasInvalidRegex ?? false;
    final suggestions = _choosingOperator
        ? const <String>[]
        : _suggestedValues(widget.controller, field, _text.text);
    final appIcons = _showsAppIcons(widget.controller, field);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditorHeader(
          icon: _fieldIcon(field),
          label: field.label(isIos: widget.controller.isIos),
          onRemove: widget.onRemove,
          operator: _OperatorButton(
            label: operator.label,
            negated: operator.negate,
            open: _choosingOperator,
            onPressed: canChooseOperator
                ? () => setState(() => _choosingOperator = !_choosingOperator)
                : null,
          ),
        ),
        const SizedBox(height: 10),
        if (_choosingOperator)
          for (final option in field.operators)
            _MenuRow(
              highlighted: option == operator,
              trailing: option == operator
                  ? Icon(
                      Icons.check,
                      size: 15,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () {
                widget.controller.updateCondition(
                  condition.id,
                  operator: option,
                );
                setState(() => _choosingOperator = false);
                _textFocus.requestFocus();
              },
              child: Text(
                option.label,
                style: TextStyle(
                  color: option.negate
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            )
        else ...[
          TextField(
            controller: _text,
            focusNode: _textFocus,
            autofocus: true,
            contextMenuBuilder: AnchoredPopover.textContextMenuBuilder,
            style: const TextStyle(fontSize: 13),
            decoration: _cardInputDecoration(
              context,
              hintText: switch (operator.mode) {
                FilterMatchMode.contains => 'Type a value…',
                FilterMatchMode.exact => 'The whole value…',
                FilterMatchMode.regex => 'A regular expression…',
              },
              errorText: invalidRegex ? 'Invalid regular expression' : null,
            ),
            onChanged: (value) {
              setState(() {});
              widget.controller.updateCondition(condition.id, value: value);
            },
            onSubmitted: (_) => widget.onDone(),
          ),
          if (!canChooseOperator) ...[
            const SizedBox(height: 8),
            Text(
              'Matches text anywhere in the line.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _MenuSectionLabel('Suggestions'),
            for (final suggestion in suggestions)
              _MenuRow(
                icon: appIcons ? _fieldIcon(field) : null,
                packageName: appIcons ? suggestion : null,
                onTap: () {
                  _text.text = suggestion;
                  widget.controller.updateCondition(
                    condition.id,
                    value: suggestion,
                  );
                  widget.onDone();
                },
                child: Text(
                  suggestion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ],
      ],
    );
  }
}

/// Edits the age limit: a preset, or a custom `1h30m`-style duration.
class _AgeEditor extends StatefulWidget {
  const _AgeEditor({
    required this.controller,
    required this.onDone,
    required this.onRemove,
  });

  final LogFilterController controller;
  final VoidCallback onDone;
  final VoidCallback onRemove;

  static const List<Duration> presets = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
    Duration(hours: 6),
    Duration(days: 1),
  ];

  @override
  State<_AgeEditor> createState() => _AgeEditorState();
}

class _AgeEditorState extends State<_AgeEditor> {
  late final TextEditingController _text = TextEditingController(
    text: _isPreset(widget.controller.maxAge)
        ? ''
        : formatMaxAge(widget.controller.maxAge!),
  );
  bool _invalid = false;

  static bool _isPreset(Duration? age) =>
      age == null || _AgeEditor.presets.contains(age);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submitCustom(String value) {
    final age = parseMaxAge(value);
    setState(() => _invalid = age == null);
    if (age == null) return;
    widget.controller.setMaxAge(age);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final current = widget.controller.maxAge;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EditorHeader(
              icon: Icons.schedule,
              label: 'Age',
              onRemove: widget.onRemove,
              operator: Text(
                'within last',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in _AgeEditor.presets)
                  _PresetChip(
                    label: formatMaxAge(preset),
                    selected: current == preset,
                    onPressed: () {
                      widget.controller.setMaxAge(preset);
                      widget.onDone();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              autofocus: true,
              contextMenuBuilder: AnchoredPopover.textContextMenuBuilder,
              style: const TextStyle(fontSize: 13),
              decoration: _cardInputDecoration(
                context,
                hintText: 'Custom, e.g. 1h30m, then ↵',
                errorText: _invalid ? 'Use s, m, h or d — e.g. 90s, 2h' : null,
              ),
              onSubmitted: _submitCustom,
            ),
          ],
        );
      },
    );
  }
}

// ── Card building blocks ─────────────────────────────────────────────────────

/// Icon, field name, operator and a delete button — the top line of every
/// pill editor.
class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.icon,
    required this.label,
    required this.operator,
    required this.onRemove,
  });

  final IconData icon;
  final String label;
  final Widget operator;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 4),
        Flexible(child: operator),
        const Spacer(),
        AppIconButton(
          tooltip: 'Delete filter',
          onPressed: onRemove,
          icon: Icons.delete_outline,
          iconSize: 16,
        ),
      ],
    );
  }
}

/// The "contains ▾" control in an editor header.
class _OperatorButton extends StatelessWidget {
  const _OperatorButton({
    required this.label,
    required this.negated,
    required this.open,
    required this.onPressed,
  });

  final String label;
  final bool negated;
  final bool open;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = negated ? colors.error : colors.onSurfaceVariant;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: open ? colors.surfaceContainerHighest : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: color,
                  fontWeight: negated ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (onPressed != null)
              Icon(
                open ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: color,
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuSectionLabel extends StatelessWidget {
  const _MenuSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A rounded, hover-highlighted row in a popover list.
class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.child,
    required this.onTap,
    this.icon,
    this.packageName,
    this.trailing,
    this.highlighted = false,
    this.onHover,
  });

  final Widget child;
  final VoidCallback onTap;
  final IconData? icon;

  /// A package whose cached app icon replaces [icon], which stays the
  /// fallback until the Apps pane has fetched one.
  final String? packageName;
  final Widget? trailing;
  final bool highlighted;
  final VoidCallback? onHover;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovered = false;

  Widget _buildIcon(ColorScheme colors) {
    final glyph = Icon(widget.icon, size: 16, color: colors.onSurfaceVariant);
    final packageName = widget.packageName;
    if (packageName == null) return glyph;
    return PackageIcon(packageName: packageName, size: 16, fallback: glyph);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lit = widget.highlighted || _hovered;
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHover?.call();
      },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: lit ? colors.onSurface.withValues(alpha: 0.07) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                _buildIcon(colors),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: DefaultTextStyle.merge(
                  style: TextStyle(fontSize: 13, color: colors.onSurface),
                  child: widget.child,
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _EnterHint extends StatelessWidget {
  const _EnterHint();

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.keyboard_return,
      size: 14,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colors.primary.withValues(alpha: 0.16)
          : colors.surfaceContainerHigh,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? colors.primary.withValues(alpha: 0.6)
              : colors.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? colors.primary : colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded, filled text field for popover cards.
InputDecoration _cardInputDecoration(
  BuildContext context, {
  String? hintText,
  String? errorText,
  IconData? prefixIcon,
}) {
  final colors = Theme.of(context).colorScheme;
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(kFilterControlRadius),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: colors.surfaceContainerHigh,
    hintText: hintText,
    hintStyle: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
    errorText: errorText,
    errorStyle: const TextStyle(fontSize: 11),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    prefixIcon: prefixIcon == null
        ? null
        : Icon(prefixIcon, size: 16, color: colors.onSurfaceVariant),
    prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 20),
    border: border(colors.outlineVariant.withValues(alpha: 0.6)),
    enabledBorder: border(colors.outlineVariant.withValues(alpha: 0.6)),
    focusedBorder: border(colors.primary, 1.5),
    errorBorder: border(colors.error),
    focusedErrorBorder: border(colors.error, 1.5),
  );
}
