import 'package:flutter/material.dart';

import '../../data/device.dart';
import '../../services/devices_repository.dart';
import '../../services/ios/ios_device_trust_service.dart';
import 'confirm_dialog.dart';
import 'context_menu.dart';

/// Which way to cut an iPhone off from this computer; see
/// [IosDeviceTrustService].
enum IosTrustAction {
  /// Keeps the USB trust, stops Wi-Fi connections.
  stopWifi,

  /// Removes the pairing; the iPhone needs "Trust" over USB again.
  forget,
}

/// Whether [device]'s menus offer the [IosTrustAction]s.
bool offersIosTrustActions(Device device) =>
    device is IosDevice && iosDeviceTrustAvailable;

/// Asks before running [action] on [device], runs it, and says how it went in
/// a snackbar. The device list is refreshed after, so a forgotten iPhone
/// shows as disconnected rather than waiting for the next poll.
Future<void> confirmIosTrustAction(
  BuildContext context, {
  required Device device,
  required IosTrustAction action,
  IosDeviceTrustService? service,
  Future<void> Function()? refreshDevices,
}) async {
  final name = device.displayName;
  final confirmed = await switch (action) {
    IosTrustAction.stopWifi => showConfirmDialog(
      context,
      icon: Icons.wifi_off_rounded,
      title: 'Stop Wi-Fi connections from $name?',
      message:
          '$name stops offering itself to computers over Wi-Fi, so it no '
          'longer connects to Eagly on its own. The setting lives on the '
          'iPhone, so Xcode stops seeing it over Wi-Fi too.\n\n'
          'It still works when plugged in with a cable.',
      confirmLabel: 'Stop Wi-Fi',
    ),
    IosTrustAction.forget => showConfirmDialog(
      context,
      icon: Icons.link_off_rounded,
      title: 'Forget $name?',
      message:
          'This computer’s pairing with $name is removed, so it stops '
          'connecting on its own, over Wi-Fi or USB. To use it again, plug it '
          'in and tap Trust on the iPhone.\n\n'
          'Xcode and Finder share this pairing and lose the iPhone too.',
      confirmLabel: 'Forget',
      destructive: true,
    ),
  };
  if (!confirmed || !context.mounted) return;

  // The tab under the menu may go away once the device does.
  final messenger = ScaffoldMessenger.of(context);
  void show(String message) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  final trust = service ?? createIosDeviceTrustService();
  try {
    switch (action) {
      case IosTrustAction.stopWifi:
        await trust.stopWifiConnections(device.id);
        show('$name no longer connects over Wi-Fi.');
      case IosTrustAction.forget:
        await trust.forget(device.id);
        show('Forgot $name. It needs Trust over USB to connect again.');
    }
  } on IosDeviceTrustException catch (error) {
    show(switch (action) {
      IosTrustAction.stopWifi => 'Could not stop Wi-Fi connections: $error',
      IosTrustAction.forget => 'Could not forget $name: $error',
    });
  }
  await (refreshDevices ??
      () => DevicesRepository.instance.refreshDevices(force: true))();
}

/// The two actions as entries of a menu whose values are [T]: [value] maps
/// each action to the menu's own value.
List<PopupMenuEntry<T>> iosTrustMenuItems<T>(
  T Function(IosTrustAction action) value, {
  required ColorScheme colors,
}) => [
  PopupMenuItem(
    value: value(IosTrustAction.stopWifi),
    child: const MenuRow(Icons.wifi_off_rounded, 'Stop Wi-Fi connections…'),
  ),
  PopupMenuItem(
    value: value(IosTrustAction.forget),
    child: MenuRow(
      Icons.link_off_rounded,
      'Forget this iPhone…',
      color: colors.error,
    ),
  ),
];
