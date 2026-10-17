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
    this.rememberForNewTabs = false,
    this.onRememberForNewTabsChanged,
  });

  /// Columns offered for toggling, in display order.
  final List<LogColumn> columns;

  /// Initially hidden column names.
  final Set<String> hiddenColumns;

  final bool isIos;

  /// Called with the full hidden-column set on every toggle.
  final ValueChanged<Set<String>> onChanged;

  /// Initial state of the trailing "Use for new tabs" row — whether toggles
  /// are saved as the default for new tabs.
  final bool rememberForNewTabs;

  /// Called when that row is toggled. The row is only shown when this is set.
  final ValueChanged<bool>? onRememberForNewTabsChanged;

  @override
  State<ColumnVisibilityMenu> createState() => _ColumnVisibilityMenuState();
}

class _ColumnVisibilityMenuState extends State<ColumnVisibilityMenu> {
  late final Set<String> _hidden = Set.of(widget.hiddenColumns);
  late bool _remember = widget.rememberForNewTabs;

  void _toggle(LogColumn column) {
    setState(() {
      if (!_hidden.remove(column.name)) _hidden.add(column.name);
    });
    widget.onChanged(Set.of(_hidden));
  }

  void _toggleRemember() {
    setState(() => _remember = !_remember);
    widget.onRememberForNewTabsChanged?.call(_remember);
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontSize: 12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final column in widget.columns)
          _CheckRow(
            label: column.labelFor(isIos: widget.isIos),
            value: !_hidden.contains(column.name),
            style: labelStyle,
            onTap: () => _toggle(column),
          ),
        if (widget.onRememberForNewTabsChanged != null) ...[
          const Divider(height: 1),
          Tooltip(
            message: 'Open new tabs with the columns shown here',
            waitDuration: const Duration(milliseconds: 600),
            child: _CheckRow(
              label: 'Use for new tabs',
              value: _remember,
              style: labelStyle,
              onTap: _toggleRemember,
            ),
          ),
        ],
      ],
    );
  }
}

/// One tappable checkbox row; the row, not the checkbox, handles the tap.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.value,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool value;
  final TextStyle? style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(
          children: [
            IgnorePointer(
              child: Checkbox(
                visualDensity: VisualDensity.compact,
                value: value,
                onChanged: (_) {},
              ),
            ),
            Flexible(child: Text(label, style: style)),
          ],
        ),
      ),
    );
  }
}
