import 'package:flutter/material.dart';

import '../../presentation/components/feature_view.dart';
import 'components/mirror_control_strip.dart';
import 'components/pane_body.dart';
import 'components/quality_button.dart';
import 'mirror_controller.dart';

/// Screen-mirror feature pane. Renders the live texture + controls, driven by a
/// [MirrorController]. [onClose] hides the pane (handled by the device screen).
class MirrorFeatureView extends FeatureView {
  const MirrorFeatureView({
    super.key,
    required this.controller,
    required VoidCallback onClose,
  }) : super(onClose: onClose);

  final MirrorController controller;

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
          IconButton(
            tooltip: controller.isScreenMirrorRunning
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
            icon: Icon(
              controller.isScreenMirrorRunning
                  ? Icons.stop_circle_outlined
                  : Icons.play_arrow,
            ),
          ),
          QualityButton(controller: controller),
        ],
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
