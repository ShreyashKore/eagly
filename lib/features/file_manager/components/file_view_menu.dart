import 'package:flutter/material.dart';

import '../data/file_view_options.dart';
import '../file_manager_controller.dart';

/// The sort / group / show menu — what Finder's "View" menu holds. The list
/// view's column headers sort too; this is the way to do it in the grid, and
/// the only way to sort by Kind or group.
class const FileViewMenuButton({
  super.key,
  required final FileManagerController controller,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grouped = controller.grouping != FileGrouping.none;
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Sort and group',
      iconSize: 18,
      position: PopupMenuPosition.under,
      icon: Icon(
        grouped ? Icons.view_agenda_outlined : Icons.sort,
        color: grouped ? theme.colorScheme.primary : null,
      ),
      onSelected: (apply) => apply(),
      itemBuilder: (context) => [
        const _MenuHeading('Sort by'),
        for (final field in FileSortField.values)
          _check(
            field.label,
            checked: controller.sortField == field,
            onSelected: () => controller.setSort(
              field,
              ascending: controller.sortField == field
                  ? controller.sortAscending
                  : field.defaultAscending,
            ),
          ),
        const PopupMenuDivider(),
        for (final ascending in const [true, false])
          _check(
            _orderLabel(controller.sortField, ascending: ascending),
            checked: controller.sortAscending == ascending,
            onSelected: () =>
                controller.setSort(controller.sortField, ascending: ascending),
          ),
        const PopupMenuDivider(),
        const _MenuHeading('Group by'),
        for (final grouping in FileGrouping.values)
          _check(
            grouping.label,
            checked: controller.grouping == grouping,
            onSelected: () => controller.setGrouping(grouping),
          ),
        const PopupMenuDivider(),
        _check(
          'Folders first',
          checked: controller.foldersFirst,
          // Grouped by kind, folders are a group of their own anyway.
          enabled: controller.grouping != FileGrouping.kind,
          onSelected: () =>
              controller.setFoldersFirst(!controller.foldersFirst),
        ),
        _check(
          'Show hidden files',
          checked: controller.showHidden,
          onSelected: () => controller.setShowHidden(!controller.showHidden),
        ),
      ],
    );
  }

  /// What each direction means for [field], in the words Finder uses.
  static String _orderLabel(FileSortField field, {required bool ascending}) =>
      switch (field) {
        FileSortField.name ||
        FileSortField.kind => ascending ? 'A to Z' : 'Z to A',
        FileSortField.size => ascending ? 'Smallest first' : 'Largest first',
        FileSortField.modified => ascending ? 'Oldest first' : 'Newest first',
      };

  static CheckedPopupMenuItem<VoidCallback> _check(
    String label, {
    required bool checked,
    required VoidCallback onSelected,
    bool enabled = true,
  }) => CheckedPopupMenuItem(
    value: onSelected,
    checked: checked,
    enabled: enabled,
    height: 36,
    child: Text(label),
  );
}

class const _MenuHeading(final String label)
    extends PopupMenuEntry<VoidCallback> {
  @override
  double get height => 28;

  @override
  bool represents(VoidCallback? value) => false;

  @override
  State<_MenuHeading> createState() => _MenuHeadingState();
}

class _MenuHeadingState extends State<_MenuHeading> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: widget.height,
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Text(
        widget.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
