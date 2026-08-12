import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/animation_utils.dart';
import '../../../presentation/components/available_device_card.dart';
import '../../../session/device_session_manager.dart';

/// The device section of the landing screen: a "searching / none found"
/// status box, or one [AvailableDeviceCard] per detected device.
class HomeDeviceList extends StatelessWidget {
  const HomeDeviceList({
    super.key,
    required this.manager,
    required this.onShowMessage,
  });

  final DeviceSessionManager manager;
  final ValueChanged<String> onShowMessage;

  @override
  Widget build(BuildContext context) {
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
