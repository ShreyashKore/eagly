import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'scrcpy_mirror.dart';

/// One finger of a multi-finger touch on a [ScrcpyView], at fractions (0..1)
/// of the video rect.
class const ScrcpyTouchContact(
  /// Tells the fingers apart from frame to frame.
  final int id,
  final double nx,
  final double ny, {

  /// False in the one frame that lifts this finger.
  final bool touching = true,
});

/// Renders an embedded scrcpy stream and forwards pointer and keyboard
/// interactions to the device. Frames are decoded natively (VideoToolbox /
/// FFmpeg) and composited into [textureId]; we present that texture at the
/// device's aspect ratio. Wrap it in your own chrome (header / start-stop /
/// close controls). The iPhone mirror uses it too, with its own texture or
/// a [child] showing the latest screenshot.
///
/// Keyboard forwarding is focus-gated: keys only reach the device while the
/// surface holds focus (click it to take focus), so the host app keeps its own
/// shortcuts the rest of the time.
class const ScrcpyView({
  super.key,
  final int? textureId,

  /// Shown instead of [textureId]'s texture, such as a polled screenshot.
  final Widget? child,
  required final double aspectRatio,

  /// Called with a normalized (0..1) position within the video rect.
  final void Function(ScrcpyTouchAction action, double nx, double ny)? onTouch,

  /// Called with every frame of a two-finger gesture, which [onTouch] then
  /// doesn't see. An Option-drag (Alt-drag off macOS) pinches and turns
  /// around the picture's centre, as in the iOS Simulator, with both fingers
  /// marked while Option is held; a trackpad pinch or rotation is one too.
  /// Without it an Option-drag is one finger and a trackpad pinch is ignored.
  final void Function(List<ScrcpyTouchContact> contacts)? onMultiTouch,

  /// Focus node gating keyboard forwarding. Without one the surface is not
  /// focusable and no keys are forwarded.
  final FocusNode? focusNode,

  /// Called for every key event while the surface has focus. Return
  /// [KeyEventResult.handled] to keep the event away from the host app (and to
  /// stop the platform beeping at an unhandled key).
  final KeyEventResult Function(KeyEvent event)? onKey,
  final ValueChanged<bool>? onFocusChange,

  /// Laid over the picture at its size and let free to paint past its
  /// edges, such as a recording indicator around it. It gets no pointer
  /// events.
  final Widget? overlay,
}) extends StatelessWidget {
  this : assert(textureId != null || child != null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final node = focusNode;

    Widget surface = LayoutBuilder(
      builder: (context, constraints) => _TouchSurface(
        size: constraints.biggest,
        onTouch: onTouch,
        onMultiTouch: onMultiTouch,
        onPointerDown: node?.requestFocus,
        child: child ?? Texture(textureId: textureId!),
      ),
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
        child: overlay == null
            ? surface
            : Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  surface,
                  IgnorePointer(child: overlay),
                ],
              ),
      ),
    );
  }
}

/// The picture's pointer handling: one finger, or two for a pinch.
class const _TouchSurface({
  required final Size size,
  required final void Function(ScrcpyTouchAction action, double nx, double ny)?
  onTouch,
  required final void Function(List<ScrcpyTouchContact> contacts)? onMultiTouch,
  required final VoidCallback? onPointerDown,
  required final Widget child,
}) extends StatefulWidget {
  @override
  State<_TouchSurface> createState() => _TouchSurfaceState();
}

class _TouchSurfaceState extends State<_TouchSurface> {
  /// How far apart a trackpad pinch's fingers start, as a fraction of the
  /// picture's shorter side.
  static const _trackpadSpan = 0.3;

  /// How far a trackpad gesture has to scale or turn (radians) before it is
  /// a pinch. A two-finger scroll does neither and stays ignored.
  static const _pinchScale = 0.03;
  static const _pinchTurn = 0.05;

  bool _option = HardwareKeyboard.instance.isAltPressed;
  Offset? _hover;

  /// The pointer of an Option-drag in progress.
  int? _pinchPointer;

  /// Where a trackpad gesture began, and its scale, turn and pan when it
  /// became a pinch.
  Offset? _zoomOrigin;
  ({double scale, double rotation, Offset pan})? _zoomBase;

  /// The fingers of the pinch in progress, in local pixels.
  List<Offset>? _fingers;

