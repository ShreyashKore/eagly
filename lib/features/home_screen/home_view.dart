import 'dart:io';

import 'package:eagly/presentation/components/animation_utils.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../constants/app_constants.dart';
import '../../constants/local_assets.dart';
import '../../session/device_session_manager.dart';
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
  });

  final DeviceSessionManager manager;
  final VoidCallback onShowWireless;
  final ValueChanged<String> onShowMessage;

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
    final sessions = manager.sessions;

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
