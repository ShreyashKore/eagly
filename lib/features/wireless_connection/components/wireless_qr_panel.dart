import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// QR pairing panel: shows the generated [payload] as a scannable code, or a
/// generate prompt while no pairing session exists.
class WirelessQrPanel extends StatelessWidget {
  const WirelessQrPanel({
    super.key,
    required this.payload,
    required this.waiting,
    required this.busy,
    required this.onGenerate,
    required this.onCancel,
  });

  /// QR payload from the active pairing session; null before generation.
  final String? payload;

  /// Whether the app is waiting for the device to scan the code.
  final bool waiting;
  final bool busy;
  final VoidCallback onGenerate;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (payload == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Generate a one-time pairing code',
              style: theme.textTheme.titleMedium,
            ),
            const Gap(8),
            Text(
              'A QR code will appear here for your device to scan. Pairing and '
              'connection continue automatically once it is scanned.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const Gap(18),
            FilledButton.icon(
              onPressed: busy ? null : onGenerate,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Generate QR code'),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          payload == null
              ? const SizedBox.square(
                  dimension: 220,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: payload!,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
          const Gap(18),
          if (waiting) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const Gap(10),
                Text(
                  'Waiting for the device to scan…',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            const Gap(16),
            OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
            ),
          ],
        ],
      ),
    );
  }
}
