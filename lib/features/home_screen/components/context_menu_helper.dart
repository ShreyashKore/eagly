import 'package:flutter/material.dart';

import '../../../data/device.dart';
import '../../../session/device_session_controller.dart';
import '../../../session/device_session_manager.dart';
import '../../../presentation/components/context_menu.dart';
import '../../../presentation/components/snack_bars.dart';

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
    position: menuPositionAt(globalPosition),
    items: const [
      PopupMenuItem(
        value: _HeaderMenuAction.wireless,
        child: MenuRow(
          Icons.wifi_tethering_outlined,
          'Connect via Wireless ADB',
        ),
      ),
      PopupMenuItem(
        value: _HeaderMenuAction.emulators,
        child: MenuRow(Icons.smartphone_outlined, 'Android Emulators'),
      ),
      PopupMenuItem(
        value: _HeaderMenuAction.refresh,
        child: MenuRow(Icons.usb, 'Refresh Devices'),
      ),
      PopupMenuDivider(),
      PopupMenuItem(
        value: _HeaderMenuAction.settings,
        child: MenuRow(Icons.settings_rounded, 'Settings'),
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
    position: menuPositionAt(globalPosition),
    items: [
      if (!isWorkspace) ...[
        PopupMenuItem(
          value: _TabMenuAction.reload,
          enabled: onReload != null,
          child: const MenuRow(Icons.refresh, 'Reload tab'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _TabMenuAction.copyName,
          child: const MenuRow(Icons.title_outlined, 'Copy device name'),
        ),
        PopupMenuItem(
          value: _TabMenuAction.copyId,
          child: MenuRow(Icons.tag, 'Copy $idName'),
        ),
        const PopupMenuDivider(),
      ],
      PopupMenuItem(
        value: _TabMenuAction.close,
        enabled: onClose != null,
        child: const MenuRow(Icons.close, 'Close tab'),
      ),
    ],
  );

  if (result == null) return;
  switch (result) {
    case _TabMenuAction.reload:
      onReload?.call();
    case _TabMenuAction.copyName:
      if (!context.mounted) return;
      await copyWithToast(context, device.displayName, 'Copied device name.');
    case _TabMenuAction.copyId:
      if (!context.mounted) return;
      await copyWithToast(context, device.id, 'Copied $idName.');
    case _TabMenuAction.close:
      onClose?.call();
  }
}

enum _HeaderMenuAction { wireless, emulators, refresh, settings }

enum _TabMenuAction { reload, copyName, copyId, close }
