import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import 'app_icon_button.dart';
import '../../services/ios/apple_usb_probe.dart';
import '../../services/preferences_service.dart';
import '../../utils/external_launcher.dart';
import '../theme/app_theme.dart';

/// Microsoft Store product id for Apple's "Apple Devices" app, which installs
/// Apple Mobile Device Support (the usbmuxd service the bundled iOS tools need).
const String _appleDevicesStoreId = '9np83lwlpz9k';
const String _appleDevicesStoreUri =
    'ms-windows-store://pdp/?productid=$_appleDevicesStoreId';
const String _appleDevicesStoreWebUrl =
    'https://apps.microsoft.com/detail/$_appleDevicesStoreId';

/// Opens the Apple Devices app's Microsoft Store page. The user approves the
/// install there.
Future<void> openAppleDevicesStorePage() async {
  final launched = await openExternalUrl(_appleDevicesStoreUri);
  if (!launched) {
    // Store protocol unavailable (e.g. Store-less Windows SKU); fall back to
    // the web listing, which still hands off to the Store's Install button.
    await openExternalUrl(_appleDevicesStoreWebUrl);
  }
}

/// What to call [devices] in a sentence: "iPhone", "iPad", "iPhone and iPad".
String _deviceNoun(List<AppleUsbDevice> devices) =>
    {for (final device in devices) device.kind.label}.join(' and ');

/// Subtle, dismissible hint shown when iOS detection is unavailable because
/// usbmuxd isn't reachable. Guides the user to install the Apple Devices app
/// (which provides the required Apple Mobile Device Support service) with one
/// click that opens its Microsoft Store page — they approve the install there.
///
/// With [devices] (iOS devices Windows has on USB) it says they are connected
/// instead of guessing, and a newly plugged-in one brings it back after it was
/// dismissed.
class const IosSupportNotice({
  super.key,
  final List<AppleUsbDevice> devices = const [],
}) extends StatefulWidget {
  @override
  State<IosSupportNotice> createState() => _IosSupportNoticeState();
}

class _IosSupportNoticeState extends State<IosSupportNotice> {
  bool _dismissed = false;

  @override
  void didUpdateWidget(IosSupportNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.devices.any((device) => !oldWidget.devices.contains(device))) {
      _dismissed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final eagly = context.eaglyTheme;
    final devices = widget.devices;
    final noun = devices.isEmpty ? null : _deviceNoun(devices);

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
                  noun == null
                      ? "Don't see your iPhone or iPad?"
                      : "$noun connected, but Eagly can't reach it",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: eagly.inlineNoticeForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Gap(2),
                Text(
                  noun == null
                      ? 'iOS devices need Apple Mobile Device Support, which '
                            'ships with the free Apple Devices app (or iTunes).'
                      : 'Windows sees it, but Eagly needs Apple Mobile Device '
                            'Support. Install the free Apple Devices app (or '
                            'iTunes), then unplug and reconnect the $noun.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: eagly.inlineNoticeForeground.withValues(alpha: 0.85),
                  ),
                ),
                const Gap(6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: openAppleDevicesStorePage,
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
          AppIconButton(
            tooltip: 'Dismiss',
            iconSize: 16,
            color: eagly.inlineNoticeForeground,
            onPressed: () => setState(() => _dismissed = true),
            icon: Icons.close_rounded,
          ),
        ],
      ),
    );
  }
}

/// Shows [IosSupportPromptDialog] for [devices].
Future<void> showIosSupportPrompt(
  BuildContext context,
  List<AppleUsbDevice> devices,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => IosSupportPromptDialog(devices: devices),
  );
}

/// Asks to install the Apple Devices app when an iOS device Eagly can't reach
/// is plugged in — the moment the user is looking for it. Ticking "Don't ask
/// again" sets [PreferencesService.skipIosSupportPrompt]; the home screen's
/// [IosSupportNotice] still names the device.
class const IosSupportPromptDialog({
  super.key,
  required final List<AppleUsbDevice> devices,

  /// Opens the Store page; tests pass a stand-in.
  final Future<void> Function() openStorePage = openAppleDevicesStorePage,
}) extends StatefulWidget {
  @override
  State<IosSupportPromptDialog> createState() => _IosSupportPromptDialogState();
}

class _IosSupportPromptDialogState extends State<IosSupportPromptDialog> {
  bool _dontAskAgain = false;

  void _close() {
    if (_dontAskAgain) PreferencesService.skipIosSupportPrompt = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noun = _deviceNoun(widget.devices);

    return AlertDialog(
      scrollable: true,
      icon: Icon(Icons.phone_iphone_rounded, color: theme.colorScheme.primary),
      title: Text('$noun connected'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Windows sees your $noun, but Eagly can't reach iOS devices "
              "without Apple Mobile Device Support. It comes with Apple's "
              'free Apple Devices app.',
              style: theme.textTheme.bodyMedium,
            ),
            const Gap(16),
            const _Step(
              number: 1,
              text:
                  'Install Apple Devices from the Microsoft Store. iTunes '
                  'works too.',
            ),
            _Step(number: 2, text: 'Unplug and reconnect the $noun.'),
            _Step(
              number: 3,
              text: 'Unlock the $noun and tap Trust if it asks.',
            ),
            CheckboxListTile(
              value: _dontAskAgain,
              onChanged: (value) =>
                  setState(() => _dontAskAgain = value ?? false),
              title: const Text("Don't ask again"),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _close, child: const Text('Not now')),
        FilledButton.icon(
          onPressed: () {
            _close();
            unawaited(widget.openStorePage());
          },
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('Get Apple Devices'),
        ),
      ],
    );
  }
}

class const _Step({required final int number, required final String text})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$number.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.eaglyTheme.tertiaryTextColor,
              ),
            ),
          ),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
