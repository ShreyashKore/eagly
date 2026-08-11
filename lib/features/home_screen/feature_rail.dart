import 'package:flutter/material.dart';

import '../../services/eagly_info_service.dart';
import '../../session/device_session_controller.dart';

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
                    _RailButton(
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
                                _RailButton(
                                  icon: Icons.article_outlined,
                                  label: 'Logs',
                                  isActive: session.isLogsOpen,
                                  tooltip: session.isLogsOpen
                                      ? 'Hide logs'
                                      : 'View device logs',
                                  onTap: session.toggleLogs,
                                ),
                                _RailButton(
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
                                  _RailButton(
                                    icon: Icons.bug_report_outlined,
                                    label: 'Crashes',
                                    isActive: session.isCrashReportsOpen,
                                    tooltip: session.isCrashReportsOpen
                                        ? 'Hide crash reports'
                                        : 'Read crash reports',
                                    onTap: session.toggleCrashReports,
                                  ),
                                _RailButton(
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
                                _RailButton(
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
              _RailButton(
                icon: Icons.settings_rounded,
                label: 'Settings',
                isActive: false,
                tooltip: 'Settings',
                onTap: onOpenSettings,
              ),
              const _RailFooter(),
            ],
          ),
        );
      },
    );
  }
}

/// Bottom-pinned separator and the app version, shown unobtrusively.
class _RailFooter extends StatelessWidget {
  const _RailFooter();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: 1,
          thickness: 1,
          indent: 16,
          endIndent: 16,
          color: colorScheme.outlineVariant,
        ),
        const SizedBox(height: 6),
        Text(
          'v${EaglyInfoService.appVersion}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final String tooltip;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : isActive
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive
            ? colorScheme.primaryContainer.withValues(alpha: 1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        animationDuration: const Duration(milliseconds: 250),
        child: InkWell(
          onTap: enabled ? onTap : null,
          mouseCursor: SystemMouseCursors.click,
          splashColor: colorScheme.primary.withValues(alpha: 0.24),
          highlightColor: colorScheme.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  Icon(icon, size: 22, color: foreground),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: foreground),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
