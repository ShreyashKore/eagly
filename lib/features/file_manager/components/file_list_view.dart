import 'package:flutter/material.dart';

import '../data/device_file_entry.dart';
import '../data/file_view_options.dart';
import '../file_manager_controller.dart';
import 'file_browser_keys.dart';
import 'file_context_menu.dart';
import 'file_entry_visuals.dart';
import 'file_group_header.dart';
import '../../../presentation/components/min_width_box.dart';
import '../../../presentation/theme/app_theme.dart';

/// Detailed table view: a sortable header (Name / Size / Modified) and a
/// Perms column above one row per entry, in labelled, foldable sections when
/// grouped. Single tap selects, double tap opens a directory, right-click
/// shows the context menu; [FileBrowserKeys] adds the keyboard.
///
/// A narrow pane drops the trailing columns, Permissions first, so Name keeps
/// at least [_minNameWidth]; narrower still, the table clips its right edge.
/// Header and rows lay their columns out with the same [_column], so labels
/// and values line up and every pair of columns is [_columnGap] apart.
///
/// Names read first: Size and Modified are secondary text, Permissions —
/// rarely what anyone came for — tertiary.
class const FileListView({
  super.key,
  required final FileManagerController controller,
  required final FileManagerActions actions,
  final FocusNode? focusNode,
}) extends StatefulWidget {
  static const double _sizeWidth = 72;
  static const double _modifiedWidth = 132;
  static const double _permsWidth = 88;
  static const double _columnGap = 16;
  static const double _minNameWidth = 140;
  static const double _horizontalPadding = 12;
  static const double _rowExtent = 40;

  /// Inset of every cell's content, header and rows alike: room for a header
  /// cell's hover highlight, kept in the rows so values stay under labels.
  static const EdgeInsets _cellPadding = EdgeInsets.symmetric(horizontal: 4);

  /// A trailing column: [_columnGap] from its neighbour, then [width].
  static Widget _column(double width, Widget child) => Padding(
    padding: const EdgeInsets.only(left: _columnGap),
    child: SizedBox(width: width, child: child),
  );

  @override
  State<FileListView> createState() => _FileListViewState();
}

class _FileListViewState extends State<FileListView> {
  final GlobalKey _selectedRowKey = GlobalKey();

  FileManagerController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final groups = controller.groups;
    final selectedPath = controller.selectedEntry?.path;
    return MinWidthBox(
      minWidth:
          FileListView._minNameWidth + 2 * FileListView._horizontalPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _FileColumns.fitting(
            constraints.maxWidth - 2 * FileListView._horizontalPadding,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, columns),
              Expanded(
                child: FileBrowserKeys(
                  controller: controller,
                  actions: widget.actions,
                  focusNode: widget.focusNode,
                  revealKey: _selectedRowKey,
                  // Ink (row hover) paints on the nearest Material, which
                  // would otherwise sit under the pane's background.
                  child: Material(
                    type: MaterialType.transparency,
                    child: CustomScrollView(
                      slivers: [
                        for (final group in groups) ...[
                          if (group.label.isNotEmpty)
                            SliverToBoxAdapter(
                              child: FileGroupHeader(
                                controller: controller,
                                group: group,
                              ),
                            ),
                          if (!controller.isGroupCollapsed(group))
                            SliverFixedExtentList(
                              itemExtent: FileListView._rowExtent,
                              delegate: SliverChildBuilderDelegate(
                                childCount: group.entries.length,
                                (context, index) {
                                  final entry = group.entries[index];
                                  return _FileRow(
                                    key: entry.path == selectedPath
                                        ? _selectedRowKey
                                        : null,
                                    controller: controller,
                                    entry: entry,
                                    actions: widget.actions,
                                    columns: columns,
                                  );
                                },
                              ),
                            ),
                        ],
                      ],
                    ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: FileListView._horizontalPadding,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      // The header cells' hover ink paints on this, above the bar's colour.
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _SortHeaderCell(
                controller: controller,
                label: 'Name',
                field: FileSortField.name,
              ),
            ),
            if (columns.size)
              FileListView._column(
                FileListView._sizeWidth,
                _SortHeaderCell(
                  controller: controller,
                  label: 'Size',
                  field: FileSortField.size,
                  alignEnd: true,
                ),
              ),
            if (columns.modified)
              FileListView._column(
                FileListView._modifiedWidth,
                _SortHeaderCell(
                  controller: controller,
                  label: 'Modified',
                  field: FileSortField.modified,
                ),
              ),
            if (columns.perms)
              FileListView._column(
                FileListView._permsWidth,
                Container(
                  alignment: Alignment.centerLeft,
                  padding: FileListView._cellPadding,
                  child: Text(
                    'Perms',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _SortHeaderCell.labelStyle(context, active: false),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A column title that sorts by [field]: hover highlights it and shows the
/// pointing hand, a click sorts (again: reverses). The active one is tinted
/// and carries the direction arrow — on the inner side for a right-aligned
/// column, so its label stays flush with the values below.
class const _SortHeaderCell({
  required final FileManagerController controller,
  required final String label,
  required final FileSortField field,
  final bool alignEnd = false,
}) extends StatelessWidget {
  static TextStyle? labelStyle(BuildContext context, {required bool active}) {
    final theme = Theme.of(context);
    return theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: active
          ? theme.colorScheme.primary
          : context.eaglyTheme.secondaryTextColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = controller.sortField == field;
    final arrow = Icon(
      controller.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
      size: context.scaled(12),
      color: theme.colorScheme.primary,
    );
    final text = Flexible(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: labelStyle(context, active: active),
      ),
    );
    return Tooltip(
      message: active
          ? 'Sorted ${controller.sortAscending ? 'ascending' : 'descending'}'
                ' — click to reverse'
          : 'Sort by ${field.label.toLowerCase()}',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(4),
        onTap: () => controller.setSort(field),
        child: Padding(
          padding: FileListView._cellPadding,
          child: Row(
            mainAxisAlignment: alignEnd
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            spacing: 2,
            children: [
              if (active && alignEnd) arrow,
              text,
              if (active && !alignEnd) arrow,
            ],
          ),
        ),
      ),
    );
  }
}

class const _FileRow({
  super.key,
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

    Widget detail(String text, TextStyle? style, {bool alignEnd = false}) =>
        Padding(
          padding: FileListView._cellPadding,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
            style: style,
          ),
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
              child: Padding(
                padding: FileListView._cellPadding,
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
                        child: FileNameText(
                          name: entry.name,
                          filter: controller.filterText,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (columns.size)
              FileListView._column(
                FileListView._sizeWidth,
                detail(
                  FileEntryVisuals.formatSize(entry),
                  detailStyle,
                  alignEnd: true,
                ),
              ),
            if (columns.modified)
              FileListView._column(
                FileListView._modifiedWidth,
                detail(
                  FileEntryVisuals.formatModified(entry.modified),
                  detailStyle,
                ),
              ),
            if (columns.perms)
              FileListView._column(
                FileListView._permsWidth,
                detail(
                  entry.permissions ?? entry.typeLabel,
                  eaglyTheme.monoStyle.copyWith(
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
    const gap = FileListView._columnGap;
    var used = FileListView._minNameWidth + gap + FileListView._sizeWidth;
    final size = width >= used;
    used += gap + FileListView._modifiedWidth;
    final modified = width >= used;
    used += gap + FileListView._permsWidth;
    final perms = width >= used;
    return _FileColumns(size: size, modified: modified, perms: perms);
  }
}
