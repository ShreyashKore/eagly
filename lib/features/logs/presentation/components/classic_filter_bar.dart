import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../presentation/components/anchored_popover.dart';
import '../../../../presentation/theme/log_level_presentation.dart';
import '../../data/models/filter_condition.dart';
import '../../data/models/log_filters.dart';
import '../../data/models/log_level.dart';
import 'filter_bar_shared.dart';
import 'log_filter_controller.dart';

export 'filter_bar_shared.dart' show filterInputDecoration, kFilterFieldHeight;
export 'log_filter_controller.dart'
    show ClassicFilterController, LogFilterSuggestions;

/// The classic filter bar's controls, Notion style: a **Filter** button whose
/// menu adds filters (type to get "Message contains …" and friends) and a
/// **Level** button. The filters it adds show in [ClassicFilterPills], which
/// the host lays out on its own row underneath. Fully driven by a
/// [ClassicFilterController]; it owns no filter state.
class ClassicFilterBar extends StatelessWidget {
  const ClassicFilterBar({super.key, required this.controller});

  final ClassicFilterController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilterMenuButton(controller: controller),
          const SizedBox(width: 6),
          _LevelButton(controller: controller),
        ],
      ),
    );
  }
}

/// The classic bar's active filters as rounded pills, plus "Clear filters".
/// Builds nothing while there are none.
class ClassicFilterPills extends StatelessWidget {
  const ClassicFilterPills({super.key, required this.controller});

  final ClassicFilterController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _buildPills(context),
    );
  }

  Widget _buildPills(BuildContext context) {
    if (!controller.hasPills) return const SizedBox(width: double.infinity);
    final isIos = controller.isIos;
    final maxAge = controller.maxAge;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (controller.showsAgePill)
          _FilterPill(
            key: const ValueKey('age-pill'),
            icon: Icons.schedule,
            fieldLabel: 'Age',
            operatorLabel: 'within last',
            value: maxAge == null ? '' : formatMaxAge(maxAge),
            openOnMount: controller.takePendingEditor(
              ClassicFilterController.ageConditionId,
            ),
            onRemove: () {
              controller.setMaxAge(null);
              controller.commitCondition(
                ClassicFilterController.ageConditionId,
              );
            },
            onEditorClosed: () => controller.commitCondition(
              ClassicFilterController.ageConditionId,
            ),
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
            icon: _fieldIcon(condition.field),
            fieldLabel: condition.field.label(isIos: isIos),
            operatorLabel: condition.operator.label,
            value: condition.value.trim(),
            negated: condition.operator.negate,
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
        _ClearButton(onPressed: controller.clearConditions),
      ],
    );
  }
}

IconData _fieldIcon(FilterConditionField field) => switch (field) {
  FilterConditionField.packageName => Icons.apps_outlined,
  FilterConditionField.tag => Icons.sell_outlined,
  FilterConditionField.pidTid => Icons.numbers,
  FilterConditionField.message => Icons.notes_rounded,
  FilterConditionField.anyField => Icons.manage_search,
};

// ── Filter button + "Filter by…" menu ────────────────────────────────────────

/// The fields in the order the menu offers them — most-used first, so a bare
/// ↵ after typing filters the message.
const List<FilterConditionField> _menuFieldOrder = [
  FilterConditionField.message,
  FilterConditionField.packageName,
  FilterConditionField.tag,
  FilterConditionField.pidTid,
  FilterConditionField.anyField,
];

class _FilterMenuButton extends StatefulWidget {
  const _FilterMenuButton({required this.controller});

  final ClassicFilterController controller;

  @override
  State<_FilterMenuButton> createState() => _FilterMenuButtonState();
}

class _FilterMenuButtonState extends State<_FilterMenuButton> {
  final PopoverController _popover = PopoverController();

  @override
  void initState() {
    super.initState();
    widget.controller.filterMenuRequests.addListener(_popover.open);
  }

  @override
  void dispose() {
    widget.controller.filterMenuRequests.removeListener(_popover.open);
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.controller.activeFilterCount;
    final colors = Theme.of(context).colorScheme;
    return AnchoredPopover(
      controller: _popover,
      width: 300,
      popoverBuilder: (context) =>
          _FilterByMenu(controller: widget.controller, onDone: _popover.close),
      child: FilterControlButton(
        focusNode: widget.controller.filterButtonFocusNode,
        icon: Icons.filter_list_rounded,
        label: const Text('Filter'),
        active: count > 0,
        tooltip: 'Hide lines that don’t match (⌘L)',
        trailing: count == 0
            ? null
            : Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onPrimary,
                  ),
                ),
              ),
        onPressed: _popover.toggle,
      ),
    );
  }
}

