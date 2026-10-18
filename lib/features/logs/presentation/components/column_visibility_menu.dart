import 'package:flutter/material.dart';

import '../../data/models/log_column.dart';

/// Multi-select column list shown inside the column-visibility popup.
///
/// Owns a working copy of the hidden-column set so toggling a row updates the
/// popup in place — the menu stays open until the user dismisses it, letting
/// several columns be shown/hidden in one go.
class const ColumnVisibilityMenu({
  super.key,

  /// Columns offered for toggling, in display order.
  required final List<LogColumn> columns,

  /// Initially hidden column names.
  required final Set<String> hiddenColumns,
  required final bool isIos,

  /// Called with the full hidden-column set on every toggle.
  required final ValueChanged<Set<String>> onChanged,

  /// Initial state of the trailing "Use for new tabs" row — whether toggles
  /// are saved as the default for new tabs.
  final bool rememberForNewTabs = false,

  /// Called when that row is toggled. The row is only shown when this is set.
  final ValueChanged<bool>? onRememberForNewTabsChanged,
}) extends StatefulWidget {
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
class const _CheckRow({
  required final String label,
  required final bool value,
  required final TextStyle? style,
  required final VoidCallback onTap,
}) extends StatelessWidget {
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
