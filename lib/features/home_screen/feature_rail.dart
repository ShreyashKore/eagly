import 'package:flutter/material.dart';

import '../../session/device_session_controller.dart';
import 'components/rail_button.dart';
import 'components/rail_footer.dart';

/// Far-left vertical rail listing the features available for a device. The
/// rail is split into two sections: Home (pinned at the top, its own
/// mutually-exclusive view) and the other destinations below a divider, each
/// of which toggles on/off independently and stacks side by side. Selecting
/// Home swaps the visible view but never closes the other panes underneath —
/// selecting any of them again restores the previous layout. Install opens a
/// file picker. Settings and the app version are pinned to the bottom.
class FeatureRail extends StatelessWidget {
  const FeatureRail({
    super.key,
    required this.session,
    required this.onInstall,
    required this.onOpenSettings,
  });

  final DeviceSessionController session;
  final VoidCallback onInstall;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        return Container(
          width: 72,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(
              right: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          padding: EdgeInsets.all(4),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    RailButton(
                      icon: Icons.home_outlined,
                      label: 'Home',
                      isActive: session.isHomeOpen,
                      tooltip: session.isHomeOpen
                          ? 'Hide device home'
                          : 'Show device home',
                      onTap: session.toggleHome,
                    ),
                    const SizedBox(height: 8),
                    Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface.withValues(
                                alpha: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Column(
                              spacing: 4,
                              children: [
                                RailButton(
                                  icon: Icons.article_outlined,
                                  label: 'Logs',
                                  isActive: session.isLogsOpen,
                                  tooltip: session.isLogsOpen
                                      ? 'Hide logs'
                                      : 'View device logs',
                                  onTap: session.toggleLogs,
                                ),
                                RailButton(
                                  icon: Icons.mobile_screen_share,
                                  label: 'Mirror',
                                  isActive: session.isMirrorOpen,
                                  enabled:
                                      session.canMirror ||
                                      session.isMirrorOpen,
                                  tooltip: session.canMirror
                                      ? (session.isMirrorOpen
                                            ? 'Hide mirror'
                                            : 'Open mirror')
                                      : 'Screen mirror supports connected Android devices',
                                  onTap:
                                      session.canMirror ||
                                          session.isMirrorOpen
                                      ? session.toggleMirror
                                      : null,
                                ),
                                if (session.canReadCrashReports)
                                  RailButton(
                                    icon: Icons.bug_report_outlined,
                                    label: 'Crashes',
                                    isActive: session.isCrashReportsOpen,
                                    tooltip: session.isCrashReportsOpen
                                        ? 'Hide crash reports'
                                        : 'Read crash reports',
                                    onTap: session.toggleCrashReports,
                                  ),
                                RailButton(
                                  icon: Icons.folder_outlined,
                                  label: 'Files',
                                  isActive: session.isFilesOpen,
                                  enabled:
                                      session.canManageFiles ||
                                      session.isFilesOpen,
                                  tooltip:
                                      session.canManageFiles ||
                                          session.isFilesOpen
                                      ? (session.isFilesOpen
                                            ? 'Hide files'
                                            : 'Browse device files')
                                      : 'Connect the device to browse files',
                                  onTap:
                                      session.canManageFiles ||
                                          session.isFilesOpen
                                      ? session.toggleFiles
                                      : null,
                                ),
                                RailButton(
                                  icon: Icons.apps_outlined,
                                  label: 'Apps',
                                  isActive: session.isAppsOpen,
                                  enabled:
                                      session.canManageApps ||
                                      session.isAppsOpen,
                                  tooltip:
                                      session.canManageApps ||
                                          session.isAppsOpen
                                      ? (session.isAppsOpen
                                            ? 'Hide apps'
                                            : 'Manage installed apps')
                                      : 'Connect the device to manage apps',
                                  onTap:
                                      session.canManageApps ||
                                          session.isAppsOpen
                                      ? session.toggleApps
                                      : null,
                                ),
                                RailButton(
                                  icon: session.isInstallingApp
                                      ? Icons.hourglass_top_rounded
                                      : Icons.system_update_outlined,
                                  label: 'Install',
                                  isActive: session.isInstallingApp,
                                  enabled: session.isConnected,
                                  tooltip: session.isInstallingApp
                                      ? (session.installingAppName == null
                                            ? 'Installing…'
                                            : 'Installing ${session.installingAppName}…')
                                      : session.isConnected
                                      ? 'Install app on this device'
                                      : 'Connect the device to install an app',
                                  onTap:
                                      session.isConnected &&
                                          !session.isInstallingApp
                                      ? onInstall
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withValues(
                                  alpha: session.isHomeOpen ? 0.5 : 0,
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              RailButton(
                icon: Icons.settings_rounded,
                label: 'Settings',
                isActive: false,
                tooltip: 'Settings',
                onTap: onOpenSettings,
              ),
              const RailFooter(),
            ],
          ),
        );
      },
    );
  }
}
