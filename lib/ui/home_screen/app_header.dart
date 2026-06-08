import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:window_manager/window_manager.dart';

import '../../constants/app_constants.dart';
import '../../constants/local_assets.dart';
import '../../session/device_session_controller.dart';
import '../../session/device_session_manager.dart';
import '../components/device_presentation.dart';
import 'window_controls.dart';

/// Top app header: logo + name, the horizontal device-tab strip (auto-created
/// per detected device), home/load/wireless actions, and settings.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.manager,
    required this.onOpenSettings,
    required this.onShowWireless,
  });

  final DeviceSessionManager manager;
  final VoidCallback onOpenSettings;
  final VoidCallback onShowWireless;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        return Container(
          height: 52,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          padding: EdgeInsets.only(
            left: 10,
            right: usesCustomWindowCaption ? 0 : 10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: GestureDetector(
                  onSecondaryTapUp: (details) => _showHeaderMenu(
                    context,
                    details.globalPosition,
                    manager: manager,
                    onShowWireless: onShowWireless,
                    onOpenSettings: onOpenSettings,
                  ),
                  child: DragToMoveArea(
                    child: Row(
                      children: [
                        if (macWindowButtonInset > 0)
                          SizedBox(width: macWindowButtonInset),
                        _Brand(onTap: manager.goHome),
                        const Gap(12),
                        Expanded(child: _DeviceTabStrip(manager: manager)),
                        const Gap(8),
                        _HeaderAction(
                          icon: Icons.home_outlined,
                          tooltip: 'Home',
                          isActive: manager.isHome,
                          onPressed: manager.goHome,
                        ),
                        _HeaderAction(
                          icon: manager.isLoadingDevices ? null : Icons.usb,
                          tooltip: 'Load / refresh devices',
                          busy: manager.isLoadingDevices,
                          onPressed: () => manager.refreshDevices(),
                        ),
                        _HeaderAction(
                          icon: Icons.wifi_tethering_outlined,
                          tooltip: 'Wireless ADB',
                          onPressed: onShowWireless,
                        ),
                        const Gap(4),
                        SizedBox(
                          height: 22,
                          child: VerticalDivider(
                            width: 2,
                            thickness: 1,
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        const Gap(4),
                        _HeaderAction(
                          icon: Icons.settings_rounded,
                          tooltip: 'Settings',
                          onPressed: onOpenSettings,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (usesCustomWindowCaption) const WindowControls(),
            ],
          ),
        );
      },
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      mouseCursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(LocalAssets.appIcon, height: 26, width: 26),
            ),
            const Gap(8),
            Text(
              AppConstants.appName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTabStrip extends StatefulWidget {
  const _DeviceTabStrip({required this.manager});

  final DeviceSessionManager manager;

  @override
  State<_DeviceTabStrip> createState() => _DeviceTabStripState();
}

class _DeviceTabStripState extends State<_DeviceTabStrip> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_scrollController.hasClients) return;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    _scrollController.jumpTo(
      (_scrollController.offset + delta).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = widget.manager;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        return Listener(
          onPointerSignal: _onPointerSignal,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _scrollController,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final session in manager.sessions)
                  _DeviceTab(
                    key: ValueKey(session.id),
                    session: session,
                    selected: manager.selectedId == session.id,
                    onSelect: () => manager.select(session.id),
                    onClose: manager.canClose(session.id)
                        ? () => manager.close(session.id)
                        : null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DeviceTab extends StatelessWidget {
  const _DeviceTab({
    super.key,
    required this.session,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final DeviceSessionController session;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final device = session.device;
        final background = selected
            ? theme.colorScheme.surface
            : Colors.transparent;

        final label = device.displayLabel;
        final tooltipMessage = [
          label.primary,
          label.secondary,
        ].whereType<String>().join('  ·  ');

        return GestureDetector(
          onSecondaryTapUp: (details) => _showTabContextMenu(
            context,
            details.globalPosition,
            onClose: onClose,
          ),
          child: Tooltip(
            message: tooltipMessage,
            waitDuration: const Duration(milliseconds: 600),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
              child: Material(
                color: background,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onSelect,
                  mouseCursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.only(left: 12, right: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? theme.colorScheme.outlineVariant
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ConnectionDot(connected: device.isConnected),
                        const Gap(6),
                        DeviceSelectionLabel(
                          device: device,
                          maxWidth: 160,
                          textStyle: theme.textTheme.bodyMedium,
                          secondaryTextStyle: theme.textTheme.labelSmall,
                          iconSize: 16,
                        ),
                        if (onClose != null) ...[
                          const Gap(4),
                          IconButton(
                            tooltip: 'Close tab',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            mouseCursor: SystemMouseCursors.click,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            iconSize: 16,
                            onPressed: onClose,
                            icon: const Icon(Icons.close),
                          ),
                        ] else
                          const Gap(6),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: connected
            ? Colors.green
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
    this.busy = false,
  });

  final IconData? icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isActive;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: isActive,
      mouseCursor: SystemMouseCursors.click,
      color: isActive ? colorScheme.primary : null,
      icon: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
    );
  }
}

// ---------------------------------------------------------------------------
// Context menu helpers
// ---------------------------------------------------------------------------

RelativeRect _menuPosition(Offset globalPosition) => RelativeRect.fromLTRB(
  globalPosition.dx,
  globalPosition.dy,
  globalPosition.dx,
  globalPosition.dy,
);

void _showHeaderMenu(
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

void _showTabContextMenu(
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
