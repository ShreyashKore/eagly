import 'package:eagly/features/home_screen/components/context_menu_helper.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:window_manager/window_manager.dart';
import '../../session/device_session_manager.dart';
import '../updates/update_chip.dart';
import '../tips/tips_controller.dart';
import '../tips/tips_header_panel.dart';
import 'components/brand.dart';
import 'components/device_tab_strip.dart';
import 'components/github_star_button.dart';
import 'components/header_action.dart';
import 'window_controls.dart';

/// Top app header: logo + name, the horizontal device-tab strip (auto-created
/// per detected device), home/load/wireless actions, and a GitHub link.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.manager,
    required this.tipsController,
    required this.onOpenSettings,
    required this.onShowWireless,
  });

  final DeviceSessionManager manager;
  final TipsController tipsController;
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
                        Brand(onTap: manager.goHome),
                        const Gap(12),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(child: DeviceTabStrip(manager: manager)),
                              TipsHeaderPanel(controller: tipsController),
                            ],
                          ),
                        ),
                        const Gap(8),
                        HeaderAction(
                          icon: manager.isLoadingDevices
                              ? null
                              : Icons.refresh_rounded,
                          tooltip: 'Load / refresh devices',
                          busy: manager.isLoadingDevices,
                          onPressed: () => manager.refreshDevices(),
                        ),
                        HeaderAction(
                          icon: Icons.wifi_tethering_outlined,
                          tooltip: 'Wireless ADB',
                          onPressed: onShowWireless,
                        ),
                        const Gap(6),
                        const AppUpdateChip(),
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
                        const GitHubStarButton(),
                        const Gap(2),
                        HeaderAction(
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