/// One selectable row in the "Filter by…" menu.
class _MenuOption {
  const _MenuOption({
    required this.icon,
    required this.label,
    required this.onSelected,
  });

  final IconData icon;
  final InlineSpan label;
  final VoidCallback onSelected;
}

/// The Filter button's menu: a "Filter by…" field over a list of fields. With
/// text typed, each field becomes a ready "Field contains ‘text’" filter, and
/// matching recent / known values are offered under it. ↑↓ and ↵ work.
class _FilterByMenu extends StatefulWidget {
  const _FilterByMenu({required this.controller, required this.onDone});

  final ClassicFilterController controller;
  final VoidCallback onDone;

  @override
  State<_FilterByMenu> createState() => _FilterByMenuState();
}

class _FilterByMenuState extends State<_FilterByMenu> {
  final TextEditingController _query = TextEditingController();
  int _highlighted = 0;

  ClassicFilterController get _controller => widget.controller;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _select(_MenuOption option) {
    widget.onDone();
    option.onSelected();
  }

  /// The menu as sections of options; the flattened order is keyboard order.
  List<(String, List<_MenuOption>)> _sections(BuildContext context) {
    final isIos = _controller.isIos;
    final query = _query.text.trim();
    final colors = Theme.of(context).colorScheme;
    final valueStyle = TextStyle(
      fontWeight: FontWeight.w600,
      color: colors.onSurface,
    );
    final mutedStyle = TextStyle(color: colors.onSurfaceVariant);

    if (query.isEmpty) {
      return [
        (
          'Filter by',
          [
            for (final field in _menuFieldOrder)
              _MenuOption(
                icon: _fieldIcon(field),
                label: TextSpan(text: field.label(isIos: isIos)),
                onSelected: () => _controller.addCondition(field),
              ),
            if (!_controller.showsAgePill)
              _MenuOption(
                icon: Icons.schedule,
                label: const TextSpan(text: 'Age'),
                onSelected: _controller.addAgeCondition,
              ),
          ],
        ),
      ];
    }

    InlineSpan contains(String field, String value) => TextSpan(
      children: [
        TextSpan(text: field),
        TextSpan(text: ' contains ', style: mutedStyle),
        TextSpan(text: value, style: valueStyle),
      ],
    );

    final age = parseMaxAge(query);
    final suggestions = <_MenuOption>[];
    void suggest(FilterConditionField field, Iterable<String> values) {
      final q = query.toLowerCase();
      for (final value in deduplicateFilterValues(values)) {
        final normalized = value.toLowerCase();
        if (normalized == q || !normalized.contains(q)) continue;
        suggestions.add(
          _MenuOption(
            icon: _fieldIcon(field),
            label: contains(field.label(isIos: isIos), value),
            onSelected: () => _controller.addConditionWithValue(field, value),
          ),
        );
      }
    }

    final sources = _controller.suggestions;
    suggest(FilterConditionField.packageName, [
      ...sources.recentPackageFilters(),
      ...sources.knownPackageFilters(),
    ]);
    suggest(FilterConditionField.tag, sources.recentTagFilters());
    suggest(FilterConditionField.message, sources.recentMessageFilters());

    return [
      (
        'Add filter',
        [
          for (final field in _menuFieldOrder)
            _MenuOption(
              icon: _fieldIcon(field),
              label: contains(field.label(isIos: isIos), query),
              onSelected: () => _controller.addConditionWithValue(field, query),
            ),
          if (age != null && !_controller.showsAgePill)
            _MenuOption(
              icon: Icons.schedule,
              label: TextSpan(
                children: [
                  const TextSpan(text: 'Age'),
                  TextSpan(text: ' within last ', style: mutedStyle),
                  TextSpan(text: formatMaxAge(age), style: valueStyle),
                ],
              ),
              onSelected: () => _controller.setMaxAge(age),
            ),
        ],
      ),
      if (suggestions.isNotEmpty) ('Suggestions', suggestions.take(6).toList()),
    ];
  }

  /// Keyboard order: every section's options, flattened.
  List<_MenuOption> _options(BuildContext context) => [
    for (final (_, items) in _sections(context)) ...items,
  ];

