import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/animation_utils.dart';
import '../../../presentation/components/available_device_card.dart';
import '../../../presentation/components/install_conflict_dialog.dart';
import '../../../session/device_session_manager.dart';

/// The body of the home page's Devices card: a "searching / none found"
/// status, or one [AvailableDeviceCard] per detected device.
class const HomeDeviceList({
  super.key,
  required final DeviceSessionManager manager,
  required final ValueChanged<String> onShowMessage,
}) extends StatelessWidget {
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
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
                      'Plug in an Android device with USB debugging on, or an '
                      'iPhone, or pair one over Wi-Fi.',
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
        for (final session in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AvailableDeviceCard(
              device: session.device,
              onSelected: () => manager.select(session.id),
              onInstallApp: session.isConnected
                  ? () async {
                      final result = await session.installAppFromPicker();
                      if (!context.mounted) return;
                      await presentAppInstallResult(
                        context,
                        session: session,
                        result: result,
                        showMessage: onShowMessage,
                      );
                    }
                  : null,
              onShowMessage: onShowMessage,
            ),
          ),
      ],
    );
  }
}
