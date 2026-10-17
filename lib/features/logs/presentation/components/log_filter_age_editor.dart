import 'package:flutter/material.dart';

import '../../../../presentation/components/anchored_popover.dart';
import '../../data/models/log_filters.dart';
import 'log_filter_controller.dart';
import 'log_filter_parts.dart';

/// Edits the age limit: a preset, or a custom `1h30m`-style duration.
class FilterAgeEditor extends StatefulWidget {
  const FilterAgeEditor({
    super.key,
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
  State<FilterAgeEditor> createState() => _FilterAgeEditorState();
}

class _FilterAgeEditorState extends State<FilterAgeEditor> {
  late final TextEditingController _text = TextEditingController(
    text: _isPreset(widget.controller.maxAge)
        ? ''
        : formatMaxAge(widget.controller.maxAge!),
  );
  bool _invalid = false;

  static bool _isPreset(Duration? age) =>
      age == null || FilterAgeEditor.presets.contains(age);

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
            FilterEditorHeader(
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
                for (final preset in FilterAgeEditor.presets)
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
              decoration: filterCardInputDecoration(
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
