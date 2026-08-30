import 'package:flutter/material.dart';

import '../../../session/device_session_controller.dart';
import '../../utilities/data/utility_catalog.dart';
import '../../utilities/data/utility_command.dart';
import '../../utilities/utility_runner.dart';
import '../data/app_info.dart';

/// The Utilities bridge for the Apps pane.
///
/// Several catalog commands are aimed at one app and would otherwise make the
/// user copy a package name out of this pane and paste it into the Utilities
/// pane. Any command that declares a [UtilityCommand.packageParamKey] is
/// offered here instead, pre-filled with the app that was right-clicked — so
/// growing the catalog grows this menu for free, exactly like the Utilities
/// pane itself.
///
/// **System apps.** A preinstalled package is part of the OS: revoking its
/// permissions or hammering it with random input can leave the device
/// unusable and cannot be undone from here. Only commands that opt in via
/// [UtilityCommand.systemAppSafe] — the read-only ones — are offered for a
/// system app; the rest are listed but disabled, with the reason spelled out,
/// rather than hidden, so the menu doesn't silently change shape between apps.

/// The app-targeted commands this device supports, in catalog order.
List<UtilityCommand> appUtilityCommandsFor(DeviceSessionController session) => [
  for (final group in utilityCatalog)
    for (final command in group.commands)
      if (command.targetsApp && command.supports(session.device)) command,
];

/// Whether the Apps pane should offer a "Utilities" entry at all.
bool hasAppUtilities(DeviceSessionController session) =>
    appUtilityCommandsFor(session).isNotEmpty;

/// Shows the app-targeted utilities for [app] at [position] and runs the
/// chosen one, opening the Utilities pane first so its parameters dialog and
/// result panel are where the user expects them.
Future<void> showAppUtilityMenu(
  BuildContext context,
  Offset position, {
  required DeviceSessionController session,
  required AppInfo app,
  required void Function(String message) showSnackBar,
}) async {
  final commands = appUtilityCommandsFor(session);
  if (commands.isEmpty) return;

  final theme = Theme.of(context);
  final blockedReason =
      'Not available for system apps — it could leave the device unusable.';

  final picked = await showMenu<UtilityCommand>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: [
      PopupMenuItem<UtilityCommand>(
        enabled: false,
        height: 30,
        child: Text(
          app.packageName,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFamily: 'monospace',
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const PopupMenuDivider(),
      for (final command in commands)
        _utilityItem(
          context,
          command: command,
          allowed: command.allowsApp(isSystemApp: app.isSystemApp),
          blockedReason: blockedReason,
        ),
    ],
  );

  if (picked == null || !context.mounted) return;

  session.openUtilities();
  await runUtilityCommand(
    context,
    controller: session.utilitiesController,
    command: picked,
    showSnackBar: showSnackBar,
    initialValues: {picked.packageParamKey!: app.packageName},
  );
}

PopupMenuItem<UtilityCommand> _utilityItem(
  BuildContext context, {
  required UtilityCommand command,
  required bool allowed,
  required String blockedReason,
}) {
  final theme = Theme.of(context);
  final destructive = command.isDestructive;
  final foreground = !allowed
      ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
      : destructive
      ? theme.colorScheme.error
      : null;

  final row = Row(
    children: [
      Icon(command.icon, size: 16, color: foreground),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          command.needsInput ? '${command.label}…' : command.label,
          style: TextStyle(color: foreground),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (!allowed) ...[
        const SizedBox(width: 8),
        Icon(Icons.lock_outline, size: 14, color: foreground),
      ],
    ],
  );

  return PopupMenuItem<UtilityCommand>(
    value: command,
    enabled: allowed,
    child: Tooltip(
      message: allowed ? command.description : blockedReason,
      waitDuration: const Duration(milliseconds: 400),
      child: row,
    ),
  );
}
