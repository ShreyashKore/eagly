import 'package:flutter/material.dart';

import '../data/device_file_entry.dart';
import '../file_manager_controller.dart';
import 'file_context_menu.dart';
import 'file_entry_visuals.dart';

/// Icon-grid view: a large icon, name and size per entry. Single tap selects,
/// double tap opens a directory, right-click shows the context menu.
class FileGridView extends StatelessWidget {
  const FileGridView({
    super.key,
    required this.controller,
    required this.actions,
  });

  final FileManagerController controller;
  final FileManagerActions actions;

  @override
  Widget build(BuildContext context) {
    final entries = controller.entries;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 128,
        mainAxisExtent: 116,
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
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.controller,
    required this.entry,
    required this.actions,
  });

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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FileEntryVisuals.iconFor(entry),
              size: 40,
              color: FileEntryVisuals.colorFor(entry, theme.colorScheme),
            ),
            const SizedBox(height: 8),
            Text(
              entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              FileEntryVisuals.formatSize(entry),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
