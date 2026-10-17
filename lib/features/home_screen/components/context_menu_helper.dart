import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/device.dart';
import '../../../session/device_session_controller.dart';
import '../../../session/device_session_manager.dart';

void showHeaderMenu(
  BuildContext context,
  Offset globalPosition, {
  required DeviceSessionManager manager,
  required VoidCallback onShowWireless,
  required VoidCallback onShowEmulators,
  required VoidCallback onOpenSettings,
}) async {
  final result = await showMenu<_HeaderMenuAction>(
    context: context,
    position: _menuPosition(globalPosition),
    items: const [
      PopupMenuItem(
        value: _HeaderMenuAction.wireless,
        child: _MenuRow(
          Icons.wifi_tethering_outlined,
          'Connect via Wireless ADB',
        ),
      ),
      PopupMenuItem(
        value: _HeaderMenuAction.emulators,
        child: _MenuRow(Icons.smartphone_outlined, 'Android Emulators'),
      ),
      PopupMenuItem(
        value: _HeaderMenuAction.refresh,
        child: _MenuRow(Icons.usb, 'Refresh Devices'),
      ),
      PopupMenuDivider(),
      PopupMenuItem(
        value: _HeaderMenuAction.settings,
        child: _MenuRow(Icons.settings_rounded, 'Settings'),
      ),
    ],
  );
  if (result == null) return;
  switch (result) {
    case _HeaderMenuAction.wireless:
      onShowWireless();
    case _HeaderMenuAction.emulators:
      onShowEmulators();
    case _HeaderMenuAction.refresh:
      manager.refreshDevices();
    case _HeaderMenuAction.settings:
      onOpenSettings();
  }
}

/// Right-click menu for a device tab. [onReload] is null for the synthetic
/// imported-logs workspace (no device to reload), [onClose] is null while the
/// device is still connected — both are then shown disabled so the actions
/// stay discoverable.
void showTabContextMenu(
  BuildContext context,
  Offset globalPosition, {
  required DeviceSessionController session,
  required VoidCallback? onReload,
  required VoidCallback? onClose,
}) async {
  final device = session.device;
  final isWorkspace = session.isImportedWorkspace;
  final idName = device.platform == DevicePlatform.ios ? 'UDID' : 'serial';

  final result = await showMenu<_TabMenuAction>(
    context: context,
    position: _menuPosition(globalPosition),
    items: [
      if (!isWorkspace) ...[
        PopupMenuItem(
          value: _TabMenuAction.reload,
          enabled: onReload != null,
          child: const _MenuRow(Icons.refresh, 'Reload tab'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _TabMenuAction.copyName,
          child: const _MenuRow(Icons.title_outlined, 'Copy device name'),
        ),
        PopupMenuItem(
          value: _TabMenuAction.copyId,
          child: _MenuRow(Icons.tag, 'Copy $idName'),
        ),
        const PopupMenuDivider(),
      ],
      PopupMenuItem(
        value: _TabMenuAction.close,
        enabled: onClose != null,
        child: const _MenuRow(Icons.close, 'Close tab'),
      ),
    ],
  );

  if (result == null) return;
  switch (result) {
    case _TabMenuAction.reload:
      onReload?.call();
    case _TabMenuAction.copyName:
      await Clipboard.setData(ClipboardData(text: device.displayName));
      if (context.mounted) _toast(context, 'Copied device name.');
    case _TabMenuAction.copyId:
      await Clipboard.setData(ClipboardData(text: device.id));
      if (context.mounted) _toast(context, 'Copied $idName.');
    case _TabMenuAction.close:
      onClose?.call();
  }
}

void _toast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

enum _HeaderMenuAction { wireless, emulators, refresh, settings }

enum _TabMenuAction { reload, copyName, copyId, close }

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 16), const SizedBox(width: 10), Text(label)],
    );
  }
}

RelativeRect _menuPosition(Offset globalPosition) => RelativeRect.fromLTRB(
  globalPosition.dx,
  globalPosition.dy,
  globalPosition.dx,
  globalPosition.dy,
);
