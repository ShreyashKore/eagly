import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../data/device.dart';
import '../../../presentation/components/delayed_reveal.dart';
import '../../../presentation/components/hint_note.dart';
import '../../flutter_scrcpy/flutter_scrcpy.dart';
import '../mirror_controller.dart';
import 'recording_glow.dart';
import '../services/ios_screen_capture.dart';
import 'ios_mirror_surface.dart';

class const PaneBody({super.key, required final MirrorController controller})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = controller.device;
    final session = controller.screenMirrorSession;
    final ios = controller.iosMirror;
    final isIos = device is IosDevice;

    if (ios != null && controller.isScreenMirrorRunning) {
      return IosMirrorSurface(controller: controller, mirror: ios);
    }

    // Display the live texture once the mirror is running.
    if (session != null && controller.isScreenMirrorRunning) {
      final aspectRatio = session.height > 0
          ? session.width / session.height
          : 9 / 16;
      return ScrcpyView(
        key: controller.surfaceKey,
        textureId: session.textureId,
        aspectRatio: aspectRatio,
        onTouch: controller.handleTouch,
        focusNode: controller.keyboardFocusNode,
        onKey: controller.handleKeyEvent,
        onFocusChange: controller.handleKeyboardFocusChange,
        overlay: recordingGlow(controller),
      );
    }

    final (
      :icon,
      :title,
      :description,
    ) = switch (controller.screenMirrorState) {
      ScreenMirrorState.starting => (
        icon: Icons.hourglass_top_rounded,
        title: 'Starting mirror',
        description: isIos
            ? "Waiting for ${device.displayName}'s screen. The first picture "
                  'takes a few seconds.'
            : 'Opening scrcpy for ${device.displayName}.',
      ),
      ScreenMirrorState.running => (
        icon: Icons.cast_connected_rounded,
        title: 'Mirror running',
        description: 'scrcpy is controlling ${device.displayName}.',
      ),
      ScreenMirrorState.unsupported => (
        icon: Icons.phonelink_off_rounded,
        title: 'Unsupported device',
        description:
            controller.screenMirrorError ??
            "Screen mirroring isn't available for this device.",
      ),
      ScreenMirrorState.error => (
        icon: Icons.error_outline_rounded,
        title: 'Mirror unavailable',
        description:
            controller.screenMirrorError ??
            'The mirror session could not be started.',
      ),
      ScreenMirrorState.stopped => (
        icon: Icons.mobile_screen_share,
        title: 'Ready to mirror',
        description: isIos
            ? "Show ${device.displayName}'s screen here and control it with "
                  'the mouse and keyboard.'
            : 'Launch scrcpy for ${device.displayName}.',
      ),
    };

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: theme.colorScheme.primary),
          const Gap(12),
          Text(
            title,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const Gap(8),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          // The capture route is a camera to macOS, so its permission prompt
          // and indicators would otherwise look like Eagly watching the room.
          if (isIos &&
              IosScreenCapture.isAvailable &&
              controller.screenMirrorState == ScreenMirrorState.stopped)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: HintNote(
                icon: Icons.videocam_outlined,
                title: "macOS treats the iPhone's screen as a camera",
                text:
                    'The first time, macOS asks to give Eagly camera access. '
                    'While mirroring, the Mac shows its camera indicator and '
                    'the iPhone may show its microphone indicator. Eagly '
                    "reads only the iPhone's screen: no camera, no "
                    'microphone, no sound.',
              ),
            ),
          // Starting the capture makes the iPhone take the Mac for an audio
          // device, and the question it asks holds back every touch.
          if (isIos &&
              IosScreenCapture.isAvailable &&
              controller.screenMirrorState == ScreenMirrorState.starting)
            const DelayedReveal(
              delay: Duration(seconds: 3),
              child: Padding(
                padding: EdgeInsets.only(top: 16),
                child: HintNote(
                  text:
                      'If the iPhone asks whether you are connecting '
                      'headphones, answer it on the phone. Touches from here '
                      "don't get through until it's gone.",
                ),
              ),
            ),
          const Gap(18),
          FilledButton.icon(
            onPressed: controller.isScreenMirrorRunning
                ? () => controller.stop()
                : controller.canStart
                ? () => controller.start()
                : null,
            icon: Icon(
              controller.isScreenMirrorRunning
                  ? Icons.stop_circle_outlined
                  : Icons.play_arrow,
            ),
            label: Text(
              controller.isScreenMirrorRunning ? 'Stop mirror' : 'Start mirror',
            ),
          ),
        ],
      ),
    );
  }
}
