import 'package:flutter/material.dart';

import '../../data/device.dart';
import '../../presentation/components/feature_view.dart';
import '../../presentation/components/overflow_toolbar.dart';
import 'components/ios_capture_notice_dialog.dart';
import 'components/mirror_control_strip.dart';
import 'components/pane_body.dart';
import 'components/quality_button.dart';
import 'components/recording_badge.dart';
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

  /// Whether the capture notice is on screen, so it is shown only once.
  bool _showingNotice = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(_showNoticeWhenAsked);
    // A start from opening the pane can ask before this view exists.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNoticeWhenAsked());
  }

  @override
  void didUpdateWidget(MirrorFeatureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, controller)) return;
    oldWidget.controller.removeListener(_showNoticeWhenAsked);
    controller.addListener(_showNoticeWhenAsked);
  }

  @override
  void dispose() {
    controller.removeListener(_showNoticeWhenAsked);
    super.dispose();
  }

  Future<void> _showNoticeWhenAsked() async {
    if (!mounted || _showingNotice || !controller.isCaptureNoticePending) {
      return;
    }
    final asking = controller;
    _showingNotice = true;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => const IosCaptureNoticeDialog(),
    );
    _showingNotice = false;
    asking.answerCaptureNotice(proceed: proceed ?? false);
  }

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
        // QuickTime's route and CoreDevice offer no quality settings.
        trailing: [
          if (controller.device is AndroidDevice)
            QualityButton(controller: controller),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    alignment: Alignment.center,
                    padding: EdgeInsets.all(8),
                    child: PaneBody(controller: controller),
                  ),
                ),
                if (controller.recordingClock case final clock?)
                  Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: RecordingBadge(
                        startedAt: clock.startedAt,
                        timeLimit: clock.timeLimit,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          MirrorControlStrip(controller: controller),
        ],
      ),
    );
  }
}
