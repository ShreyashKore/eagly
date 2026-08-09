import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../crash_reports/crash_report_controller.dart';
import '../crash_reports/crash_report_feature_view.dart';
import '../device_home/device_home_feature_view.dart';
import '../file_manager/file_manager_controller.dart';
import '../file_manager/file_manager_feature_view.dart';
import '../logs/log_feature_view.dart';
import '../mirror/mirror_controller.dart';
import '../mirror/mirror_feature_view.dart';
import '../../data/device.dart';
import '../../session/device_session_controller.dart';
import '../../utils/log_feedback.dart';
import '../../features/logs/log_controller.dart';
import '../../presentation/components/animation_utils.dart';
import 'feature_rail.dart';

/// The screen shown for the selected device tab: the feature rail on the far
/// left, then the open feature panes (Logs always, Mirror alongside when open).
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({
    super.key,
    required this.session,
    required this.appMemoryBytesListenable,
    required this.onOpenSettings,
  });

  final DeviceSessionController session;
  final ValueListenable<int> appMemoryBytesListenable;
  final VoidCallback onOpenSettings;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  bool _isDragOver = false;

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleInstallApp() async {
    final result = await widget.session.installAppFromPicker();
    if (!mounted || result.cancelled) return;
    _showSnackBar(formatAppInstallMessage(result));
  }

  Future<void> _handleDrop(DropDoneDetails detail) async {
    if (mounted) setState(() => _isDragOver = false);
    final paths = detail.files
        .map((file) => file.path)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) return;

    final result = await widget.session.handleDroppedPaths(paths);
    if (!mounted || result == null) return;
    final message = result.message;
    if (message != null) _showSnackBar(message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The device-less "Imported Logs" workspace has no device features (mirror,
    // files, install, …) — show just the log viewer, full-width.
    if (widget.session.isImportedWorkspace) {
      return DecoratedBox(
        decoration: BoxDecoration(color: theme.colorScheme.surface),
        child: LogFeatureView(
          logManager: widget.session.logSessionManager,
          session: widget.session,
          appMemoryBytesListenable: widget.appMemoryBytesListenable,
        ),
      );
    }

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragOver = true),
      onDragExited: (_) => setState(() => _isDragOver = false),
      onDragDone: _handleDrop,
      child: DecoratedBox(
        decoration: BoxDecoration(color: theme.colorScheme.surface),
        child: Stack(
          children: [
            Row(
              children: [
                FeatureRail(
                  session: widget.session,
                  onInstall: _handleInstallApp,
                  onOpenSettings: widget.onOpenSettings,
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: widget.session,
                    builder: (context, _) => _buildContent(context),
                  ),
                ),
              ],
            ),
            if (_isDragOver)
              Positioned.fill(child: _DropOverlay(session: widget.session)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final device = widget.session.device;
    final guidance = _guidanceForDevice(device);
    if (guidance != null) {
      return guidance;
    }

    final homePane = DeviceHomeFeatureView(
      session: widget.session,
      homeController: widget.session.homeController,
      onShowSnackBar: _showSnackBar,
    );

    final logController = widget.session.logSessionManager.selectedTab;
    final mirror = widget.session.mirrorController;
    final crashReports = widget.session.crashReportController;
    final files = widget.session.fileManagerController;

    return Row(
      children: [
        if (logController != null)
          ListenableBuilder(
            listenable: logController,
            builder: (context, _) {
              return AnimatedSection(
                visible: widget.session.isLogsOpen,
                child: Row(
                  children: [
                    SizedBox(
                      width: logController.paneWidth,
                      child: LogFeatureView(
                        logManager: widget.session.logSessionManager,
                        session: widget.session,
                        appMemoryBytesListenable:
                            widget.appMemoryBytesListenable,
                      ),
                    ),
                    _LogPaneResizeHandle(controller: logController),
                  ],
                ),
              );
            },
          ),
        ListenableBuilder(
          listenable: mirror,
          builder: (context, _) {
            return AnimatedSection(
              visible: widget.session.isMirrorOpen,
              child: Row(
                children: [
                  SizedBox(
                    width: mirror.paneWidth,
                    child: MirrorFeatureView(
                      controller: mirror,
                      onClose: widget.session.closeMirror,
                    ),
                  ),
                  _MirrorPaneResizeHandle(mirror: mirror),
                ],
              ),
            );
          },
        ),
        ListenableBuilder(
          listenable: crashReports,
          builder: (context, _) {
            return AnimatedSection(
              visible: widget.session.isCrashReportsOpen,
              child: Row(
                children: [
                  SizedBox(
                    width: crashReports.paneWidth,
                    child: CrashReportFeatureView(
                      controller: crashReports,
                      onClose: widget.session.closeCrashReports,
                    ),
                  ),
                  _CrashPaneResizeHandle(controller: crashReports),
                ],
              ),
            );
          },
        ),
        ListenableBuilder(
          listenable: files,
          builder: (context, _) {
            return AnimatedSection(
              visible: widget.session.isFilesOpen,
              child: Row(
                children: [
                  SizedBox(
                    width: files.paneWidth,
                    child: FileManagerFeatureView(
                      controller: files,
                      onClose: widget.session.closeFiles,
                    ),
                  ),
                  _FilePaneResizeHandle(controller: files),
                ],
              ),
            );
          },
        ),
        Expanded(child: homePane),
      ],
    );
  }
}

/// Returns a guidance widget when [device] needs user action before it can be
/// used, or null if the device is ready.
Widget? _guidanceForDevice(Device device) {
  if (device is AndroidDevice) {
    if (device.status == 'unauthorized') {
      return const _AndroidUnauthorizedGuidance();
    }
  } else if (device is IosDevice) {
    return switch (device.status) {
      'unpaired' => const _IosGuidance(
        icon: Icons.phonelink_lock_outlined,
        title: 'Trust This Computer',
        message:
            'Your iPhone is asking whether to trust this Mac.\n'
            'Pick up your device and tap "Trust" on the dialog that appeared.',
        steps: [
          'Unlock your iPhone',
          'Tap "Trust" on the "Trust This Computer?" alert',
          'Enter your iPhone passcode if prompted',
        ],
      ),
      'locked' => const _IosGuidance(
        icon: Icons.lock_outline,
        title: 'iPhone Locked',
        message:
            'Your iPhone is locked. Unlock it and trust this computer to continue.',
        steps: [
          'Unlock your iPhone with Face ID, Touch ID, or passcode',
          'If prompted, tap "Trust" on the "Trust This Computer?" alert',
        ],
      ),
      'unavailable' => const _IosGuidance(
        icon: Icons.usb_off_outlined,
        title: 'Device Unavailable',
        message: 'Could not communicate with your iPhone. Try the steps below.',
        steps: [
          'Unlock your iPhone',
          'Disconnect and reconnect the USB cable',
          'If prompted, tap "Trust This Computer"',
        ],
      ),
      _ => null,
    };
  }
  return null;
}

class _AndroidUnauthorizedGuidance extends StatelessWidget {
  const _AndroidUnauthorizedGuidance();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.usb, size: 32, color: theme.colorScheme.primary),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      'Allow USB Debugging',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(12),
              Text(
                'Your Android device is asking for permission to allow USB '
                'debugging from this computer.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(20),
              _StepList(
                steps: const [
                  'Check your Android device screen',
                  'Tap "Allow" on the "Allow USB debugging?" dialog',
                  'Optionally check "Always allow from this computer"',
                  'If the dialog has dismissed, disconnect and reconnect '
                      'the USB cable',
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IosGuidance extends StatelessWidget {
  const _IosGuidance({
    required this.icon,
    required this.title,
    required this.message,
    required this.steps,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 32, color: theme.colorScheme.primary),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(12),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(20),
              _StepList(steps: steps),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        for (final (index, step) in steps.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Gap(10),
              Expanded(child: Text(step, style: theme.textTheme.bodyMedium)),
            ],
          ),
      ],
    );
  }
}

/// Full-screen hint shown while files are dragged over the device screen.
class _DropOverlay extends StatelessWidget {
  const _DropOverlay({required this.session});

  final DeviceSessionController session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installable = session.platform == DevicePlatform.android
        ? 'APK'
        : 'IPA / .app';
    return ColoredBox(
      color: theme.colorScheme.scrim.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.primary, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.download_for_offline_outlined,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const Gap(12),
              Text(
                'Drop to install or copy to ${session.device.displayName}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Gap(4),
              Text(
                '$installable installs the app; other files are copied to the device.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin draggable divider that resizes the crash-report pane horizontally.
class _CrashPaneResizeHandle extends StatelessWidget {
  const _CrashPaneResizeHandle({required this.controller});

  final CrashReportController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) =>
            controller.setPaneWidth(controller.paneWidth + details.delta.dx),
        child: Container(
          width: 8,
          height: double.infinity,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
          child: Center(
            child: Container(
              width: 2,
              height: 24,
              color: theme.colorScheme.outline.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin draggable divider that resizes the file-manager pane horizontally.
class _FilePaneResizeHandle extends StatelessWidget {
  const _FilePaneResizeHandle({required this.controller});

  final FileManagerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) =>
            controller.setPaneWidth(controller.paneWidth + details.delta.dx),
        child: Container(
          width: 8,
          height: double.infinity,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
          child: Center(
            child: Container(
              width: 2,
              height: 24,
              color: theme.colorScheme.outline.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin draggable divider that resizes the screen-mirror pane horizontally.
class _MirrorPaneResizeHandle extends StatelessWidget {
  const _MirrorPaneResizeHandle({required this.mirror});

  final MirrorController mirror;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) =>
            mirror.setPaneWidth(mirror.paneWidth + details.delta.dx),
        child: Container(
          width: 8,
          height: double.infinity,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
          child: Center(
            child: Container(
              width: 2,
              height: 24,
              color: theme.colorScheme.outline.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin draggable divider that resizes the log-viewer pane horizontally.
class _LogPaneResizeHandle extends StatelessWidget {
  const _LogPaneResizeHandle({required this.controller});

  final LogController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) =>
            controller.setPaneWidth(controller.paneWidth + details.delta.dx),
        child: Container(
          width: 8,
          height: double.infinity,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
          child: Center(
            child: Container(
              width: 2,
              height: 24,
              color: theme.colorScheme.outline.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}
