import 'package:flutter/material.dart';

import '../../../../presentation/components/anchored_popover.dart';
import '../../../../presentation/theme/app_theme.dart';
import '../../data/models/log_filters.dart';
import 'filter_bar_shared.dart';
import 'log_filter_age_editor.dart';
import 'log_filter_condition_editor.dart';
import 'log_filter_controller.dart';

/// The active filters as pills — the age limit first, then one per condition.
List<Widget> buildFilterPills(
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
        editorBuilder: (context, close) => FilterAgeEditor(
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
        editorBuilder: (context, close) => FilterConditionEditor(
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
    // The field name is a caption over the value the user typed.
    final labelStyle = TextStyle(
      fontSize: 10,
      height: 1.2,
      letterSpacing: 0.1,
      color: context.eaglyTheme.secondaryTextColor,
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
            height: context.filterPillHeight,
            child: Padding(
              padding: const EdgeInsets.only(left: 9, right: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Shrinks, ellipsizing, when the field is narrower than
                  // the pill.
                  Flexible(
                    child: Semantics(
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
                                    ? context.eaglyTheme.tertiaryTextColor
                                    : colors.onSurface,
                              ),
                            ),
                          ],
                        ),
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
