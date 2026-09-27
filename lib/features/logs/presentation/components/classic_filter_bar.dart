import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/filter_condition.dart';
import '../../data/models/log_filters.dart';
import 'filter_bar_shared.dart';
import 'log_filter_controller.dart';

export 'filter_bar_shared.dart' show filterInputDecoration, kFilterFieldHeight;
export 'log_filter_controller.dart'
    show ClassicFilterController, LogFilterSuggestions;

/// The classic filter bar: a level dropdown, a quick message field and an
/// "Add filter" menu on top, with the active filter pills wrapping underneath.
/// Clicking a pill opens its editor (operator + value). Fully driven by a
/// [ClassicFilterController]; it owns no filter state.
class ClassicFilterBar extends StatelessWidget {
  const ClassicFilterBar({super.key, required this.controller});

  final ClassicFilterController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopRow(context),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topLeft,
            child: _hasPills
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _buildPills(context),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  bool get _hasPills =>
      controller.conditions.isNotEmpty || controller.showsAgePill;

  Widget _buildTopRow(BuildContext context) {
    final isIos = controller.isIos;
    return Row(
      spacing: 8,
      children: [
        SizedBox(
          width: 150,
          child: LogLevelDropdown(
            selectedLogLevel: controller.selectedLevel,
            onLogLevelChanged: (level) {
              if (level != null) controller.setLevel(level);
            },
            isIos: isIos,
          ),
        ),
        Expanded(
          child: _RecentFilterField(
            controller: controller.messageController,
            focusNode: controller.messageFocusNode,
            onSuggestionSelected: controller.selectMessageSuggestion,
            onSubmitted: (_) => controller.applyNow(),
            recentValues: controller.suggestions.recentMessageFilters(),
            labelText: 'Message',
            hintText: 'Filter message text…',
            prefixIcon: Icons.message_outlined,
          ),
        ),
        _AddFilterMenu(
          controller: controller,
          builder: (context, onPressed) {
            final count = controller.activeFilterCount;
            return SizedBox(
              height: kFilterFieldHeight,
              child: TextButton.icon(
                onPressed: onPressed,
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  textStyle: _buttonTextStyle(context),
                ),
                icon: const Icon(Icons.filter_list_rounded, size: 16),
                label: Text(count == 0 ? 'Filter' : 'Filter · $count'),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPills(BuildContext context) {
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
        _AddFilterMenu(
          controller: controller,
          builder: (context, onPressed) => _PillButton(
            icon: Icons.add,
            label: 'Add filter',
            onPressed: onPressed,
          ),
        ),
        _PillButton(
          icon: Icons.clear_all,
          label: 'Clear',
          onPressed: controller.clearConditions,
        ),
      ],
    );
  }
}

/// The theme's button label at the bar's 12px size. A button's `textStyle`
/// replaces the theme's rather than merging with it, so a bare `TextStyle`
/// would drop the app font.
TextStyle? _buttonTextStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12);

IconData _fieldIcon(FilterConditionField field) => switch (field) {
  FilterConditionField.packageName => Icons.apps_outlined,
  FilterConditionField.tag => Icons.sell_outlined,
  FilterConditionField.pidTid => Icons.numbers,
  FilterConditionField.message => Icons.message_outlined,
  FilterConditionField.anyField => Icons.manage_search,
};

// ── Add-filter menu ──────────────────────────────────────────────────────────

/// A menu of the fields a pill can filter on; picking one adds an empty pill
/// and opens its editor. [builder] draws the button that opens it.
class _AddFilterMenu extends StatelessWidget {
  const _AddFilterMenu({required this.controller, required this.builder});

  final ClassicFilterController controller;
  final Widget Function(BuildContext context, VoidCallback onPressed) builder;

  @override
  Widget build(BuildContext context) {
    final isIos = controller.isIos;
    return MenuAnchor(
      menuChildren: [
        for (final field in FilterConditionField.values)
          MenuItemButton(
            leadingIcon: Icon(_fieldIcon(field), size: 16),
            onPressed: () => controller.addCondition(field),
            child: Text(field.label(isIos: isIos)),
          ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.schedule, size: 16),
          // One age limit at most; edit the existing pill instead.
          onPressed: controller.showsAgePill
              ? null
              : controller.addAgeCondition,
          child: const Text('Age'),
        ),
      ],
      builder: (context, menu, _) =>
          builder(context, () => menu.isOpen ? menu.close() : menu.open()),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kPillHeight,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: _buttonTextStyle(context),
          visualDensity: VisualDensity.compact,
        ),
        icon: Icon(icon, size: 14),
        label: Text(label),
      ),
    );
  }
}

