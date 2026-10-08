import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/delayed_reveal.dart';
import '../../../presentation/components/hint_note.dart';
import '../../../presentation/theme/app_theme.dart';

/// The iOS wireless-pairing pane: advertises this computer as a pairable host
/// and walks the user through the device-initiated flow, showing the 6-digit
/// setup code once a device connects.
class IosWirelessPairPanel extends StatelessWidget {
  const IosWirelessPairPanel({
    super.key,
    required this.hostName,
    required this.waiting,
    required this.pin,
    required this.deviceName,
    required this.deviceModel,
    required this.deviceUdid,
    required this.error,
    required this.onPairAgain,
    this.hintDelay = const Duration(seconds: 12),
  });

  final String? hostName;
  final bool waiting;
  final String? pin;
  final String? deviceName;
  final String? deviceModel;
  final String? deviceUdid;
  final String? error;
  final VoidCallback onPairAgain;

  /// How long to advertise before offering the troubleshooting note.
  final Duration hintDelay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Pair an iPhone over Wi-Fi',
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              if (hostName != null)
                Text(
                  hostName!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const Gap(6),
          Text(
            'On the iPhone (iOS 27 or later), open Settings → Developer and '
            'choose this computer from the remote pairing list. The device '
            'drives the pairing; a code appears here to type on the phone.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(16),
          _buildBody(context),
          const Gap(4),
          if (pin == null && deviceUdid == null && error == null)
            DelayedReveal(
              enabled: waiting,
              delay: hintDelay,
              child: const Padding(
                padding: EdgeInsets.only(top: 12),
                child: HintNote(
                  title: 'Still waiting?',
                  text:
                      'The computer and the iPhone must be on the same Wi-Fi '
                      'network, and networks that isolate clients (guest or '
                      'public Wi-Fi) block discovery. Keep the Settings screen '
                      'open on the phone.',
                ),
              ),
            ),
          if (deviceUdid != null || error != null) ...[
            const Gap(12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onPairAgain,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Pair another device'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);

    if (error != null) {
      return _ErrorRow(message: error!);
    }

    if (deviceUdid != null) {
      return _PairedCard(
        name: deviceName,
        model: deviceModel,
        udid: deviceUdid!,
      );
    }

    if (pin != null) {
      return _PinCard(pin: pin!);
    }

    return Row(
      children: [
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const Gap(10),
        Text(
          'Waiting for the iPhone to connect…',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PinCard extends StatelessWidget {
  const _PinCard({required this.pin});

  final String pin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eagly = context.eaglyTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: eagly.inlineNoticeBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            'Enter this code on the iPhone',
            style: theme.textTheme.bodySmall?.copyWith(
              color: eagly.inlineNoticeForeground,
            ),
          ),
          const Gap(10),
          Text(
            pin,
            style: theme.textTheme.headlineMedium?.copyWith(
              letterSpacing: 6,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _PairedCard extends StatelessWidget {
  const _PairedCard({
    required this.name,
    required this.model,
    required this.udid,
  });

  final String? name;
  final String? model;
  final String udid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = [name, model].whereType<String>().join(' · ');

    return Row(
      children: [
        Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.isEmpty ? 'Device paired' : 'Paired with $label',
                style: theme.textTheme.bodyMedium,
              ),
              if (label.isNotEmpty)
                Text(
                  udid,
                  style: theme.textTheme.bodySmall?.copyWith(
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

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eagly = context.eaglyTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 20, color: eagly.warningColor),
        const Gap(10),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: eagly.warningColor,
            ),
          ),
        ),
      ],
    );
  }
}
