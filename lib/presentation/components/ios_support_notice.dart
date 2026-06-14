import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../utils/external_launcher.dart';
import '../theme/app_theme.dart';

/// Microsoft Store product id for Apple's "Apple Devices" app, which installs
/// Apple Mobile Device Support (the usbmuxd service the bundled iOS tools need).
const String _appleDevicesStoreId = '9np83lwlpz9k';
const String _appleDevicesStoreUri =
    'ms-windows-store://pdp/?productid=$_appleDevicesStoreId';
const String _appleDevicesStoreWebUrl =
    'https://apps.microsoft.com/detail/$_appleDevicesStoreId';

/// Subtle, dismissible hint shown when iOS detection is unavailable because
/// usbmuxd isn't reachable. Guides the user to install the Apple Devices app
/// (which provides the required Apple Mobile Device Support service) with one
/// click that opens its Microsoft Store page — they approve the install there.
class IosSupportNotice extends StatefulWidget {
  const IosSupportNotice({super.key});

  @override
  State<IosSupportNotice> createState() => _IosSupportNoticeState();
}

class _IosSupportNoticeState extends State<IosSupportNotice> {
  bool _dismissed = false;

  Future<void> _openInstallPage() async {
    final launched = await openExternalUrl(_appleDevicesStoreUri);
    if (!launched) {
      // Store protocol unavailable (e.g. Store-less Windows SKU); fall back to
      // the web listing, which still hands off to the Store's Install button.
      await openExternalUrl(_appleDevicesStoreWebUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final eagly = context.eaglyTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: eagly.inlineNoticeBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.phone_iphone_rounded,
            size: 18,
            color: eagly.inlineNoticeForeground,
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Don't see your iPhone or iPad?",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: eagly.inlineNoticeForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Gap(2),
                Text(
                  'iOS devices need Apple Mobile Device Support, which ships '
                  'with the free Apple Devices app.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: eagly.inlineNoticeForeground.withValues(alpha: 0.85),
                  ),
                ),
                const Gap(6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _openInstallPage,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Get the Apple Devices app'),
                    style: TextButton.styleFrom(
                      foregroundColor: eagly.inlineNoticeForeground,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            color: eagly.inlineNoticeForeground,
            onPressed: () => setState(() => _dismissed = true),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
