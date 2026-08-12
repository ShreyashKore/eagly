import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../constants/app_constants.dart';
import '../../constants/local_assets.dart';
import '../../session/device_session_manager.dart';
import '../../presentation/components/get_started_action_card.dart';
import '../../presentation/components/ios_support_notice.dart';
import '../../presentation/components/layout_constants.dart';
import 'components/home_device_list.dart';
import 'components/recent_files_list.dart';

/// Landing screen shown when no device tab is selected. Lets the user load
/// devices, connect wirelessly, and pick a detected device to open its tab.
class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.manager,
    required this.onShowWireless,
    required this.onShowMessage,
    required this.onImportLog,
    required this.onOpenRecent,
  });

  final DeviceSessionManager manager;
  final VoidCallback onShowWireless;
  final ValueChanged<String> onShowMessage;

  /// Opens a log file via the system picker (no device required).
  final VoidCallback onImportLog;

  /// Re-opens a previously imported log file by its absolute [path].
  final ValueChanged<String> onOpenRecent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.surface,
                theme.colorScheme.primaryContainer,
                theme.colorScheme.surface,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: LayoutConstants.getStartedMaxWidth,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      LocalAssets.appIcon,
                      height: 96,
                      width: 96,
                    ),
                  ),
                  const Gap(18),
                  Text(
                    AppConstants.appName,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const Gap(6),
                  Text(
                    'Stream live device logs, or open a saved log file.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(28),
                  GetStartedActionCard(
                    icon: Icons.phone_android_rounded,
                    title: 'Select device',
                    subtitle:
                        'Discover connected Android and iOS devices and open a live log stream.',
                    onTap: () => manager.refreshDevices(),
                    secondaryActions: [
                      FilledButton.tonalIcon(
                        onPressed: () => manager.refreshDevices(),
                        icon: const Icon(Icons.usb),
                        label: const Text('Load devices'),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.wifi_tethering_outlined),
                        onPressed: onShowWireless,
                        label: const Text('Wireless ADB'),
                      ),
                    ],
                    children: [
                      HomeDeviceList(
                        manager: manager,
                        onShowMessage: onShowMessage,
                      ),
                      if (Platform.isWindows && manager.iosSupportUnavailable)
                        const IosSupportNotice(),
                    ],
                  ),
                  const Gap(16),
                  GetStartedActionCard(
                    icon: Icons.description_outlined,
                    title: 'Open a log file',
                    subtitle: 'View a saved logcat or syslog file.',
                    onTap: onImportLog,
                    secondaryActions: [
                      FilledButton.tonalIcon(
                        onPressed: onImportLog,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Import log file'),
                      ),
                    ],
                    children: [RecentFilesList(onOpenRecent: onOpenRecent)],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
