import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../controllers/log_tab_controller.dart';
import '../data/device.dart';
import '../theme/app_theme.dart';
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
  final VoidCallback? onExport;
  final VoidCallback? onOpenSettings;

  const Toolbar({
    super.key,
    required this.controller,
    required this.dropdownButtonKey,
    required this.onLoadDevices,
    required this.onShowWirelessConnectionDialog,
    required this.onSelectDevice,
    required this.onImport,
    required this.onExport,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logTheme = context.logViewTheme;
    final selectedValue = controller.devices.firstWhereOrNull(
      (device) => device.id == controller.selectedDevice?.id,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        spacing: 4,
        children: [
          if (controller.devices.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: BoxConstraints(maxWidth: 320),
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
                          constraints: BoxConstraints(maxWidth: 240),
                          child: DeviceLabel(
                            device: device,
                            maxWidth: 240,
                            textStyle: theme.textTheme.bodyMedium,
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
                            child: DeviceLabel(
                              device: device,
                              maxWidth: 240,
                              textStyle: theme.textTheme.bodyMedium,
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
                    padding: EdgeInsets.all(0),
                    tooltip: 'Reload devices',
                    onPressed: () => onLoadDevices(),
                    icon: const Icon(Icons.refresh),
                    iconSize: 20,
                  ),
                ],
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
          const Gap(4),
          SizedBox(
            height: 18,
            child: VerticalDivider(
              width: 2,
              thickness: 2,
              radius: BorderRadius.circular(2),
            ),
          ),
          const Gap(4),
          IconButton(
            icon: Icon(
              controller.isRunning
                  ? Icons.restart_alt_rounded
                  : Icons.play_arrow,
              color: controller.hasConnectedSelectedDevice
                  ? logTheme.statusLiveColor
                  : theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: controller.selectedDevice?.isDisconnected == true
                ? 'Selected device is disconnected'
                : controller.isRunning
                ? 'Restart'
                : 'Start',
            onPressed: !controller.hasConnectedSelectedDevice
                ? null
                : controller.startLogcat,
          ),
          IconButton(
            icon: Icon(
              controller.isPaused ? Icons.play_arrow : Icons.pause,
              color: controller.isRunning
                  ? logTheme.statusPausedColor
                  : theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: controller.isRunning
                ? (controller.isPaused ? 'Resume' : 'Pause')
                : 'Not running',
            onPressed: controller.isRunning
                ? controller.togglePauseResume
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: controller.logs.isNotEmpty
                ? 'Clear logs'
                : 'No logs to clear',
            onPressed: controller.logs.isNotEmpty ? controller.clearLogs : null,
          ),
          const Spacer(),
          // Action icons (previously ActionToolbar)
          IconButton(
            icon: Icon(
              Icons.search,
              color: controller.searchBarVisible
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: controller.searchBarVisible
                ? 'Close search'
                : 'Search in logs (Ctrl+F / Cmd+F)',
            onPressed: controller.toggleSearchBar,
          ),
          IconButton(
            onPressed: onImport,
            icon: const Icon(Icons.file_download),
            tooltip: 'Import Logcat File',
          ),
          IconButton(
            onPressed: onExport,
            icon: const Icon(Icons.file_upload),
            tooltip: 'Export Logs',
          ),
          IconButton(
            onPressed: controller.toggleWrapText,
            icon: Icon(controller.wrapText ? Icons.wrap_text : Icons.notes),
            tooltip: controller.wrapText ? 'Disable Wrap' : 'Enable Wrap',
          ),
          IconButton(
            onPressed: controller.toggleAutoScroll,
            icon: Icon(
              controller.autoScroll
                  ? Icons.vertical_align_bottom
                  : Icons.swipe_down,
            ),
            tooltip: controller.autoScroll
                ? 'Auto-scroll ON'
                : 'Auto-scroll OFF',
            color: controller.autoScroll ? theme.colorScheme.primary : null,
          ),
          Gap(4),
          SizedBox(
            height: 18,
            child: VerticalDivider(
              width: 2,
              thickness: 2,
              radius: BorderRadius.circular(2),
            ),
          ),
          Gap(4),
          IconButton(
            onPressed: onOpenSettings,
            icon: Icon(Icons.settings_rounded),
            tooltip: 'View settings',
          ),
        ],
      ),
    );
  }
}
