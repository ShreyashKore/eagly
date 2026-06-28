import 'dart:io';

import 'package:eagly/presentation/components/animation_utils.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../constants/app_constants.dart';
import '../../constants/local_assets.dart';
import '../../services/preferences_service.dart';
import '../../session/device_session_manager.dart';
import '../../utils/utils.dart';
import '../../presentation/components/available_device_card.dart';
import '../../presentation/components/get_started_action_card.dart';
import '../../presentation/components/ios_support_notice.dart';
import '../../presentation/components/layout_constants.dart';

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
                      _buildDeviceList(context),
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
                    children: [_RecentFilesList(onOpenRecent: onOpenRecent)],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeviceList(BuildContext context) {
    final theme = Theme.of(context);
    // Exclude the synthetic "Imported Logs" workspace — it's not a device.
    final sessions = [
      for (final session in manager.sessions)
        if (!session.isImportedWorkspace) session,
    ];

    if (sessions.isEmpty) {
      return Container(
        key: const ValueKey('status-box'),
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: AnimatedContent(
          child: manager.isLoadingDevices
              ? Column(
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const Gap(10),
                    Text(
                      'Searching for devices…',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                )
              : Column(
                  children: [
                    Icon(
                      Icons.usb_off,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const Gap(10),
                    Text('No devices found', style: theme.textTheme.titleSmall),
                    const Gap(6),
                    Text(
                      'Connect an Android device with ADB enabled, or an iOS device '
                      'supported by libimobiledevice.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
        ),
      );
    }

    return Column(
      key: const ValueKey('devices'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Gap(4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Devices', style: theme.textTheme.titleMedium),
        ),
        const Gap(8),
        for (final session in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AvailableDeviceCard(
              device: session.device,
              onSelected: () => manager.select(session.id),
              onInstallApp: session.isConnected
                  ? () => session.installAppFromPicker()
                  : null,
              onShowMessage: onShowMessage,
            ),
          ),
      ],
    );
  }
}

/// The last opened log files, bound to [PreferencesService.recentLogFilesListenable]
/// so it rebuilds as files are opened or removed. Empty until the first import.
class _RecentFilesList extends StatelessWidget {
  const _RecentFilesList({required this.onOpenRecent});

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
                child: _RecentFileTile(
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

class _RecentFileTile extends StatelessWidget {
  const _RecentFileTile({
    required this.path,
    required this.onOpen,
    required this.onRemove,
  });

  final String path;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      extractFileName(path),
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      path,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Gap(8),
              IconButton(
                tooltip: 'Remove from recent',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
