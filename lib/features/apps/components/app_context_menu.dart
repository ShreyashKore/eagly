import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps_controller.dart';
import '../data/app_info.dart';
import 'app_utility_menu.dart';

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
  utilities,
  uninstall,
}

/// Why the irreversible entries are off for a preinstalled package.
const _systemAppBlockedReason =
    'Not available for system apps — wiping or removing a preinstalled '
    'package can leave the device unusable.';

/// Right-click menu for a single [app], with options gated by what the
/// platform actually supports (see [AppsController.canLaunchApps] /
/// [AppsController.canManageAppState]). [position] is the global pointer
/// location.
///
/// **System apps** keep the reversible entries (open, force stop — a system
/// app just restarts) but the irreversible ones (clear data, uninstall) are
/// shown disabled with [_systemAppBlockedReason] as their tooltip. They are
/// disabled rather than hidden so the menu keeps the same shape for every
/// app and the reason is discoverable. The same rule governs the Utilities
/// submenu, per command — see [showAppUtilityMenu].
Future<void> showAppContextMenu(
  BuildContext context,
  Offset position, {
  required AppsController controller,
  required AppInfo app,
  required AppActions actions,
  required void Function(String message) showSnackBar,
}) async {
  final theme = Theme.of(context);
  final isSystem = app.isSystemApp;
  final hasUtilities = hasAppUtilities(controller.session);

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
        PopupMenuItem(
          value: _AppAction.clearData,
          enabled: !isSystem,
          child: _MenuRow(
            Icons.delete_sweep_outlined,
            'Clear Data…',
            blocked: isSystem,
            blockedReason: _systemAppBlockedReason,
          ),
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
      if (hasUtilities) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _AppAction.utilities,
          child: _MenuRow(
            Icons.handyman_outlined,
            'Utilities',
            trailing: Icons.chevron_right,
          ),
        ),
      ],
      const PopupMenuDivider(),
      PopupMenuItem(
        value: _AppAction.uninstall,
        enabled: !isSystem,
        child: _MenuRow(
          Icons.delete_outline,
          'Uninstall…',
          color: isSystem ? null : theme.colorScheme.error,
          blocked: isSystem,
          blockedReason: _systemAppBlockedReason,
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
      if (context.mounted) showSnackBar('Copied package name.');
    case _AppAction.utilities:
      await showAppUtilityMenu(
        context,
        position,
        session: controller.session,
        app: app,
        showSnackBar: showSnackBar,
      );
    case _AppAction.uninstall:
      actions.onUninstall(app);
  }
}

RelativeRect _positionFrom(Offset globalPosition) => RelativeRect.fromLTRB(
  globalPosition.dx,
  globalPosition.dy,
  globalPosition.dx,
  globalPosition.dy,
);

class _MenuRow extends StatelessWidget {
  const _MenuRow(
    this.icon,
    this.label, {
    this.color,
    this.trailing,
    this.blocked = false,
    this.blockedReason,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final IconData? trailing;

  /// Renders the row as unavailable and explains why on hover.
  final bool blocked;
  final String? blockedReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = blocked
        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : color;

    final row = Row(
      children: [
        Icon(icon, size: 16, color: foreground),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: foreground == null ? null : TextStyle(color: foreground),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (blocked)
          Icon(Icons.lock_outline, size: 14, color: foreground)
        else if (trailing != null)
          Icon(trailing, size: 16, color: theme.colorScheme.onSurfaceVariant),
      ],
    );

    if (!blocked || blockedReason == null) return row;
    return Tooltip(
      message: blockedReason!,
      waitDuration: const Duration(milliseconds: 400),
      child: row,
    );
  }
}
