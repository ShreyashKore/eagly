import 'dart:async';

import 'package:flutter/material.dart';

import '../mirror_controller.dart';

/// [RecordingGlow] for [controller]'s running recording, if there is one.
Widget? recordingGlow(MirrorController controller) =>
    switch (controller.recordingClock) {
      final clock? => RecordingGlow(
        startedAt: clock.startedAt,
        timeLimit: clock.timeLimit,
      ),
      null => null,
    };

/// Rims the mirrored screen while it is recorded: a faint red outline and a
/// soft glow outside it that beats — a quick swell, then a slow fade. Painted
/// around the picture rather than on it, and the recording is made from the
/// device's own picture anyway, so none of it ends up in the video.
///
/// The beat stops when [timeLimit] runs out — the recording has stopped by
/// itself then — and never starts when the platform asks for less motion;
/// the outline and a steady glow still say "recording".
class const RecordingGlow({
  super.key,
  required final DateTime startedAt,

  /// Null when the recording has no limit (an iPhone's).
  required final Duration? timeLimit,
}) extends StatefulWidget {
  /// How far outside the picture the outline sits, clear of the 2 px focus
  /// border the mirror draws on its own edge.
  static const double gap = 3;

  /// One beat, rest included.
  static const beat = Duration(milliseconds: 1800);

  @override
  State<RecordingGlow> createState() => _RecordingGlowState();
}

class _RecordingGlowState extends State<RecordingGlow>
    with TickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: RecordingGlow.beat,
  );
  late final AnimationController _fadeIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..forward();
  Timer? _limitTimer;
  bool _reachedLimit = false;

  @override
  void initState() {
    super.initState();
    _scheduleLimit();
  }

  @override
  void didUpdateWidget(RecordingGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.startedAt != oldWidget.startedAt ||
        widget.timeLimit != oldWidget.timeLimit) {
      _scheduleLimit();
      _updateMotion();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void dispose() {
    _limitTimer?.cancel();
    _beat.dispose();
    _fadeIn.dispose();
    super.dispose();
  }

  void _scheduleLimit() {
    _limitTimer?.cancel();
    _limitTimer = null;
    final limit = widget.timeLimit;
    if (limit == null) {
      _reachedLimit = false;
      return;
    }
    final left = widget.startedAt.add(limit).difference(DateTime.now());
    _reachedLimit = left <= Duration.zero;
    if (!_reachedLimit) {
      _limitTimer = Timer(left, () {
        if (!mounted) return;
        setState(() => _reachedLimit = true);
        _updateMotion();
      });
    }
  }

  bool get _beating =>
      !_reachedLimit && !MediaQuery.disableAnimationsOf(context);

  void _updateMotion() {
    if (!_beating) {
      _beat.stop();
    } else if (!_beat.isAnimating) {
      _beat.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GlowPainter(
          beat: _beat,
          fadeIn: _fadeIn,
          // Held still: a steady mid glow, or a fainter one once the limit
          // has ended the recording.
          stillStrength: _beating ? null : (_reachedLimit ? 0 : 0.5),
          color: Colors.red,
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.beat,
    required this.fadeIn,
    required this.stillStrength,
    required this.color,
  }) : super(repaint: Listenable.merge([beat, fadeIn]));

  final Animation<double> beat;
  final Animation<double> fadeIn;

  /// The glow's strength when it isn't beating; null while it is.
  final double? stillStrength;
  final Color color;

  /// The part of a beat spent swelling; the rest fades out.
  static const double _swell = 0.2;

  /// How far the glow reaches past the rim, roughly.
  static const double _spread = 4;

  /// How strong the glow is at [t] through a beat, 0..1.
  static double _strength(double t) => t < _swell
      ? Curves.easeOut.transform(t / _swell)
      : 1 - Curves.easeInOut.transform((t - _swell) / (1 - _swell));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final opacity = Curves.easeOut.transform(fadeIn.value);
    final strength = stillStrength ?? _strength(beat.value);
    final rim = RRect.fromRectAndRadius(
      (Offset.zero & size).inflate(RecordingGlow.gap),
      const Radius.circular(6),
    );

    // The glow: a blurred stroke along the rim, clipped to outside it so it
    // spreads away from the picture and never over it. (BlurStyle.outer
    // would say the same, but tints the middle of large shapes.)
    canvas
      ..save()
      ..clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(rim.outerRect.inflate(_spread * 3)),
          Path()..addRRect(rim),
        ),
      )
      ..drawRRect(
        rim,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _spread
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _spread)
          ..color = color.withValues(alpha: (0.04 + 0.2 * strength) * opacity),
      )
      ..restore();
    canvas.drawRRect(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: (0.14 + 0.12 * strength) * opacity),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) =>
      oldDelegate.stillStrength != stillStrength || oldDelegate.color != color;
}
