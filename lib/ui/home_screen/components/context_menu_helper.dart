import 'package:flutter/material.dart';

import '../../../session/device_session_manager.dart';

void showHeaderMenu(
  BuildContext context,
  Offset globalPosition, {
  required DeviceSessionManager manager,
  required VoidCallback onShowWireless,
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
    case _HeaderMenuAction.refresh:
      manager.refreshDevices();
    case _HeaderMenuAction.settings:
      onOpenSettings();
  }
}

void showTabContextMenu(
  BuildContext context,
  Offset globalPosition, {
  required VoidCallback? onClose,
}) async {
  if (onClose == null) return;
  final result = await showMenu<_TabMenuAction>(
    context: context,
    position: _menuPosition(globalPosition),
    items: const [
      PopupMenuItem(
        value: _TabMenuAction.close,
        child: _MenuRow(Icons.close, 'Close Tab'),
      ),
    ],
  );
  if (result == _TabMenuAction.close) onClose();
}

enum _HeaderMenuAction { wireless, refresh, settings }

enum _TabMenuAction { close }

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
