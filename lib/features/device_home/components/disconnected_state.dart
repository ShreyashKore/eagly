import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../app_menu/intents.dart';
import '../../../data/device.dart';
import '../../../presentation/components/notice_banner.dart';
import '../../../presentation/theme/app_theme.dart';
import 'home_primitives.dart';

/// Full-width notice shown at the top of the dashboard once the device drops
/// off. The dashboard below it keeps rendering the last snapshot, so this
/// banner has to say clearly that what follows is frozen, not live.
class const DisconnectedBanner({
  super.key,
  required final Device device,
  required final DateTime? lastUpdatedAt,
  required final bool hasSnapshot,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final seen = lastUpdatedAt;

    final subtitle = hasSnapshot
        ? 'Showing the last known state'
              '${seen == null ? '' : ', captured at ${formatClockTime(seen)}'}.'
        : 'Reconnect the device to see its vitals and use its features.';

    return NoticeBanner(
      icon: Icons.usb_off_rounded,
      title: '${device.displayName} disconnected',
      message: subtitle,
      actions: [
        NoticeButton(
          primary: true,
          icon: Icons.refresh_rounded,
          label: 'Reload devices',
          onPressed: () =>
              Actions.maybeInvoke(context, const ReloadDevicesIntent()),
        ),
        KeyCap(label: acceleratorLabel('R', shift: true)),
      ],
    );
  }
}

/// Troubleshooting checklist shown when there is no snapshot to fall back on
/// — the device dropped before Eagly could read anything off it.
class const ReconnectHelpCard({super.key, required final Device device})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isIos = device is IosDevice;
    final steps = isIos
        ? const [
            (
              Icons.cable_rounded,
              'Reconnect the cable',
              'Use a data-capable Lightning/USB-C cable, then wait a few '
                  'seconds for pairing.',
            ),
            (
              Icons.lock_open_rounded,
              'Unlock and trust',
              'Unlock the device and tap "Trust This Computer" on the '
                  'prompt.',
            ),
            (
              Icons.developer_mode,
              'Enable Developer Mode',
              'On iOS 16+, turn on Settings › Privacy & Security › '
                  'Developer Mode.',
            ),
          ]
        : const [
            (
              Icons.cable_rounded,
              'Reconnect the cable',
              'Use a data-capable USB cable, or re-pair the device over '
                  'wireless ADB.',
            ),
            (
              Icons.lock_open_rounded,
              'Unlock and authorize',
              'Unlock the device and accept the "Allow USB debugging" '
                  'prompt.',
            ),
            (
              Icons.developer_mode,
              'Check Developer options',
              'USB debugging must stay enabled in Settings › System › '
                  'Developer options.',
            ),
          ];

    return SectionCard(
      title: 'Getting reconnected',
      icon: Icons.help_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (icon, title, body) in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _Step(icon: icon, title: title, body: body),
            ),
        ],
      ),
    );
  }
}

class const _Step({
  required final IconData icon,
  required final String title,
  required final String body,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: context.scaled(26),
          height: context.scaled(26),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Gap(10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Gap(1),
              Text(
                body,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  height: 1.35,
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
