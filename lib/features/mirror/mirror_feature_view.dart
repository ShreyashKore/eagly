import 'package:flutter/material.dart';

import '../../presentation/components/feature_view.dart';
import '../../presentation/components/overflow_toolbar.dart';
import 'components/mirror_control_strip.dart';
import 'components/pane_body.dart';
import 'components/quality_button.dart';
import 'mirror_controller.dart';

/// Screen-mirror feature pane. Renders the live texture + controls, driven by a
/// [MirrorController]. [onClose] hides the pane (handled by the device screen).
class const MirrorFeatureView({
  super.key,
  required final MirrorController controller,
  required VoidCallback onClose,
}) extends FeatureView {
  this : super(onClose: onClose);

  @override
  State<MirrorFeatureView> createState() => _MirrorFeatureViewState();
}

class _MirrorFeatureViewState extends FeatureViewState<MirrorFeatureView> {
  MirrorController get controller => widget.controller;

  @override
  Listenable get listenable => controller;

  @override
  Widget buildContent(BuildContext context) {
    return FeaturePane(
      header: FeatureViewHeader(
        title: 'Screen mirror',
        closeTooltip: 'Close mirror pane',
        onClose: widget.onClose,
        actions: [
          ToolbarAction(
            icon: controller.isScreenMirrorRunning
                ? Icons.stop_circle_outlined
                : Icons.play_arrow,
            label: controller.isScreenMirrorRunning
                ? 'Stop mirror'
                : 'Start mirror',
            onPressed: controller.canStart || controller.isScreenMirrorRunning
                ? () {
                    if (controller.isScreenMirrorRunning) {
                      controller.stop();
                    } else {
                      controller.start();
                    }
                  }
                : null,
          ),
        ],
        trailing: [QualityButton(controller: controller)],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(child: PaneBody(controller: controller)),
          ),
          MirrorControlStrip(controller: controller),
        ],
      ),
    );
  }
}
