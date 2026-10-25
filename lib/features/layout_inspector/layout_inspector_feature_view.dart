import 'package:flutter/material.dart';

import '../../presentation/components/centered_state_message.dart';
import '../../presentation/components/feature_view.dart';
import '../../presentation/components/notice_banner.dart';
import '../../presentation/components/overflow_toolbar.dart';
import '../../presentation/theme/app_theme.dart';
import 'components/layout_node_details.dart';
import 'components/layout_screen_canvas.dart';
import 'components/layout_tree_view.dart';
import 'layout_inspector_controller.dart';

/// The Layout pane: the device's screen as a tree of nodes, beside the
/// screenshot it was read from (docs/LAYOUT_INSPECTOR.md).
class const LayoutInspectorFeatureView({
  super.key,
  required final LayoutInspectorController controller,
  required VoidCallback onClose,
}) extends FeatureView {
  this : super(onClose: onClose);

  @override
  State<LayoutInspectorFeatureView> createState() =>
      _LayoutInspectorFeatureViewState();
}

class _LayoutInspectorFeatureViewState
    extends FeatureViewState<LayoutInspectorFeatureView> {
  LayoutInspectorController get controller => widget.controller;

  @override
  Listenable get listenable => controller;

  @override
  Widget buildContent(BuildContext context) {
    final capturing = controller.isCapturing;
    final canCapture = controller.isSupported && controller.isConnected;
    return FeaturePane(
      header: FeatureViewHeader(
        title: 'Layout',
        closeTooltip: 'Close layout inspector',
        onClose: widget.onClose,
        actions: [
          ToolbarAction(
            icon: Icons.refresh,
            label: 'Capture',
            tooltip: 'Capture the screen again',
            onPressed: canCapture && !controller.live
                ? controller.capture
                : null,
            busy: capturing && !controller.live,
          ),
          ToolbarAction(
            icon: Icons.sensors,
            label: 'Live',
            tooltip: controller.live
                ? 'Stop following the screen'
                : 'Follow the screen: capture again whenever it changes',
            isActive: controller.live,
            onPressed: controller.canGoLive || controller.live
                ? controller.toggleLive
                : null,
          ),
          ToolbarAction(
            icon: Icons.border_all,
            label: 'All bounds',
            tooltip: controller.showAllBounds
                ? 'Outline only the hovered and selected nodes'
                : 'Outline every node',
            isActive: controller.showAllBounds,
            onPressed: () =>
                controller.setShowAllBounds(!controller.showAllBounds),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.snapshot != null && controller.error != null)
            NoticeBanner(
              icon: Icons.error_outline,
              title: 'The last capture failed',
              message: controller.error,
              edgeToEdge: true,
            ),
          if (controller.notice case final notice?)
            NoticeBanner(
              icon: Icons.info_outline,
              title: notice,
              color: context.eaglyTheme.infoColor,
              edgeToEdge: true,
            ),
          Expanded(child: _body(context)),
        ],
      ),
      statusBar: controller.snapshot == null ? null : _statusBar(context),
    );
  }

  Widget _body(BuildContext context) {
    final snapshot = controller.snapshot;
    if (!controller.isSupported) {
      return const CenteredStateMessage(
        icon: Icons.phonelink_off_rounded,
        title: 'Android only, for now',
        description:
            'Reading an iPhone\'s screen needs WebDriverAgent or an SDK in '
            'the app; see docs/LAYOUT_INSPECTOR.md.',
      );
    }
    if (snapshot == null) {
      if (controller.isCapturing) {
        return const Center(child: CircularProgressIndicator());
      }
      if (!controller.isConnected) {
        return const CenteredStateMessage(
          icon: Icons.link_off,
          title: 'Device disconnected',
          description: 'Connect the device to inspect its screen.',
        );
      }
      return CenteredStateMessage(
        icon: Icons.error_outline_rounded,
        title: controller.error == null
            ? 'Nothing captured yet'
            : 'Could not read the screen',
        description:
            controller.error ??
            'Capture the screen to see what is on it, node by node.',
        footer: FilledButton.icon(
          onPressed: controller.capture,
          icon: const Icon(Icons.refresh),
          label: const Text('Capture'),
        ),
      );
    }

    final divider = Theme.of(context).colorScheme.outlineVariant;
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = LayoutScreenCanvas(controller: controller);
        final tree = LayoutTreeView(controller: controller);
        final details = LayoutNodeDetails(controller: controller);
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 4, child: canvas),
              Divider(height: 1, color: divider),
              Expanded(flex: 4, child: tree),
              Divider(height: 1, color: divider),
              Expanded(flex: 3, child: details),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: (constraints.maxWidth * 0.38).clamp(220.0, 460.0),
              child: canvas,
            ),
            VerticalDivider(width: 1, color: divider),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: tree),
                  Divider(height: 1, color: divider),
                  Expanded(flex: 2, child: details),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statusBar(BuildContext context) {
    final snapshot = controller.snapshot!;
    final eagly = context.eaglyTheme;
    final separator = Text(
      '  |  ',
      style: TextStyle(color: eagly.tertiaryTextColor),
    );
    final time = TimeOfDay.fromDateTime(snapshot.capturedAt).format(context);
    final seconds = snapshot.elapsed.inMilliseconds / 1000;
    return FeatureStatusBar(
      children: [
        Text('${snapshot.nodeCount} nodes'),
        separator,
        Text(
          snapshot.windows.length == 1
              ? '1 window'
              : '${snapshot.windows.length} windows',
        ),
        const Spacer(),
        if (controller.live) ...[
          Icon(Icons.circle, size: 8, color: eagly.statusLiveColor),
          const SizedBox(width: 6),
          const Text('Live'),
          separator,
        ],
        Tooltip(
          message: 'How this capture was made, and how long it took',
          child: Text(
            '${snapshot.source.label} · ${seconds.toStringAsFixed(2)} s · $time',
            style: TextStyle(color: eagly.tertiaryTextColor),
          ),
        ),
      ],
    );
  }
}