// ── Pill ─────────────────────────────────────────────────────────────────────

const double _kPillHeight = 28;
const double _kEditorWidth = 320;

/// One filter as a pill ("Tag is not Chatty ×") that opens [editorBuilder] in
/// a popover below it when clicked. The popover closes on Escape or a click
/// outside it, then reports [onEditorClosed].
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
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  /// Taps on the pill and on its popover are one region, so clicking the pill
  /// while the popover is open toggles it rather than counting as "outside".
  final Object _tapGroup = Object();

  /// Anchors the popover to the pill's right edge when it would otherwise run
  /// off the right side of the window.
  bool _alignRight = false;

  @override
  void initState() {
    super.initState();
    if (widget.openOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open();
      });
    }
  }

  void _open() {
    if (_portal.isShowing) return;
    final box = context.findRenderObject() as RenderBox?;
    final windowWidth = MediaQuery.sizeOf(context).width;
    final left = box?.localToGlobal(Offset.zero).dx ?? 0;
    setState(() {
      _alignRight = left + _kEditorWidth > windowWidth - 8;
      _portal.show();
    });
  }

  void _close() {
    if (!_portal.isShowing) return;
    setState(_portal.hide);
    widget.onEditorClosed();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: TapRegion(
        groupId: _tapGroup,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: _buildPopover,
          child: _buildPill(context),
        ),
      ),
    );
  }

  Widget _buildPopover(BuildContext context) {
    final anchor = _alignRight ? Alignment.topRight : Alignment.topLeft;
    return Positioned(
      width: _kEditorWidth,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: _alignRight
            ? Alignment.bottomRight
            : Alignment.bottomLeft,
        followerAnchor: anchor,
        offset: const Offset(0, 4),
        child: TapRegion(
          groupId: _tapGroup,
          onTapOutside: (_) => _close(),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _close,
            },
            child: FocusScope(
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: widget.editorBuilder(context, _close),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPill(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOpen = _portal.isShowing;
    final error = widget.error;
    final borderColor = isOpen
        ? colorScheme.primary
        : error != null
        ? colorScheme.error
        : Colors.transparent;
    final isDraft = widget.value.isEmpty;

    final pill = Material(
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isOpen ? _close : _open,
        child: SizedBox(
          height: _kPillHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: widget.fieldLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: ' ${widget.operatorLabel} ',
                          style: TextStyle(
                            color: widget.negated
                                ? colorScheme.error
                                : colorScheme.onSurfaceVariant,
                            fontWeight: widget.negated
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        TextSpan(
                          text: isDraft ? '…' : widget.value,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isDraft
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove filter',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close, size: 14),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return error == null ? pill : Tooltip(message: error, child: pill);
  }
}

// ── Editors ──────────────────────────────────────────────────────────────────

/// The header every pill editor shares: the field's name and a delete button.
class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.icon,
    required this.label,
    required this.onRemove,
  });

  final IconData icon;
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
          ),
        ),
        IconButton(
          tooltip: 'Delete filter',
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline, size: 16),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

ButtonStyle _segmentStyle(BuildContext context) => SegmentedButton.styleFrom(
  visualDensity: VisualDensity.compact,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textStyle: _buttonTextStyle(context),
);

/// Edits one [FilterCondition]: how it matches (contains / is / regex),
/// whether it keeps or hides what matches, and the value — with recent and
/// known values for that field offered underneath.
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

  FilterCondition? get _condition => widget.controller.conditions
      .where((condition) => condition.id == widget.conditionId)
      .firstOrNull;

  @override
  void dispose() {
    _text.dispose();
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
    if (query.isEmpty) return values.take(8).toList();
    final preferred = <String>[];
    final secondary = <String>[];
    for (final value in values) {
      final normalized = value.toLowerCase();
      if (normalized == query || !normalized.contains(query)) continue;
      (filterBoundaryMatch(normalized, query) ? preferred : secondary).add(
        value,
      );
    }
    return [...preferred, ...secondary].take(8).toList();
  }

  void _setOperator(
    FilterCondition condition,
    FilterMatchMode mode,
    bool negate,
  ) {
    widget.controller.updateCondition(
      condition.id,
      operator: FilterOperator.of(mode, negate: negate),
    );
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
    final hasOperators = field.operators.length > 1;
    final suggestions = _suggestions(field);
    final invalidRegex = condition.toTerm()?.hasInvalidRegex ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditorHeader(
          icon: _fieldIcon(field),
          label: field.label(isIos: widget.controller.isIos),
          onRemove: widget.onRemove,
        ),
        const SizedBox(height: 8),
        if (hasOperators) ...[
          SegmentedButton<FilterMatchMode>(
            style: _segmentStyle(context),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: FilterMatchMode.contains,
                label: Text('Contains'),
              ),
              ButtonSegment(value: FilterMatchMode.exact, label: Text('Is')),
              ButtonSegment(value: FilterMatchMode.regex, label: Text('Regex')),
            ],
            selected: {operator.mode},
            onSelectionChanged: (selection) =>
                _setOperator(condition, selection.single, operator.negate),
          ),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            style: _segmentStyle(context),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.visibility_outlined, size: 14),
                label: Text('Show matches'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.visibility_off_outlined, size: 14),
                label: Text('Hide matches'),
              ),
            ],
            selected: {operator.negate},
            onSelectionChanged: (selection) =>
                _setOperator(condition, operator.mode, selection.single),
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _text,
          autofocus: true,
          style: const TextStyle(fontSize: 12),
          decoration:
              filterInputDecoration(
                context,
                hintText: switch (operator.mode) {
                  FilterMatchMode.contains => 'Text to look for…',
                  FilterMatchMode.exact => 'Whole value…',
                  FilterMatchMode.regex => 'Regular expression…',
                },
              ).copyWith(
                errorText: invalidRegex ? 'Invalid regular expression' : null,
                errorStyle: const TextStyle(fontSize: 11),
              ),
          onChanged: (value) =>
              widget.controller.updateCondition(condition.id, value: value),
          onSubmitted: (_) => widget.onDone(),
        ),
        if (!hasOperators) ...[
          const SizedBox(height: 6),
          Text(
            'Matches text anywhere in the line.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final suggestion in suggestions)
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      _text.text = suggestion;
                      widget.controller.updateCondition(
                        condition.id,
                        value: suggestion,
                      );
                      widget.onDone();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      child: Text(
                        suggestion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
              label: 'Age — only lines from the last…',
              onRemove: widget.onRemove,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in _AgeEditor.presets)
                  ChoiceChip(
                    label: Text(formatMaxAge(preset)),
                    labelStyle: const TextStyle(fontSize: 12),
                    visualDensity: VisualDensity.compact,
                    selected: current == preset,
                    onSelected: (_) {
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
              style: const TextStyle(fontSize: 12),
              decoration:
                  filterInputDecoration(
                    context,
                    hintText: 'Custom, e.g. 1h30m — press Enter',
                  ).copyWith(
                    errorText: _invalid
                        ? 'Use s, m, h, d — e.g. 90s, 2h'
                        : null,
                    errorStyle: const TextStyle(fontSize: 11),
                  ),
              onSubmitted: _submitCustom,
            ),
          ],
        );
      },
    );
  }
}

