import 'package:flutter/material.dart';

import '../../data/models/log_column.dart';

/// Multi-select column list shown inside the column-visibility popup.
///
/// Owns a working copy of the hidden-column set so toggling a row updates the
/// popup in place — the menu stays open until the user dismisses it, letting
/// several columns be shown/hidden in one go.
class ColumnVisibilityMenu extends StatefulWidget {
  const ColumnVisibilityMenu({
    super.key,
    required this.columns,
    required this.hiddenColumns,
    required this.isIos,
    required this.onChanged,
  });

  /// Columns offered for toggling, in display order.
  final List<LogColumn> columns;

  /// Initially hidden column names.
  final Set<String> hiddenColumns;

  final bool isIos;

  /// Called with the full hidden-column set on every toggle.
  final ValueChanged<Set<String>> onChanged;

  @override
  State<ColumnVisibilityMenu> createState() => _ColumnVisibilityMenuState();
}

class _ColumnVisibilityMenuState extends State<ColumnVisibilityMenu> {
  late final Set<String> _hidden = Set.of(widget.hiddenColumns);

  void _toggle(LogColumn column) {
    setState(() {
      if (!_hidden.remove(column.name)) _hidden.add(column.name);
    });
    widget.onChanged(Set.of(_hidden));
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontSize: 12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final column in widget.columns)
          InkWell(
            onTap: () => _toggle(column),
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  IgnorePointer(
                    child: Checkbox(
                      visualDensity: VisualDensity.compact,
                      value: !_hidden.contains(column.name),
                      onChanged: (_) {},
                    ),
                  ),
                  Text(column.labelFor(isIos: widget.isIos), style: labelStyle),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
