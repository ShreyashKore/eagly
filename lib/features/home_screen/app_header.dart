import 'package:eagly/features/home_screen/components/context_menu_helper.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../constants/app_constants.dart';
import '../../constants/local_assets.dart';
import '../../session/device_session_manager.dart';
import '../../utils/url_launcher.dart';
import 'components/device_tab.dart';
import 'window_controls.dart';

/// Top app header: logo + name, the horizontal device-tab strip (auto-created
/// per detected device), home/load/wireless actions, and a GitHub link.
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
                  onSecondaryTapUp: (details) => showHeaderMenu(
                    context,
                    details.globalPosition,
                    manager: manager,
                    onShowWireless: onShowWireless,
                    onOpenSettings: onOpenSettings,
                  ),
                  child: DragToMoveArea(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (macWindowButtonInset > 0)
                          SizedBox(width: macWindowButtonInset),
                        _Brand(onTap: manager.goHome),
                        const Gap(12),
                        Expanded(child: _DeviceTabStrip(manager: manager)),
                        const Gap(8),
                        _HeaderAction(
                          icon: manager.isLoadingDevices
                              ? null
                              : Icons.refresh_rounded,
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
                          icon: SvgPicture.asset(
                            LocalAssets.githubIcon,
                            color: theme.iconTheme.color,
                          ),
                          tooltip: 'View on GitHub',
                          onPressed: () =>
                              openExternalUrl(AppConstants.repoUrl),
                        ),
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

  /// Session ids we've already rendered, so a tab only plays its entrance +
  /// highlight-wave the first time it appears (i.e. when a device connects).
  final Set<String> _seenIds = {};
  bool _firstBuild = true;

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
        final sessions = manager.sessions;

        // Figure out which tabs are appearing for the first time. On the very
        // first build everything is "already there" (no entrance), so only
        // devices that connect later animate in.
        final currentIds = {for (final s in sessions) s.id};
        _seenIds.removeWhere((id) => !currentIds.contains(id));
        final freshIds = <String>{};
        for (final s in sessions) {
          if (_seenIds.add(s.id) && !_firstBuild) freshIds.add(s.id);
        }
        _firstBuild = false;

        return Listener(
          onPointerSignal: _onPointerSignal,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _scrollController,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final session in sessions)
                  DeviceTab(
                    key: ValueKey(session.id),
                    session: session,
                    selected: manager.selectedId == session.id,
                    animateIn: freshIds.contains(session.id),
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

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
  });

  final Object? icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      mouseCursor: SystemMouseCursors.click,
      icon: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : icon is IconData
          ? Icon(icon as IconData)
          : icon is Widget
          ? icon as Widget
          : const SizedBox.shrink(),
    );
  }
}