// ── Quick message field ──────────────────────────────────────────────────────

class _RecentFilterField extends StatelessWidget {
  const _RecentFilterField({
    required this.controller,
    required this.focusNode,
    required this.onSuggestionSelected,
    required this.onSubmitted,
    required this.recentValues,
    required this.labelText,
    required this.hintText,
    required this.prefixIcon,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSuggestionSelected;
  final ValueChanged<String> onSubmitted;
  final List<String> recentValues;
  final String labelText;
  final String hintText;
  final IconData prefixIcon;

  List<String> _matchingOptions(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return recentValues.toList(growable: false);

    final preferredMatches = <String>[];
    final secondaryMatches = <String>[];
    for (final option in recentValues) {
      final normalized = option.toLowerCase();
      if (!normalized.contains(q)) continue;
      final bucket = filterBoundaryMatch(normalized, q)
          ? preferredMatches
          : secondaryMatches;
      bucket.add(option);
    }

    return [...preferredMatches, ...secondaryMatches];
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kFilterFieldHeight,
      child: RawAutocomplete<String>(
        textEditingController: controller,
        focusNode: focusNode,
        optionsBuilder: (textEditingValue) =>
            _matchingOptions(textEditingValue.text),
        onSelected: onSuggestionSelected,
        fieldViewBuilder:
            (context, fieldController, fieldFocusNode, onFieldSubmitted) {
              return TextField(
                controller: fieldController,
                focusNode: fieldFocusNode,
                style: const TextStyle(fontSize: 12),
                decoration: filterInputDecoration(
                  context,
                  labelText: labelText,
                  hintText: hintText,
                  prefixIcon: prefixIcon,
                ),
                onSubmitted: (value) {
                  onSubmitted(value);
                  onFieldSubmitted();
                },
              );
            },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 220,
                  maxWidth: 320,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return InkWell(
                      onTap: () => onSelected(option),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          option,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
