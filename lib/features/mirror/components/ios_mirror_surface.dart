import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/hint_note.dart';
import '../../flutter_scrcpy/flutter_scrcpy.dart';
import '../ios/ios_mirror_session.dart';
import '../mirror_controller.dart';
import 'recording_glow.dart';

/// A running iPhone mirror: the live capture's texture, or the latest
/// screenshot, under a note for whatever is missing (live video, controls).
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
    final notices = [?mirror.videoNotice, ?mirror.inputNotice];
    final input = mirror.hasInput;

    final view = ScrcpyView(
      key: controller.surfaceKey,
      textureId: textureId,
      aspectRatio: size == null || size.height == 0
          ? 9 / 19.5
          : size.width / size.height,
      onTouch: input ? controller.handleTouch : null,
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
    if (notices.isEmpty) return view;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            children: [
              for (final (index, notice) in notices.indexed) ...[
                if (index > 0) const Gap(8),
                HintNote(text: notice, icon: Icons.info_outline),
              ],
            ],
          ),
        ),
        Expanded(child: view),
      ],
    );
  }
}
