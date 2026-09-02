import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../app_menu/intents.dart';
import '../../../data/device.dart';
import '../../../presentation/theme/app_theme.dart';
import 'home_primitives.dart';

/// Full-width notice shown at the top of the dashboard once the device drops
/// off. The dashboard below it keeps rendering the last snapshot, so this
/// banner has to say clearly that what follows is frozen, not live.
class DisconnectedBanner extends StatelessWidget {
  const DisconnectedBanner({
    super.key,
    required this.device,
    required this.lastUpdatedAt,
    required this.hasSnapshot,
  });

  final Device device;
  final DateTime? lastUpdatedAt;
  final bool hasSnapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = context.eaglyTheme.warningColor;
    final seen = lastUpdatedAt;

    final subtitle = hasSnapshot
        ? 'Showing the last known state'
              '${seen == null ? '' : ', captured at ${formatClockTime(seen)}'}'
              ' — values below are frozen.'
        : 'Reconnect the device to see its vitals and use its features.';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: context.scaled(34),
            height: context.scaled(34),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.usb_off_rounded, size: 18, color: accent),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${device.displayName} disconnected',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Gap(2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Gap(12),
          const _ReloadButton(),
        ],
      ),
    );
  }
}

class _ReloadButton extends StatelessWidget {
  const _ReloadButton();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.tonalIcon(
          onPressed: () =>
              Actions.maybeInvoke(context, const ReloadDevicesIntent()),
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('Reload devices'),
        ),
        const Gap(8),
        KeyCap(label: acceleratorLabel('R', shift: true)),
      ],
    );
  }
}

/// Troubleshooting checklist shown when there is no snapshot to fall back on
/// — the device dropped before Eagly could read anything off it.
class ReconnectHelpCard extends StatelessWidget {
  const ReconnectHelpCard({super.key, required this.device});

  final Device device;

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

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

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
