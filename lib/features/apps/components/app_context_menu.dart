import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps_controller.dart';
import '../data/app_info.dart';

/// The app actions that need dialogs or snackbars. Owned by the feature view
/// and invoked from the context menu, so the menu helper stays free of
/// dialog logic.
class AppActions {
  const AppActions({
    required this.onLaunch,
    required this.onForceStop,
    required this.onClearData,
    required this.onAppInfo,
    required this.onViewLogs,
    required this.onUninstall,
  });

  final void Function(AppInfo app) onLaunch;
  final void Function(AppInfo app) onForceStop;
  final void Function(AppInfo app) onClearData;
  final void Function(AppInfo app) onAppInfo;
  final void Function(AppInfo app) onViewLogs;
  final void Function(AppInfo app) onUninstall;
}

enum _AppAction {
  open,
  forceStop,
  clearData,
  appInfo,
  viewLogs,
  copyPackageName,
  uninstall,
}

/// Right-click menu for a single [app], with options gated by what the
/// platform actually supports (see [AppsController.canLaunchApps] /
/// [AppsController.canManageAppState]). [position] is the global pointer
/// location.
Future<void> showAppContextMenu(
  BuildContext context,
  Offset position, {
  required AppsController controller,
  required AppInfo app,
  required AppActions actions,
}) async {
  final theme = Theme.of(context);
  final result = await showMenu<_AppAction>(
    context: context,
    position: _positionFrom(position),
    items: [
      if (controller.canLaunchApps)
        const PopupMenuItem(
          value: _AppAction.open,
          child: _MenuRow(Icons.open_in_new, 'Open'),
        ),
      if (controller.canManageAppState) ...[
        const PopupMenuItem(
          value: _AppAction.forceStop,
          child: _MenuRow(Icons.stop_circle_outlined, 'Force Stop'),
        ),
        const PopupMenuItem(
          value: _AppAction.clearData,
          child: _MenuRow(Icons.delete_sweep_outlined, 'Clear Data…'),
        ),
        const PopupMenuItem(
          value: _AppAction.appInfo,
          child: _MenuRow(Icons.info_outline, 'App Info'),
        ),
      ],
      const PopupMenuItem(
        value: _AppAction.viewLogs,
        child: _MenuRow(Icons.article_outlined, 'View Logs'),
      ),
      const PopupMenuItem(
        value: _AppAction.copyPackageName,
        child: _MenuRow(Icons.badge_outlined, 'Copy Package Name'),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: _AppAction.uninstall,
        child: _MenuRow(
          Icons.delete_outline,
          'Uninstall…',
          color: theme.colorScheme.error,
        ),
      ),
    ],
  );

  if (result == null || !context.mounted) return;
  switch (result) {
    case _AppAction.open:
      actions.onLaunch(app);
    case _AppAction.forceStop:
      actions.onForceStop(app);
    case _AppAction.clearData:
      actions.onClearData(app);
    case _AppAction.appInfo:
      actions.onAppInfo(app);
    case _AppAction.viewLogs:
      actions.onViewLogs(app);
    case _AppAction.copyPackageName:
      await Clipboard.setData(ClipboardData(text: app.packageName));
      if (context.mounted) _toast(context, 'Copied package name.');
    case _AppAction.uninstall:
      actions.onUninstall(app);
  }
}

void _toast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

RelativeRect _positionFrom(Offset globalPosition) => RelativeRect.fromLTRB(
  globalPosition.dx,
  globalPosition.dy,
  globalPosition.dx,
  globalPosition.dy,
);

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(label, style: color == null ? null : TextStyle(color: color)),
      ],
    );
  }
}