  bool get _pinches => widget.onMultiTouch != null;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final option = HardwareKeyboard.instance.isAltPressed;
    if (option != _option) setState(() => _option = option);
    return false;
  }

  void _emit(ScrcpyTouchAction action, Offset position) {
    final onTouch = widget.onTouch;
    final size = widget.size;
    if (onTouch == null || size.width <= 0 || size.height <= 0) return;
    onTouch(
      action,
      (position.dx / size.width).clamp(0.0, 1.0),
      (position.dy / size.height).clamp(0.0, 1.0),
    );
  }

  void _emitFingers(List<Offset> fingers, {required bool touching}) {
    final size = widget.size;
    if (size.width <= 0 || size.height <= 0) return;
    widget.onMultiTouch?.call([
      for (final (id, finger) in fingers.indexed)
        ScrcpyTouchContact(
          id,
          (finger.dx / size.width).clamp(0.0, 1.0),
          (finger.dy / size.height).clamp(0.0, 1.0),
          touching: touching,
        ),
    ]);
  }

  /// The pointer's finger and its mirror image through the picture's centre.
  List<Offset> _mirrored(Offset pointer) => [
    pointer,
    Offset(widget.size.width - pointer.dx, widget.size.height - pointer.dy),
  ];

  void _press(List<Offset> fingers) {
    setState(() => _fingers = fingers);
    _emitFingers(fingers, touching: true);
  }

  void _lift() {
    final fingers = _fingers;
    if (fingers == null) return;
    _emitFingers(fingers, touching: false);
    setState(() {
      _fingers = null;
      _pinchPointer = null;
    });
  }

  // ── Mouse ─────────────────────────────────────────────────────────────

  void _onDown(PointerDownEvent event) {
    widget.onPointerDown?.call();
    if (_pinches && _option && _fingers == null) {
      _pinchPointer = event.pointer;
      _press(_mirrored(event.localPosition));
    } else {
      _emit(ScrcpyTouchAction.down, event.localPosition);
    }
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer == _pinchPointer) {
      _press(_mirrored(event.localPosition));
    } else {
      _emit(ScrcpyTouchAction.move, event.localPosition);
    }
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer == _pinchPointer) {
      _lift();
    } else {
      _emit(ScrcpyTouchAction.up, event.localPosition);
    }
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer == _pinchPointer) _lift();
  }

  void _onHover(PointerHoverEvent event) {
    if (!_pinches) return;
    if (_option) {
      setState(() => _hover = event.localPosition);
    } else {
      _hover = event.localPosition;
    }
  }

  // ── Trackpad ──────────────────────────────────────────────────────────

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    if (_pinches && _fingers == null) _zoomOrigin = event.localPosition;
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final origin = _zoomOrigin;
    if (origin == null) return;
    final base = _zoomBase ??=
        (event.scale - 1).abs() < _pinchScale &&
            event.rotation.abs() < _pinchTurn
        ? null
        : (scale: event.scale, rotation: event.rotation, pan: event.localPan);
    if (base == null) return;
    final centre = origin + event.localPan - base.pan;
    final reach =
        widget.size.shortestSide * _trackpadSpan / 2 * event.scale / base.scale;
    final turn = event.rotation - base.rotation;
    final arm = Offset(math.cos(turn), math.sin(turn)) * reach;
    _press([centre - arm, centre + arm]);
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) {
    final pinching = _zoomBase != null;
    _zoomOrigin = null;
    _zoomBase = null;
    if (pinching) _lift();
  }

  @override
  Widget build(BuildContext context) {
    final hover = _hover;
    final markers =
        _fingers ??
        (_pinches && _option && hover != null ? _mirrored(hover) : null);
    return MouseRegion(
      onHover: _onHover,
      onExit: (_) => setState(() => _hover = null),
      child: Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        onPointerPanZoomStart: _onPanZoomStart,
        onPointerPanZoomUpdate: _onPanZoomUpdate,
        onPointerPanZoomEnd: _onPanZoomEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (markers != null)
              IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('scrcpy-pinch-fingers'),
                  painter: _FingerPainter(
                    markers,
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A pinch's two fingers, as circles where they touch.
class const _FingerPainter(final List<Offset> fingers, final Color color)
    extends CustomPainter {
  static const _radius = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color.withValues(alpha: 0.3);
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final finger in fingers) {
      canvas
        ..drawCircle(finger, _radius, fill)
        ..drawCircle(finger, _radius, ring);
    }
  }

  @override
  bool shouldRepaint(_FingerPainter oldDelegate) =>
      oldDelegate.color != color || !listEquals(oldDelegate.fingers, fingers);
}
