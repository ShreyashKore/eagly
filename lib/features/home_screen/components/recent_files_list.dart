import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../services/preferences_service.dart';
import 'recent_file_tile.dart';

/// The last opened log files, bound to [PreferencesService.recentLogFilesListenable]
/// so it rebuilds as files are opened or removed. Empty until the first import.
class RecentFilesList extends StatelessWidget {
  const RecentFilesList({super.key, required this.onOpenRecent});

  final ValueChanged<String> onOpenRecent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<List<String>>(
      valueListenable: PreferencesService.recentLogFilesListenable,
      builder: (context, recentFiles, _) {
        if (recentFiles.isEmpty) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Recently opened files will appear here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Recent files', style: theme.textTheme.titleSmall),
            ),
            const Gap(8),
            for (final path in recentFiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: RecentFileTile(
                  path: path,
                  onOpen: () => onOpenRecent(path),
                  onRemove: () => PreferencesService.removeRecentLogFile(path),
                ),
              ),
          ],
        );
      },
    );
  }
}
