import 'package:flutter/material.dart';

import '../../../presentation/components/hint_note.dart';
import '../../flutter_scrcpy/flutter_scrcpy.dart';
import '../ios/ios_mirror_session.dart';
import '../mirror_controller.dart';
import '../services/ios_screen_capture.dart';
import 'ios_screenshot_mode_note.dart';
import 'recording_glow.dart';

/// A running iPhone mirror: the live capture's texture, or the latest
/// screenshot, under notes for whatever is missing (live video, controls).
class const IosMirrorSurface({
  super.key,
  required final MirrorController controller,
  required final IosMirrorSession mirror,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = mirror.size;
    final textureId = mirror.textureId;
    final frame = mirror.frame;
    final screenshots = mirror.video == IosMirrorVideo.screenshots;
    final notices = [?mirror.videoNotice, ?mirror.inputNotice];
    final input = mirror.hasInput;

    final view = ScrcpyView(
      key: controller.surfaceKey,
      textureId: textureId,
      aspectRatio: size == null || size.height == 0
          ? 9 / 19.5
          : size.width / size.height,
      onTouch: input ? controller.handleTouch : null,
      onMultiTouch: input ? controller.handleMultiTouch : null,
      focusNode: input ? controller.keyboardFocusNode : null,
      onKey: controller.handleKeyEvent,
      onFocusChange: controller.handleKeyboardFocusChange,
      overlay: recordingGlow(controller),
      child: textureId == null && frame != null
          ? Image.memory(
              frame,
              gaplessPlayback: true,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
            )
          : null,
    );
    if (notices.isEmpty && !screenshots) return view;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            spacing: 8,
            children: [
              if (screenshots)
                // Where there is a live route, the notice below says why it
                // failed; iOS 27 is the way only where there is none.
                IosScreenshotModeNote(
                  suggestIos27: !IosScreenCapture.isAvailable,
                ),
              for (final notice in notices)
                HintNote(text: notice, icon: Icons.info_outline),
            ],
          ),
        ),
        Expanded(child: view),
      ],
    );
  }
}
