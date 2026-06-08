import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/crash_reports/crash_report_controller.dart';
import '../../features/crash_reports/crash_report_feature_view.dart';
import '../../features/logs/log_feature_view.dart';
import '../../features/mirror/mirror_controller.dart';
import '../../features/mirror/mirror_feature_view.dart';
import '../../session/device_session_controller.dart';
import '../../utils/log_feedback.dart';
import '../components/animation_utils.dart';
import 'feature_rail.dart';

/// The screen shown for the selected device tab: the feature rail on the far
/// left, then the open feature panes (Logs always, Mirror alongside when open).
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({
    super.key,
    required this.session,
    required this.appMemoryBytesListenable,
  });

  final DeviceSessionController session;
  final ValueListenable<int> appMemoryBytesListenable;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(color: theme.colorScheme.surface),
      child: Row(
        children: [
          FeatureRail(session: widget.session, onInstall: _handleInstallApp),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.session,
              builder: (context, _) => _buildContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final logPane = LogFeatureView(
      logManager: widget.session.logSessionManager,
      session: widget.session,
      appMemoryBytesListenable: widget.appMemoryBytesListenable,
    );

    final mirror = widget.session.mirrorController;
    final crashReports = widget.session.crashReportController;

    return Row(
      children: [
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
        Expanded(child: logPane),
      ],
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
