import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../features/app_log/app_logger.dart';
import '../../../../presentation/components/app_log_overlay.dart';
import '../../../../presentation/theme/app_theme.dart';
import '../../../../utils/utils.dart';
import '../../log_controller.dart';
import 'log_lines_limit_editor.dart';

(String, Color) _liveStatusLabel(EaglyTheme theme, LogController controller) {
  if (controller.liveLoggingInterrupted) {
    return ('Interrupted', theme.statusStoppedColor);
  }
  if (controller.isRecovering) {
    return ('Reconnecting…', theme.statusPausedColor);
  }
  if (controller.isPaused) return ('Paused', theme.statusPausedColor);
  if (controller.isRunning) return ('Live', theme.statusLiveColor);
  return ('Stopped', theme.statusStoppedColor);
}

/// Bottom status bar: log/filtered/selected counts, memory usage, the
/// max-lines editor, and the live/imported status indicator.
class LogStatusBar extends StatelessWidget {
  const LogStatusBar({
    super.key,
    required this.controller,
    required this.appMemoryBytes,
    required this.deviceDisplayName,
  });

  final LogController controller;
  final int appMemoryBytes;
  final String deviceDisplayName;

  @override
  Widget build(BuildContext context) {
    final theme = context.eaglyTheme;

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text('Logs: ${controller.logCount}', style: theme.statusBarStyle),
          const Gap(16),
          Text(
            'Filtered: ${controller.filteredLogs.length}',
            style: theme.statusBarStyle,
          ),
          if (controller.rowSelectionMode || controller.hasSelectedRows) ...[
            const Gap(16),
            Text(
              'Selected: ${controller.selectedRowCount}',
              style: theme.statusBarStyle,
            ),
          ],
          const Spacer(),
          Text(
            'App mem: ${formatBytes(appMemoryBytes)}',
            style: theme.statusBarStyle,
          ),
          const Gap(16),
          Text(
            'Logs mem: ${formatBytes(controller.totalLogsMemoryBytes)}',
            style: theme.statusBarStyle,
          ),
          const Gap(8),
          LogLinesLimitEditor(controller: controller),
          const Gap(8),
          SizedBox(
            height: 18,
            child: VerticalDivider(
              width: 2,
              thickness: 2,
              radius: BorderRadius.circular(2),
            ),
          ),
          const Gap(8),
          if (controller.isImported)
            Text(
              'Imported',
              style: TextStyle(
                fontSize: 12,
                color: theme.statusBarStyle.color,
                fontWeight: FontWeight.bold,
              ),
            )
          else
            Builder(
              builder: (context) {
                final (label, color) = _liveStatusLabel(theme, controller);
                return Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ListenableBuilder(
            listenable: AppLogger.global.entriesListenable,
            builder: (context, _) {
              final hasWorkspaceErrors = AppLogger.global.hasEntries(
                sessionTag: controller.appLogSessionTag,
                errorsOnly: true,
              );
              if (!hasWorkspaceErrors) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Gap(8),
                  AppLogTriggerButton(
                    sessionTag: controller.appLogSessionTag,
                    title: 'App Logs • $deviceDisplayName',
                    tooltip: 'Show app errors for this device',
                    iconSize: 16,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
