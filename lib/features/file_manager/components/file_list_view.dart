import 'package:flutter/material.dart';

import '../data/device_file_entry.dart';
import '../file_manager_controller.dart';
import 'file_context_menu.dart';
import 'file_entry_visuals.dart';
import '../../../presentation/components/min_width_box.dart';
import '../../../presentation/theme/app_theme.dart';

/// Detailed table view: a sortable header (Name / Size / Modified /
/// Permissions) above one row per entry. Single tap selects, double tap opens
/// a directory, right-click shows the context menu.
///
/// A narrow pane drops the trailing columns, Permissions first, so Name keeps
/// at least [_minNameWidth]; narrower still, the table clips its right edge.
///
/// Names read first: Size and Modified are secondary text, Permissions —
/// rarely what anyone came for — tertiary.
class const FileListView({
  super.key,
  required final FileManagerController controller,
  required final FileManagerActions actions,
}) extends StatelessWidget {
  static const double _sizeWidth = 84;
  static const double _modifiedWidth = 132;
  static const double _permsWidth = 104;
  static const double _minNameWidth = 140;
  static const double _horizontalPadding = 12;

  @override
  Widget build(BuildContext context) {
    final entries = controller.entries;
    return MinWidthBox(
      minWidth: _minNameWidth + 2 * _horizontalPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _FileColumns.fitting(
            constraints.maxWidth - 2 * _horizontalPadding,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, columns),
              Expanded(
                child: ListView.builder(
                  itemCount: entries.length,
                  itemExtent: 40,
                  itemBuilder: (context, index) => _FileRow(
                    controller: controller,
                    entry: entries[index],
                    actions: actions,
                    columns: columns,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, _FileColumns columns) {
    final theme = Theme.of(context);
    return Container(
      height: context.scaled(34),
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: _headerCell(context, 'Name', FileSortField.name)),
          if (columns.size)
            SizedBox(
              width: _sizeWidth,
              child: _headerCell(
                context,
                'Size',
                FileSortField.size,
                alignEnd: true,
              ),
            ),
          if (columns.modified)
            SizedBox(
              width: _modifiedWidth,
              child: _headerCell(context, 'Modified', FileSortField.modified),
            ),
          if (columns.perms)
            SizedBox(
              width: _permsWidth,
              child: _headerCell(context, 'Perms', FileSortField.type),
            ),
        ],
      ),
    );
  }

  Widget _headerCell(
    BuildContext context,
    String label,
    FileSortField field, {
    bool alignEnd = false,
  }) {
    final theme = Theme.of(context);
    final active = controller.sortField == field;
    return InkWell(
      onTap: () => controller.setSort(field),
      child: Row(
        mainAxisAlignment: alignEnd
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: active
                    ? theme.colorScheme.primary
                    : context.eaglyTheme.secondaryTextColor,
              ),
            ),
          ),
          if (active)
            Icon(
              controller.sortAscending
                  ? Icons.arrow_drop_up
                  : Icons.arrow_drop_down,
              size: 18,
              color: theme.colorScheme.primary,
            ),
        ],
      ),
    );
  }
}

class const _FileRow({
  required final FileManagerController controller,
  required final DeviceFileEntry entry,
  required final FileManagerActions actions,
  required final _FileColumns columns,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eaglyTheme = context.eaglyTheme;
    final selected = controller.selectedEntry?.path == entry.path;
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: eaglyTheme.secondaryTextColor,
    );

    return InkWell(
      onTap: () => controller.selectEntry(entry),
      onDoubleTap: entry.isNavigable ? () => controller.open(entry) : null,
      onSecondaryTapUp: (details) {
        controller.selectEntry(entry);
        showFileEntryMenu(
          context,
          details.globalPosition,
          controller: controller,
          entry: entry,
          actions: actions,
        );
      },
      child: Container(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: FileListView._horizontalPadding,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  FileEntryIcon(entry: entry, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: entry.linkTarget == null
                          ? entry.name
                          : '${entry.name} → ${entry.linkTarget}',
                      waitDuration: const Duration(milliseconds: 600),
                      child: Text(
                        entry.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (columns.size)
              SizedBox(
                width: FileListView._sizeWidth,
                child: Text(
                  FileEntryVisuals.formatSize(entry),
                  textAlign: TextAlign.end,
                  style: detailStyle,
                ),
              ),
            if (columns.modified)
              SizedBox(
                width: FileListView._modifiedWidth,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    FileEntryVisuals.formatModified(entry.modified),
                    style: detailStyle,
                  ),
                ),
              ),
            if (columns.perms)
              SizedBox(
                width: FileListView._permsWidth,
                child: Text(
                  entry.permissions ?? entry.typeLabel,
                  style: eaglyTheme.monoStyle.copyWith(
                    fontSize: theme.textTheme.bodySmall?.fontSize,
                    color: eaglyTheme.tertiaryTextColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Which trailing columns fit beside a Name column of at least
/// [FileListView._minNameWidth]. They drop from the right: Permissions, then
/// Modified, then Size.
class const _FileColumns({
  required final bool size,
  required final bool modified,
  required final bool perms,
}) {
  factory _FileColumns.fitting(double width) {
    var used = FileListView._minNameWidth + FileListView._sizeWidth;
    final size = width >= used;
    used += FileListView._modifiedWidth;
    final modified = width >= used;
    used += FileListView._permsWidth;
    final perms = width >= used;
    return _FileColumns(size: size, modified: modified, perms: perms);
  }
}
