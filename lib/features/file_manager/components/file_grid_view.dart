import 'package:flutter/material.dart';

import '../data/device_file_entry.dart';
import '../file_manager_controller.dart';
import 'file_context_menu.dart';
import 'file_entry_visuals.dart';
import '../../../presentation/theme/app_theme.dart';

/// Icon-grid view: a large icon, name and size per entry. Single tap selects,
/// double tap opens a directory, right-click shows the context menu.
class const FileGridView({
  super.key,
  required this.controller,
  required this.actions,
}) extends StatelessWidget {
  final FileManagerController controller;
  final FileManagerActions actions;

  static const double _iconSize = 40;
  static const EdgeInsets _tilePadding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 8,
  );

  @override
  Widget build(BuildContext context) {
    final entries = controller.entries;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: context.scaled(128),
        mainAxisExtent: _tileHeight(context),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) => _GridTile(
        controller: controller,
        entry: entries[index],
        actions: actions,
      ),
    );
  }

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

class const _GridTile({
  required this.controller,
  required this.entry,
  required this.actions,
}) extends StatelessWidget {
  final FileManagerController controller;
  final DeviceFileEntry entry;
  final FileManagerActions actions;

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
      child: Container(
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
        padding: FileGridView._tilePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FileEntryIcon(entry: entry, size: FileGridView._iconSize),
            const SizedBox(height: 8),
            Text(
              entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
    );
  }
}
