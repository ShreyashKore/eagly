import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/device_file_entry.dart';
import '../file_manager_controller.dart';
import 'file_browser_keys.dart';
import 'file_context_menu.dart';
import 'file_entry_visuals.dart';
import 'file_group_header.dart';
import '../../../presentation/theme/app_theme.dart';

/// Icon-grid view: a large icon, name and size per entry, in labelled,
/// foldable sections when grouped. Single tap selects, double tap opens a
/// directory, right-click shows the context menu; [FileBrowserKeys] adds the
/// keyboard, moving a whole row on ↑/↓.
class const FileGridView({
  super.key,
  required final FileManagerController controller,
  required final FileManagerActions actions,
  final FocusNode? focusNode,
}) extends StatefulWidget {
  static const double _iconSize = 40;
  static const double _spacing = 8;
  static const double _padding = 12;
  static const EdgeInsets _tilePadding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 8,
  );

  @override
  State<FileGridView> createState() => _FileGridViewState();

  /// Fits the icon, a two-line name and the size at the current zoom and
  /// font — a fixed height overflowed as soon as a name wrapped or the app
  /// was zoomed in.
  static double _tileHeight(BuildContext context) {
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    double lineHeight(TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag', style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return _tilePadding.vertical +
        2 + // border
        context.scaled(_iconSize) +
        8 +
        2 * lineHeight(_nameStyle(theme)) +
        2 +
        lineHeight(_sizeStyle(theme));
  }

  static TextStyle? _nameStyle(ThemeData theme) => theme.textTheme.bodySmall;

  static TextStyle? _sizeStyle(ThemeData theme) => theme.textTheme.labelSmall
      ?.copyWith(color: theme.extension<EaglyTheme>()!.tertiaryTextColor);
}

class _FileGridViewState extends State<FileGridView> {
  final GlobalKey _selectedTileKey = GlobalKey();

  FileManagerController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final groups = controller.groups;
    final selectedPath = controller.selectedEntry?.path;
    final maxTileWidth = context.scaled(128);
    final delegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: maxTileWidth,
      mainAxisExtent: FileGridView._tileHeight(context),
      crossAxisSpacing: FileGridView._spacing,
      mainAxisSpacing: FileGridView._spacing,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // The count SliverGridDelegateWithMaxCrossAxisExtent arrives at, so
        // ↑/↓ move exactly one row.
        final usable = constraints.maxWidth - 2 * FileGridView._padding;
        final columns = math.max(
          1,
          (usable / (maxTileWidth + FileGridView._spacing)).ceil(),
        );
        return FileBrowserKeys(
          controller: controller,
          actions: widget.actions,
          focusNode: widget.focusNode,
          revealKey: _selectedTileKey,
          columns: columns,
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
                    SliverPadding(
                      padding: const EdgeInsets.all(FileGridView._padding),
                      sliver: SliverGrid(
                        gridDelegate: delegate,
                        delegate: SliverChildBuilderDelegate(
                          childCount: group.entries.length,
                          (context, index) {
                            final entry = group.entries[index];
                            return _GridTile(
                              key: entry.path == selectedPath
                                  ? _selectedTileKey
                                  : null,
                              controller: controller,
                              entry: entry,
                              actions: widget.actions,
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class const _GridTile({
  super.key,
  required final FileManagerController controller,
  required final DeviceFileEntry entry,
  required final FileManagerActions actions,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = controller.selectedEntry?.path == entry.path;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
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
      // Ink, not a Container: an opaque fill above the InkWell would hide its
      // hover highlight.
      child: Ink(
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: FileGridView._tilePadding,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FileEntryIcon(entry: entry, size: FileGridView._iconSize),
              const SizedBox(height: 8),
              FileNameText(
                name: entry.name,
                filter: controller.filterText,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: FileGridView._nameStyle(theme),
              ),
              const SizedBox(height: 2),
              Text(
                FileEntryVisuals.formatSize(entry),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FileGridView._sizeStyle(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
