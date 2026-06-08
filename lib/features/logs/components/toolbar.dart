import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../../session/device_session_controller.dart';
import '../log_controller.dart';

/// Toolbar for the Logs feature: capture controls (start/pause/clear), copy /
/// row-selection, search, view toggles, export, and app install (a device-level
/// action surfaced here, delegated to the [DeviceSessionController]).
class Toolbar extends StatelessWidget {
  final LogController controller;
  final DeviceSessionController session;
  final Future<void> Function()? onInstallApp;
  final ValueChanged<List<String>> onInstallDrop;
  final ValueChanged<bool> onInstallDropActiveChanged;
  final bool isInstallDropActive;
  final VoidCallback? onExport;
  final VoidCallback? onCopyAll;

  const Toolbar({
    super.key,
    required this.controller,
    required this.session,
    required this.onInstallApp,
    required this.onInstallDrop,
    required this.onInstallDropActiveChanged,
    required this.isInstallDropActive,
    required this.onExport,
    required this.onCopyAll,
  });

  @override
  Widget build(BuildContext context) {
    final divider = Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: VerticalDivider(
        width: 2,
        thickness: 2,
        radius: BorderRadius.circular(2),
      ),
    );

    final isConnected = session.isConnected;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        spacing: 4,
        children: [
          // ── Start / Restart ───────────────────────────────────────────────
          ToolbarIconButton(
            icon: controller.isRunning
                ? Icons.restart_alt_rounded
                : Icons.play_arrow,
            tooltip: !isConnected
                ? 'Device is disconnected'
                : controller.isRunning
                ? 'Restart'
                : 'Start',
            onPressed: !isConnected ? null : controller.startLogcat,
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
            tooltip: controller.logs.isNotEmpty
                ? 'Clear logs'
                : 'No logs to clear',
            onPressed: controller.logs.isNotEmpty ? controller.clearLogs : null,
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
            onPressed: onExport,
            icon: const Icon(Icons.file_upload),
            tooltip: 'Export Logs',
          ),
          _InstallButton(
            session: session,
            isConnected: isConnected,
            isInstallDropActive: isInstallDropActive,
            onInstallApp: onInstallApp,
            onInstallDrop: onInstallDrop,
            onInstallDropActiveChanged: onInstallDropActiveChanged,
          ),
        ],
      ),
    );
  }
}

/// Install button wrapped in a drop target so an APK / IPA can be dropped onto
/// it to install on this device.
class _InstallButton extends StatelessWidget {
  const _InstallButton({
    required this.session,
    required this.isConnected,
    required this.isInstallDropActive,
    required this.onInstallApp,
    required this.onInstallDrop,
    required this.onInstallDropActiveChanged,
  });

  final DeviceSessionController session;
  final bool isConnected;
  final bool isInstallDropActive;
  final Future<void> Function()? onInstallApp;
  final ValueChanged<List<String>> onInstallDrop;
  final ValueChanged<bool> onInstallDropActiveChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropTarget(
      onDragEntered: (_) => onInstallDropActiveChanged(true),
      onDragExited: (_) => onInstallDropActiveChanged(false),
      onDragDone: (details) {
        onInstallDropActiveChanged(false);
        onInstallDrop(
          details.files.map((file) => file.path).toList(growable: false),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isInstallDropActive
                ? theme.colorScheme.primary
                : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: IconButton(
          onPressed: onInstallApp == null ? null : () => onInstallApp!.call(),
          icon: session.isInstallingApp
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.app_registration_outlined),
          tooltip: session.isInstallingApp
              ? (session.installingAppName == null
                    ? 'Installing app…'
                    : 'Installing ${session.installingAppName}…')
              : isConnected
              ? 'Install app on this device'
              : 'Reconnect the device to install an app',
        ),
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
