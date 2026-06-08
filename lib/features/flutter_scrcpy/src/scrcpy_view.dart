import 'package:flutter/material.dart';

import 'scrcpy_mirror.dart';

/// Renders an embedded scrcpy stream and forwards pointer interactions to the
/// device. Frames are decoded natively (VideoToolbox / FFmpeg) and composited
/// into [textureId]; we present that texture at the device's aspect ratio.
/// Wrap it in your own chrome (header / start-stop / close controls).
class ScrcpyView extends StatelessWidget {
  const ScrcpyView({
    super.key,
    required this.textureId,
    required this.aspectRatio,
    this.onTouch,
  });

  final int textureId;
  final double aspectRatio;

  /// Called with a normalized (0..1) position within the video rect.
  final void Function(ScrcpyTouchAction action, double nx, double ny)? onTouch;

  void _emit(ScrcpyTouchAction action, Offset position, Size size) {
    if (onTouch == null || size.width <= 0 || size.height <= 0) return;
    onTouch!(
      action,
      (position.dx / size.width).clamp(0.0, 1.0),
      (position.dy / size.height).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: aspectRatio > 0 ? aspectRatio : 9 / 16,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            return Listener(
              onPointerDown: (e) =>
                  _emit(ScrcpyTouchAction.down, e.localPosition, size),
              onPointerMove: (e) =>
                  _emit(ScrcpyTouchAction.move, e.localPosition, size),
              onPointerUp: (e) =>
                  _emit(ScrcpyTouchAction.up, e.localPosition, size),
              child: Texture(textureId: textureId),
            );
          },
        ),
      ),
    );
  }
}