  KeyEventResult _onKey(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Built from the live query, not the last frame's list: a fast
    // type-then-↵ lands before the rebuild.
    final options = _options(context);
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (options.isEmpty) return KeyEventResult.handled;
      final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() => _highlighted = (_highlighted + step) % options.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (options.isNotEmpty) {
        _select(options[_highlighted.clamp(0, options.length - 1)]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections(context);
    final options = [for (final (_, items) in sections) ...items];
    final highlighted = options.isEmpty
        ? -1
        : _highlighted.clamp(0, options.length - 1);
    var index = 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Focus(
            onKeyEvent: (node, event) => _onKey(context, event),
            skipTraversal: true,
            child: TextField(
              controller: _query,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: _cardInputDecoration(
                context,
                hintText: 'Filter by… (try a package or tag)',
                prefixIcon: Icons.search,
              ),
              onChanged: (_) => setState(() => _highlighted = 0),
            ),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            children: [
              for (final (title, items) in sections) ...[
                _MenuSectionLabel(title),
                for (final option in items)
                  Builder(
                    builder: (context) {
                      final i = index++;
                      return _MenuRow(
                        icon: option.icon,
                        highlighted: i == highlighted,
                        trailing: i == highlighted ? const _EnterHint() : null,
                        onHover: () => setState(() => _highlighted = i),
                        onTap: () => _select(option),
                        child: Text.rich(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Level button ─────────────────────────────────────────────────────────────

class _LevelButton extends StatefulWidget {
  const _LevelButton({required this.controller});

  final ClassicFilterController controller;

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

/// One active filter as a rounded pill ("Tag is not Chatty"); clicking it
/// opens [editorBuilder] in a popover underneath.
class _FilterPill extends StatefulWidget {
  const _FilterPill({
    super.key,
    required this.icon,
    required this.fieldLabel,
    required this.operatorLabel,
    required this.value,
    required this.onRemove,
    required this.onEditorClosed,
    required this.editorBuilder,
    this.negated = false,
    this.error,
    this.openOnMount = false,
  });

  final IconData icon;
  final String fieldLabel;
  final String operatorLabel;

  /// Blank while the pill is a draft.
  final String value;
  final bool negated;

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
    final error = widget.error;
    final isDraft = widget.value.isEmpty;
    final accent = error != null ? colors.error : colors.primary;

    final pill = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: accent.withValues(alpha: _hovered || isOpen ? 0.16 : 0.10),
        shape: StadiumBorder(
          side: BorderSide(
            color: accent.withValues(alpha: isOpen ? 0.9 : 0.35),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _popover.toggle,
          child: SizedBox(
            height: kFilterControlHeight,
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 14, color: accent),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: widget.fieldLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                          TextSpan(
                            text: ' ${widget.operatorLabel} ',
                            style: TextStyle(
                              color: widget.negated
                                  ? colors.error
                                  : colors.onSurfaceVariant,
                              fontWeight: widget.negated
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          TextSpan(
                            text: isDraft ? '…' : widget.value,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isDraft
                                  ? colors.onSurfaceVariant
                                  : colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: _hovered
                        ? IconButton(
                            tooltip: 'Remove filter',
                            onPressed: widget.onRemove,
                            icon: const Icon(Icons.close, size: 14),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          )
                        : Icon(
                            Icons.expand_more,
                            size: 16,
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

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: kFilterControlHeight,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: colors.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: const StadiumBorder(),
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontSize: 12.5),
        ),
        child: const Text('Clear filters'),
      ),
    );
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

  final ClassicFilterController controller;
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

  List<String> _suggestions(FilterConditionField field) {
    final sources = widget.controller.suggestions;
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
    final query = _text.text.trim().toLowerCase();
    if (query.isEmpty) return values.take(6).toList();
    final preferred = <String>[];
    final secondary = <String>[];
    for (final value in values) {
      final normalized = value.toLowerCase();
      if (normalized == query || !normalized.contains(query)) continue;
      (filterBoundaryMatch(normalized, query) ? preferred : secondary).add(
        value,
      );
    }
    return [...preferred, ...secondary].take(6).toList();
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
        : _suggestions(field);

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

  final ClassicFilterController controller;
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
        IconButton(
          tooltip: 'Delete filter',
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline, size: 16),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          padding: EdgeInsets.zero,
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
    this.trailing,
    this.highlighted = false,
    this.onHover,
  });

  final Widget child;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? trailing;
  final bool highlighted;
  final VoidCallback? onHover;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovered = false;

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
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: lit ? colors.onSurface.withValues(alpha: 0.07) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: DefaultTextStyle.merge(
                  style: TextStyle(fontSize: 12.5, color: colors.onSurface),
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
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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
