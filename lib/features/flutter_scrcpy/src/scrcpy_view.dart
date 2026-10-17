import 'package:flutter/material.dart';

import 'scrcpy_mirror.dart';

/// Renders an embedded scrcpy stream and forwards pointer and keyboard
/// interactions to the device. Frames are decoded natively (VideoToolbox /
/// FFmpeg) and composited into [textureId]; we present that texture at the
/// device's aspect ratio. Wrap it in your own chrome (header / start-stop /
/// close controls).
///
/// Keyboard forwarding is focus-gated: keys only reach the device while the
/// surface holds focus (click it to take focus), so the host app keeps its own
/// shortcuts the rest of the time.
class ScrcpyView extends StatelessWidget {
  const ScrcpyView({
    super.key,
    required this.textureId,
    required this.aspectRatio,
    this.onTouch,
    this.focusNode,
    this.onKey,
    this.onFocusChange,
  });

  final int textureId;
  final double aspectRatio;

  /// Called with a normalized (0..1) position within the video rect.
  final void Function(ScrcpyTouchAction action, double nx, double ny)? onTouch;

  /// Focus node gating keyboard forwarding. Without one the surface is not
  /// focusable and no keys are forwarded.
  final FocusNode? focusNode;

  /// Called for every key event while the surface has focus. Return
  /// [KeyEventResult.handled] to keep the event away from the host app (and to
  /// stop the platform beeping at an unhandled key).
  final KeyEventResult Function(KeyEvent event)? onKey;

  final ValueChanged<bool>? onFocusChange;

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
    final theme = Theme.of(context);
    final node = focusNode;

    Widget surface = LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          onPointerDown: (e) {
            node?.requestFocus();
            _emit(ScrcpyTouchAction.down, e.localPosition, size);
          },
          onPointerMove: (e) =>
              _emit(ScrcpyTouchAction.move, e.localPosition, size),
          onPointerUp: (e) =>
              _emit(ScrcpyTouchAction.up, e.localPosition, size),
          child: Texture(textureId: textureId),
        );
      },
    );

    if (node != null) {
      surface = Focus(
        focusNode: node,
        onFocusChange: onFocusChange,
        onKeyEvent: (_, event) => onKey?.call(event) ?? KeyEventResult.ignored,
        child: AnimatedBuilder(
          animation: node,
          builder: (context, child) => DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(
                width: 2,
                color: node.hasFocus
                    ? theme.colorScheme.primary
                    : Colors.transparent,
              ),
            ),
            child: child,
          ),
          child: surface,
        ),
      );
    }

    return Container(
      color: theme.colorScheme.surfaceContainer,
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: aspectRatio > 0 ? aspectRatio : 9 / 16,
        child: surface,
      ),
    );
  }
}
