import 'package:flutter/material.dart';

import '../../data/app_install_conflict.dart';
import '../../services/app_install_service.dart';
import '../../session/device_session_controller.dart';
import '../../utils/log_feedback.dart';

/// Reports how an install went. A failure the device's copy of the app
/// caused (a different signing key, a newer version) asks whether to
/// uninstall that copy and install again, instead of a message the user can
/// only act on elsewhere; anything else goes to [showMessage]. [onInstalled]
/// runs once the app is on the device.
Future<void> presentAppInstallResult(
  BuildContext context, {
  required DeviceSessionController session,
  required AppInstallResult result,
  required ValueChanged<String> showMessage,
  VoidCallback? onInstalled,
}) async {
  if (result.cancelled) return;
  final conflict = result.conflict;
  final path = result.filePath;
  if (conflict == null || path == null) {
    showMessage(formatAppInstallMessage(result));
    if (result.isSuccess) onInstalled?.call();
    return;
  }

  final replace = await showDialog<bool>(
    context: context,
    builder: (context) => InstallConflictDialog(
      conflict: conflict,
      fileName: result.fileName ?? 'this app',
      deviceName: session.device.displayName,
    ),
  );
  if (replace != true) return;

  final retry = await session.forceInstallAppFromPath(path, conflict);
  if (retry.cancelled) return;
  showMessage(formatAppInstallMessage(retry));
  if (retry.isSuccess) onInstalled?.call();
}

/// Asks whether to uninstall the app [conflict] names so [fileName] can be
/// installed, spelling out that its data goes with it. Pops true to go ahead.
class const InstallConflictDialog({
  super.key,
  required final AppInstallConflict conflict,
  required final String fileName,
  required final String deviceName,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final package = conflict.packageName;
    final cause = switch (conflict.kind) {
      AppInstallConflictKind.signature =>
        '$deviceName already has $package, signed with a different key. '
            'Android only updates an app with a build signed by the same '
            'key, so $fileName can\'t be installed over it.',
      AppInstallConflictKind.downgrade =>
        '$deviceName already has a newer version of $package. Android '
            'doesn\'t install an older version over a newer one, so '
            '$fileName can\'t be installed over it.',
    };

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: colorScheme.error),
      title: Text('Replace $package?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Text(
          '$cause\n\n'
          'Uninstall and install removes the installed app first. That '
          'permanently deletes its data on the device: sign-ins, settings, '
          'databases and any files it keeps. Back up anything you need '
          'before you continue.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep installed app'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Uninstall and install'),
        ),
      ],
    );
  }
}
