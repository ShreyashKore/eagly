import 'package:eagly/constants/app_constants.dart';
import 'package:eagly/services/app_update_service.dart';
import 'package:eagly/services/eagly_info_service.dart';
import 'package:flutter/material.dart';
import 'package:updat/updat.dart';

import 'components/update_pill.dart';

/// A quiet header pill that surfaces app updates. It wraps [UpdatWidget] — which
/// checks the latest GitHub release once on mount — with a compact chip that
/// matches the muted header styling.
///
/// Only *actionable* states render anything: available, downloading, and
/// ready-to-install. Checking / up-to-date / dismissed / error all collapse to
/// nothing, so the header never nags on a normal or offline launch.
class AppUpdateChip extends StatelessWidget {
  const AppUpdateChip({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppUpdateService.isSupported) return const SizedBox.shrink();

    return UpdatWidget(
      appName: AppConstants.appName,
      currentVersion: EaglyInfoService.versionName,
      getLatestVersion: AppUpdateService.getLatestVersion,
      getBinaryUrl: AppUpdateService.getBinaryUrl,
      getDownloadFileLocation: AppUpdateService.getDownloadFileLocation,
      getChangelog: AppUpdateService.getChangelog,
      updateChipBuilder: _buildChip,
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required String? latestVersion,
    required String appVersion,
    required UpdatStatus status,
    required void Function() checkForUpdate,
    required void Function() openDialog,
    required void Function() startUpdate,
    required Future<void> Function() launchInstaller,
    required void Function() dismissUpdate,
  }) {
    switch (status) {
      case UpdatStatus.available:
      case UpdatStatus.availableWithChangelog:
        return UpdatePill(
          icon: Icons.system_update_alt_rounded,
          label: 'Update',
          tooltip: latestVersion == null
              ? 'A new version is available'
              : 'Update available — v$latestVersion',
          onTap: openDialog,
        );
      case UpdatStatus.downloading:
        return const UpdatePill(
          busy: true,
          label: 'Updating…',
          tooltip: 'Downloading the update…',
        );
      case UpdatStatus.readyToInstall:
        return UpdatePill(
          icon: Icons.check_circle_rounded,
          label: 'Restart',
          tooltip: 'Quit Eagly and open the downloaded installer',
          onTap: latestVersion == null
              ? null
              : () => _confirmQuitAndInstall(context, latestVersion),
        );
      case UpdatStatus.error:
      case UpdatStatus.checking:
      case UpdatStatus.upToDate:
      case UpdatStatus.idle:
      case UpdatStatus.dismissed:
        return const SizedBox.shrink();
    }
  }

  Future<void> _confirmQuitAndInstall(
    BuildContext context,
    String latestVersion,
  ) async {
    final shouldInstall = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quit Eagly to install update?'),
        content: Text(
          'Eagly will quit, then open the downloaded v$latestVersion installer. '
          'Save any unfinished work before continuing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Quit and install'),
          ),
        ],
      ),
    );
    if (shouldInstall != true || !context.mounted) return;

    try {
      await AppUpdateService.quitAndOpenInstaller(latestVersion);
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start the installer: $error')),
      );
    }
  }
}
