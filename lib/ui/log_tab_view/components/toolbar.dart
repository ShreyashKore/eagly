import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../../data/device.dart';
import '../log_tab_controller.dart';
import 'device_presentation.dart';

typedef LoadDevicesCallback =
    Future<void> Function({bool openPickerWhenNeeded});

/// A consolidated toolbar widget that includes device selection, control
/// buttons (start/pause/clear), and the action icons (search, import/export,
/// wrap, auto-scroll, settings).
class Toolbar extends StatelessWidget {
  final LogTabController controller;
  final GlobalKey dropdownButtonKey;
  final LoadDevicesCallback onLoadDevices;
  final VoidCallback onShowWirelessConnectionDialog;
  final Future<void> Function(Device) onSelectDevice;
  final VoidCallback? onImport;
  final Future<void> Function()? onInstallApp;
  final ValueChanged<List<String>> onInstallDrop;
  final ValueChanged<bool> onInstallDropActiveChanged;
  final bool isInstallDropActive;
  final VoidCallback? onExport;
  final VoidCallback? onCopyAll;
  final VoidCallback? onOpenSettings;

  const Toolbar({
    super.key,
    required this.controller,
    required this.dropdownButtonKey,
    required this.onLoadDevices,
    required this.onShowWirelessConnectionDialog,
    required this.onSelectDevice,
    required this.onImport,
    required this.onInstallApp,
    required this.onInstallDrop,
    required this.onInstallDropActiveChanged,
    required this.isInstallDropActive,
    required this.onExport,
    required this.onCopyAll,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedValue = controller.devices.firstWhereOrNull(
      (device) => device.id == controller.selectedDevice?.id,
    );

    final divider = Container(
      height: 18,
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: VerticalDivider(
        width: 2,
        thickness: 2,
        radius: BorderRadius.circular(2),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        spacing: 4,
        children: [
          if (controller.devices.isNotEmpty)
            DropTarget(
              onDragEntered: (_) => onInstallDropActiveChanged(true),
              onDragExited: (_) => onInstallDropActiveChanged(false),
              onDragDone: (details) {
                onInstallDropActiveChanged(false);
                onInstallDrop(
                  details.files
                      .map((file) => file.path)
                      .toList(growable: false),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isInstallDropActive
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    width: 1.4,
                  ),
                ),
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    DropdownButton<Device>(
                      key: dropdownButtonKey,
                      hint: const Text('Select Device'),
                      value: selectedValue,
                      underline: const SizedBox.shrink(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 0,
                      ),
                      isDense: true,
                      selectedItemBuilder: (context) {
                        return controller.devices.map((device) {
                          return Container(
                            alignment: Alignment.centerLeft,
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: DeviceSelectionLabel(
                              device: device,
                              maxWidth: 250,
                              textStyle: theme.textTheme.bodyMedium,
                              secondaryTextStyle: theme.textTheme.labelSmall,
                              iconSize: 18,
                            ),
                          );
                        }).toList();
                      },
                      borderRadius: BorderRadius.circular(8),
                      items: controller.devices
                          .map(
                            (device) => DropdownMenuItem(
                              value: device,
                              child: DeviceSelectionLabel(
                                device: device,
                                maxWidth: 240,
                                textStyle: theme.textTheme.bodyMedium,
                                secondaryTextStyle: theme.textTheme.labelSmall,
                                iconSize: 18,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (device) {
                        if (device != null) {
                          onSelectDevice(device);
                        }
                      },
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      tooltip: 'Reload devices',
                      onPressed: () => onLoadDevices(),
                      icon: const Icon(Icons.refresh),
                      iconSize: 20,
                    ),
                  ],
                ),
              ),
            )
          else
            FilledButton.tonalIcon(
              onPressed: () => onLoadDevices(openPickerWhenNeeded: true),
              icon: const Icon(Icons.usb),
              label: const Text('Load devices'),
            ),
          IconButton(
            icon: const Icon(Icons.wifi_tethering_outlined),
            tooltip: 'Wireless ADB connect',
            onPressed: onShowWirelessConnectionDialog,
          ),
          divider,
          // ── Start / Restart ───────────────────────────────────────────────
          ToolbarIconButton(
            icon: controller.isRunning
                ? Icons.restart_alt_rounded
                : Icons.play_arrow,
            tooltip: controller.selectedDevice?.isDisconnected == true
                ? 'Selected device is disconnected'
                : controller.isRunning
                ? 'Restart'
                : 'Start',
            onPressed: !controller.hasConnectedSelectedDevice
                ? null
                : controller.startLogcat,
          ),
          // ── Pause / Resume ────────────────────────────────────────────────
          ToolbarIconButton(
            icon: controller.isPaused ? Icons.play_arrow : Icons.pause,
            tooltip: controller.isRunning
                ? (controller.isPaused ? 'Resume' : 'Pause')
                : 'Not running',
            isActive: controller.isPaused,
            onPressed: controller.isRunning
                ? controller.togglePauseResume
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: controller.isReadingFromFile
                ? 'Cannot clear logs from a file'
                : controller.logs.isNotEmpty
                ? 'Clear logs'
                : 'No logs to clear',
            onPressed:
                !controller.isReadingFromFile && controller.logs.isNotEmpty
                ? controller.clearLogs
                : null,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: controller.hasAnyCachedLogs
                ? 'Copy all logs'
                : 'No logs to copy',
            onPressed: controller.hasAnyCachedLogs ? onCopyAll : null,
          ),
          // ── Row selection mode ────────────────────────────────────────────
          ToolbarIconButton(
            icon: controller.rowSelectionMode
                ? Icons.checklist_rounded
                : Icons.checklist_outlined,
            tooltip: controller.rowSelectionMode
                ? 'Disable row selection mode'
                : 'Enable row selection mode',
            isActive: controller.rowSelectionMode,
            onPressed: controller.filteredLogs.isNotEmpty
                ? controller.toggleRowSelectionMode
                : null,
          ),
          if (controller.hasSelectedRows)
            IconButton(
              icon: const Icon(Icons.deselect_outlined),
              tooltip: 'Clear selected rows',
              onPressed: controller.clearSelectedRows,
            ),
          divider,
          // ── Search ────────────────────────────────────────────────────────
          ToolbarIconButton(
            icon: Icons.search,
            tooltip: controller.searchBarVisible
                ? 'Close search'
                : 'Search in logs (Ctrl+F / Cmd+F)',
            isActive: controller.searchBarVisible,
            onPressed: () {
              if (controller.searchBarVisible) {
                controller.closeSearchBar();
              } else {
                controller.activateSearchFromSelection();
              }
            },
          ),
          IconButton(
            onPressed: onImport,
            icon: const Icon(Icons.file_download),
            tooltip: 'Import Logcat File',
          ),
          IconButton(
            onPressed: onInstallApp == null ? null : () => onInstallApp!.call(),
            icon: controller.isInstallingApp
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.app_registration_outlined),
            tooltip: controller.isInstallingApp
                ? (controller.installingAppName == null
                      ? 'Installing app…'
                      : 'Installing ${controller.installingAppName}…')
                : controller.hasConnectedSelectedDevice
                ? 'Install app on selected device'
                : 'Select a connected device to install an app',
          ),
          IconButton(
            onPressed: onExport,
            icon: const Icon(Icons.file_upload),
            tooltip: 'Export Logs',
          ),
          // ── Wrap text ─────────────────────────────────────────────────────
          ToolbarIconButton(
            icon: controller.wrapText ? Icons.wrap_text : Icons.notes,
            tooltip: controller.wrapText ? 'Disable Wrap' : 'Enable Wrap',
            isActive: controller.wrapText,
            onPressed: controller.toggleWrapText,
          ),
          // ── Auto-scroll ───────────────────────────────────────────────────
          ToolbarIconButton(
            icon: controller.autoScroll
                ? Icons.vertical_align_bottom
                : Icons.swipe_down,
            tooltip: controller.autoScroll
                ? 'Auto-scroll ON'
                : 'Auto-scroll OFF',
            isActive: controller.autoScroll,
            onPressed: controller.toggleAutoScroll,
          ),
          divider,
          IconButton(
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'View settings',
          ),
        ],
      ),
    );
  }
}

/// An icon button for the toolbar that shows a tinted rounded background when
/// [isActive] is true, making the toggled / enabled state clearly visible.
class ToolbarIconButton extends StatelessWidget {
  const ToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// When true the button renders with a tinted rounded background.
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = colorScheme.primary;
    final activeBg = colorScheme.primaryContainer.withValues(alpha: 0.55);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: onPressed == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive
                ? activeColor
                : onPressed == null
                ? colorScheme.onSurface.withValues(alpha: 0.38)
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
