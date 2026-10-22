import 'package:flutter/material.dart';

import '../../../presentation/theme/app_theme.dart';
import '../../../session/device_session_controller.dart';

/// A quiet "Save layout" text button for the header: saves the selected
/// device's open panes as the layout every device opens with. Draws nothing
/// unless [session] has panes open to save, and nothing while they already
/// are the saved layout — moving, resizing, opening or closing a pane brings
/// it back.
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
        return Tooltip(
          message: 'Open every device with these panes, arranged like this',
          child: TextButton(
            onPressed: onSave,
            style: TextButton.styleFrom(
              foregroundColor: context.eaglyTheme.secondaryTextColor,
              textStyle: theme.textTheme.labelMedium,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size(0, context.scaled(28)),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Save layout'),
          ),
        );
      },
    );
  }
}
