import 'package:flutter/material.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/theme/app_theme.dart';
import '../../../session/device_session_controller.dart';

/// A quiet "Save layout" button for the header: saves the selected device's
/// open panes as the layout every device opens with. Once a layout is saved,
/// a reset button sits inside the same outline, set apart by a divider and
/// padding, and puts the panes back the way the saved layout has them.
///
/// Draws nothing unless [session] has panes open to save, and nothing while
/// they already are the saved layout — moving, resizing, opening or closing
/// a pane brings it back.
class const SaveLayoutButton({
  super.key,
  required final DeviceSessionController? session,
  required final VoidCallback onSave,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = this.session;
    if (session == null) return const SizedBox.shrink();
    return ListenableBuilder(
      // The session hears about panes opening and closing; moves and
      // divider drags only reach the layout's own controller.
      listenable: Listenable.merge([session, session.workspaceLayout.panels]),
      builder: (context, _) {
        if (!session.canSaveLayout || session.matchesSavedLayout) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final outline = theme.colorScheme.outlineVariant;
        final radius = BorderRadius.circular(context.scaled(8));
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: outline),
            borderRadius: radius,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: SizedBox(
              height: context.scaled(34),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Tooltip(
                    message:
                        'Open every device with these panes, arranged like '
                        'this',
                    child: TextButton(
                      onPressed: onSave,
                      style: TextButton.styleFrom(
                        foregroundColor: context.eaglyTheme.secondaryTextColor,
                        textStyle: theme.textTheme.labelMedium,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        shape: const RoundedRectangleBorder(),
                      ),
                      child: const Text('Save layout'),
                    ),
                  ),
                  if (session.canResetLayout) ...[
                    VerticalDivider(width: 1, thickness: 1, color: outline),
                    // Wider than the icon needs, so a reset aimed a little
                    // off doesn't land on Save layout.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Center(
                        child: AppIconButton(
                          icon: Icons.restart_alt_rounded,
                          iconSize: 16,
                          tooltip: 'Reset to the saved layout',
                          onPressed: session.resetLayout,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
