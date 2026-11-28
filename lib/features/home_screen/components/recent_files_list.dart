import 'package:flutter/material.dart';

import '../../../services/preferences_service.dart';
import 'home_start_list.dart';
import 'recent_file_tile.dart';

/// The last opened log files, bound to [PreferencesService.recentLogFilesListenable]
/// so it rebuilds as files are opened or removed. Shows a one-line hint
/// until the first import.
class const RecentFilesList({
  super.key,
  required final ValueChanged<String> onOpenRecent,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<List<String>>(
      valueListenable: PreferencesService.recentLogFilesListenable,
      builder: (context, recentFiles, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HomeSectionLabel('Recent'),
            if (recentFiles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  'Log files you open will appear here.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final path in recentFiles)
              RecentFileTile(
                path: path,
                onOpen: () => onOpenRecent(path),
                onRemove: () => PreferencesService.removeRecentLogFile(path),
              ),
          ],
        );
      },
    );
  }
}
