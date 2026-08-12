import 'package:flutter/material.dart';

import '../tips_controller.dart';
import 'confirm_disable_tips.dart';
import 'menu_row.dart';

/// The three-dot options menu for the tips panel.
class TipsMenuButton extends StatelessWidget {
  const TipsMenuButton({super.key, required this.controller});

  final TipsController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TipsMenuAction>(
      tooltip: 'Tip options',
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      iconSize: 16,
      splashRadius: 16,
      constraints: const BoxConstraints(minWidth: 200),
      icon: Icon(
        Icons.more_vert_rounded,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _TipsMenuAction.another,
          child: MenuRow(Icons.refresh_rounded, 'Show another tip'),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _TipsMenuAction.disable,
          child: MenuRow(Icons.visibility_off_outlined, 'Turn off tips…'),
        ),
      ],
      onSelected: (action) async {
        switch (action) {
          case _TipsMenuAction.another:
            controller.showNextTip();
          case _TipsMenuAction.disable:
            final confirmed = await confirmDisableTips(context);
            if (confirmed) controller.disablePermanently();
        }
      },
    );
  }
}

enum _TipsMenuAction { another, disable }
