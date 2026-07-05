import 'package:eagly/constants/app_constants.dart';
import 'package:eagly/services/app_update_service.dart';
import 'package:eagly/services/eagly_info_service.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:updat/updat.dart';

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
        return _UpdatePill(
          icon: Icons.system_update_alt_rounded,
          label: 'Update',
          tooltip: latestVersion == null
              ? 'A new version is available'
              : 'Update available — v$latestVersion',
          onTap: openDialog,
        );
      case UpdatStatus.downloading:
        return const _UpdatePill(
          busy: true,
          label: 'Updating…',
          tooltip: 'Downloading the update…',
        );
      case UpdatStatus.readyToInstall:
        return _UpdatePill(
          icon: Icons.check_circle_rounded,
          label: 'Install',
          tooltip: 'Open the downloaded installer',
          onTap: () => launchInstaller(),
        );
      case UpdatStatus.error:
      case UpdatStatus.checking:
      case UpdatStatus.upToDate:
      case UpdatStatus.idle:
      case UpdatStatus.dismissed:
        return const SizedBox.shrink();
    }
  }
}

/// Header-styled accent pill mirroring the other header actions, tinted with the
/// primary color so an available update reads as a gentle call to action.
class _UpdatePill extends StatefulWidget {
  const _UpdatePill({
    required this.label,
    required this.tooltip,
    this.icon,
    this.busy = false,
    this.onTap,
  });

  final String label;
  final String tooltip;
  final IconData? icon;
  final bool busy;
  final VoidCallback? onTap;

  @override
  State<_UpdatePill> createState() => _UpdatePillState();
}

class _UpdatePillState extends State<_UpdatePill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onPrimaryContainer;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(
                alpha: _hovered && widget.onTap != null ? 1 : 0.75,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.busy)
                  SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                else if (widget.icon != null)
                  Icon(widget.icon, size: 15, color: foreground),
                const Gap(6),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
