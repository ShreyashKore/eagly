import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../presentation/components/delayed_reveal.dart';
import '../../../presentation/components/hint_note.dart';
import '../../../presentation/theme/app_theme.dart';

/// The pair-by-QR card that heads the pairing pane.
///
/// The code is always on screen — it is generated locally, so there is nothing
/// to wait for and no generate button. The troubleshooting note stays hidden
/// until scanning has visibly taken a while.
class WirelessQrPanel extends StatelessWidget {
  const WirelessQrPanel({
    super.key,
    required this.payload,
    required this.waiting,
    required this.pairing,
    required this.onRegenerate,
    this.hintDelay = const Duration(seconds: 12),
  });

  /// QR payload from the active pairing session.
  final String? payload;

  /// Whether the app is watching for this code to be scanned.
  final bool waiting;

  /// Whether a scanned code is being paired/connected right now.
  final bool pairing;
  final VoidCallback onRegenerate;

  /// How long to wait before offering the troubleshooting note.
  final Duration hintDelay;

  static const double _qrSize = 156;

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _QrCode(payload: payload),
          const Gap(20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Pair with a QR code', style: theme.textTheme.titleMedium),
                const Gap(6),
                Text(
                  'On the device: Settings → Developer options → Wireless '
                  'debugging → Pair device with QR code. Pairing and '
                  'connection continue on their own once it is scanned.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.eaglyTheme.secondaryTextColor,
                  ),
                ),
                const Gap(12),
                _StatusLine(waiting: waiting, pairing: pairing),
                DelayedReveal(
                  enabled: waiting,
                  delay: hintDelay,
                  restartKey: payload,
                  child: const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: HintNote(
                      title: 'Still waiting?',
                      text:
                          'The computer and the device must be on the same '
                          'Wi-Fi network, and networks that isolate clients '
                          '(guest or public Wi-Fi) block pairing. Keep the '
                          'pairing screen open on the device, or use Manual '
                          'entry with the address it shows.',
                    ),
                  ),
                ),
                const Gap(4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: pairing ? null : onRegenerate,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('New code'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrCode extends StatelessWidget {
  const _QrCode({required this.payload});

  final String? payload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox.square(
        dimension: WirelessQrPanel._qrSize,
        child: payload == null
            ? const Center(child: CircularProgressIndicator())
            : QrImageView(
                data: payload!,
                version: QrVersions.auto,
                size: WirelessQrPanel._qrSize,
                backgroundColor: Colors.white,
              ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.waiting, required this.pairing});

  final bool waiting;
  final bool pairing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!waiting && !pairing) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const Gap(10),
        Flexible(
          child: Text(
            pairing ? 'Pairing…' : 'Waiting for the device to scan…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.eaglyTheme.secondaryTextColor,
            ),
          ),
        ),
      ],
    );
  }
}
