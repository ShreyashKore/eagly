import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_constants.dart';
import '../../constants/local_assets.dart';
import '../../presentation/components/app_icon_button.dart';
import '../../presentation/components/ios_support_notice.dart';
import '../../presentation/components/layout_constants.dart';
import '../../presentation/theme/platform_look.dart';
import '../../services/eagly_info_service.dart';
import '../../session/device_session_manager.dart';
import 'components/home_device_list.dart';
import 'components/home_start_list.dart';
import 'components/recent_files_list.dart';

/// Landing screen shown when no device tab is selected, laid out like a
/// desktop IDE's start page: the app's name and version on top, a Start
/// list (with shortcuts) and the recent log files on the left, and the
/// detected devices on the right. Narrow windows stack the two columns.
class const HomeView({
  super.key,
  required final DeviceSessionManager manager,
  required final VoidCallback onShowWireless,
  required final VoidCallback onShowEmulators,
  required final ValueChanged<String> onShowMessage,

  /// Opens a log file via the system picker (no device required).
  required final VoidCallback onImportLog,

  /// Re-opens a previously imported log file by its absolute [path].
  required final ValueChanged<String> onOpenRecent,
}) extends StatelessWidget {
  /// Below this content width the Start column stacks above the devices.
  static const double twoColumnMinWidth = 640;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = [
      HomeStartAction(
        icon: Icons.wifi_tethering_outlined,
        label: 'Wireless pairing',
        key: LogicalKeyboardKey.keyP,
        onPressed: onShowWireless,
      ),
      HomeStartAction(
        icon: Icons.smartphone_outlined,
        label: 'Emulators',
        key: LogicalKeyboardKey.keyE,
        onPressed: onShowEmulators,
      ),
      HomeStartAction(
        icon: Icons.folder_open_outlined,
        label: 'Open log file',
        key: LogicalKeyboardKey.keyO,
        onPressed: onImportLog,
      ),
    ];

    return HomeStartShortcuts(
      actions: actions,
      child: ColoredBox(
        // Opaque, like the panes: the window material is for the chrome.
        color: theme.colorScheme.surfaceContainerLowest,
        child: Align(
          alignment: const Alignment(0, -0.35),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: LayoutConstants.getStartedMaxWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Masthead(),
                  const SizedBox(height: 28),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final start = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          HomeStartList(actions: actions),
                          const SizedBox(height: 20),
                          RecentFilesList(onOpenRecent: onOpenRecent),
                        ],
                      );
                      final devices = _DevicesCard(
                        manager: manager,
                        onShowMessage: onShowMessage,
                      );
                      if (constraints.maxWidth < twoColumnMinWidth) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            start,
                            const SizedBox(height: 20),
                            devices,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 260, child: start),
                          const SizedBox(width: 24),
                          Expanded(child: devices),
                        ],
                      );
                    },
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

/// The app icon, its name with the running version beside it, and what it
/// is for.
class const _Masthead() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = EaglyInfoService.appVersion;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(LocalAssets.appIcon, height: 52, width: 52),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    AppConstants.appName,
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (version != 'Unknown') ...[
                    const SizedBox(width: 10),
                    _VersionPill(version: version),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Stream live device logs, or open a saved log file.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class const _VersionPill({required final String version})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'v$version',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: colorScheme.primary),
      ),
    );
  }
}

/// The detected devices, under a header with their count and a refresh
/// button.
class const _DevicesCard({
  required final DeviceSessionManager manager,
  required final ValueChanged<String> onShowMessage,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final count = manager.sessions
            .where((session) => !session.isImportedWorkspace)
            .length;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(PlatformLook.surfaceRadius),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Devices', style: theme.textTheme.titleSmall),
                  if (count > 0)
                    Text(
                      '  ·  $count found',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const Spacer(),
                  AppIconButton(
                    tooltip: 'Load devices',
                    icon: Icons.refresh_rounded,
                    iconSize: 18,
                    onPressed: manager.isLoadingDevices
                        ? null
                        : manager.refreshDevices,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              HomeDeviceList(manager: manager, onShowMessage: onShowMessage),
              if (Platform.isWindows && manager.iosSupportUnavailable)
                IosSupportNotice(devices: manager.unreachableIosDevices),
            ],
          ),
        );
      },
    );
  }
}
