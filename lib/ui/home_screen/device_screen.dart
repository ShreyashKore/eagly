import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/logs/log_feature_view.dart';
import '../../features/mirror/mirror_controller.dart';
import '../../features/mirror/mirror_feature_view.dart';
import '../../session/device_session_controller.dart';
import 'feature_rail.dart';

/// The screen shown for the selected device tab: the feature rail on the far
/// left, then the open feature panes (Logs always, Mirror alongside when open).
class DeviceScreen extends StatelessWidget {
  const DeviceScreen({
    super.key,
    required this.session,
    required this.appMemoryBytesListenable,
  });

  final DeviceSessionController session;
  final ValueListenable<int> appMemoryBytesListenable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(color: theme.colorScheme.surface),
      child: Row(
        children: [
          FeatureRail(session: session),
          Expanded(
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => _buildContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final logPane = LogFeatureView(
      controller: session.logController,
      session: session,
      appMemoryBytesListenable: appMemoryBytesListenable,
    );

    if (!session.isMirrorOpen) {
      return logPane;
    }

    final mirror = session.mirrorController;
    return ListenableBuilder(
      listenable: mirror,
      builder: (context, _) {
        return Row(
          children: [
            SizedBox(
              width: mirror.paneWidth,
              child: MirrorFeatureView(
                controller: mirror,
                onClose: session.closeMirror,
              ),
            ),
            _MirrorPaneResizeHandle(mirror: mirror),
            Expanded(child: logPane),
          ],
        );
      },
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
