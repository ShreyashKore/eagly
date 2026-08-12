import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../data/device.dart';
import '../../../session/device_session_controller.dart';

/// Full-screen hint shown while files are dragged over the device screen.
class DropOverlay extends StatelessWidget {
  const DropOverlay({super.key, required this.session});

  final DeviceSessionController session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installable = session.platform == DevicePlatform.android
        ? 'APK'
        : 'IPA / .app';
    return ColoredBox(
      color: theme.colorScheme.scrim.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.primary, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.download_for_offline_outlined,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const Gap(12),
              Text(
                'Drop to install or copy to ${session.device.displayName}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Gap(4),
              Text(
                '$installable installs the app; other files are copied to the device.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
