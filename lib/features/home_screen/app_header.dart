import 'package:eagly/features/home_screen/components/context_menu_helper.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:window_manager/window_manager.dart';

import '../../presentation/theme/app_theme.dart';
import '../../session/device_session_manager.dart';
import '../updates/update_chip.dart';
import '../tips/tips_controller.dart';
import '../tips/tips_header_panel.dart';
import 'components/brand.dart';
import 'components/device_tab_strip.dart';
import 'components/github_star_button.dart';
import 'components/header_action.dart';
import 'components/save_layout_button.dart';
import 'window_controls.dart';

/// Top app header: logo + name, the horizontal device-tab strip (auto-created
/// per detected device), save-layout/load/wireless/emulator actions, and a
/// GitHub link.
class const AppHeader({
  super.key,
  required final DeviceSessionManager manager,
  required final TipsController tipsController,
  required final VoidCallback onOpenSettings,
  required final VoidCallback onShowWireless,
  required final VoidCallback onShowEmulators,
  required final VoidCallback onSaveLayout,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        return Container(
          height: context.scaled(52),
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
                    onShowEmulators: onShowEmulators,
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
                        SaveLayoutButton(
                          session: manager.selected,
                          onSave: onSaveLayout,
                        ),
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
                        HeaderAction(
                          icon: Icons.smartphone_outlined,
                          tooltip: 'Android emulators',
                          onPressed: onShowEmulators,
                        ),
                        const Gap(6),
                        const AppUpdateChip(),
                        const Gap(4),
                        SizedBox(
                          height: context.scaled(22),
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
