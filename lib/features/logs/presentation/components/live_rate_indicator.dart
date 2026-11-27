import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../presentation/theme/app_theme.dart';

/// The status bar's "Live" readout while capture is streaming: a dot that
/// pulses once a second, a sparkline of lines per second over the last
/// [historyLength] seconds, and the current rate.
///
/// It samples [readCount] (a counter that only grows, such as
/// `LogController.receivedLineCount`) on a timer of its own and rebuilds only
/// itself, so the pane never rebuilds for it. The pulse is a single beat per
/// sample, not a repeating animation: between beats nothing is scheduled, so
/// `pumpAndSettle` still settles, and with `MediaQuery.disableAnimations` the
/// dot stays still.
class const LiveRateIndicator({
  super.key,

  /// The running total of lines received; read once per [sampleInterval].
  required final int Function() readCount,

  /// The live state's colour, for the dot and the label.
  required final Color color,
}) extends StatefulWidget {
  @visibleForTesting
  static Duration sampleInterval = const Duration(seconds: 1);

  /// Seconds of history the sparkline shows.
  static const int historyLength = 30;

  /// How many of the latest samples the readout averages, so it doesn't
  /// jump with each 300 ms flush landing on one side of a second or the other.
  static const int _readoutWindow = 3;

  @override
  State<LiveRateIndicator> createState() => _LiveRateIndicatorState();
}

class _LiveRateIndicatorState extends State<LiveRateIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  Timer? _timer;
  late int _lastCount;

  /// Lines per second, oldest first; never longer than [historyLength].
  final List<int> _rates = [];

  /// Bumped on each sample so the sparkline knows to repaint.
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.readCount();
    _timer = Timer.periodic(LiveRateIndicator.sampleInterval, (_) => _sample());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _sample() {
    if (!mounted) return;
    final count = widget.readCount();
    final rate = math.max(0, count - _lastCount);
    _lastCount = count;
    setState(() {
      _rates.add(rate);
      if (_rates.length > LiveRateIndicator.historyLength) _rates.removeAt(0);
      _revision++;
    });
    if (!MediaQuery.disableAnimationsOf(context)) {
      unawaited(_pulse.forward(from: 0));
    }
  }

  int get _currentRate {
    if (_rates.isEmpty) return 0;
    final window = _rates.sublist(
      math.max(0, _rates.length - LiveRateIndicator._readoutWindow),
    );
    return (window.reduce((a, b) => a + b) / window.length).round();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.eaglyTheme;
    final rate = _currentRate;
    final readout = '${_formatRate(rate)} lines/s';
    return Semantics(
      label: 'Live, $readout',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            child: _PulseDot(pulse: _pulse, color: widget.color),
          ),
          const SizedBox(width: 6),
          Text(
            'Live',
            style: TextStyle(
              fontSize: 12,
              color: widget.color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message:
                'Lines per second, last ${LiveRateIndicator.historyLength} s',
            child: RepaintBoundary(
              child: CustomPaint(
                key: const ValueKey('live-rate-sparkline'),
                size: Size(context.scaled(60), context.scaled(16)),
                painter: LiveRateSparklinePainter(
                  rates: _rates,
                  revision: _revision,
                  color: widget.color,
                  baselineColor: theme.tertiaryTextColor.withValues(
                    alpha: 0.25,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Wide enough for "9.9k lines/s", so the bar doesn't shuffle as the
          // rate changes.
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: context.scaled(70)),
            child: Text(readout, style: theme.statusBarStyle),
          ),
        ],
      ),
    );
  }

  static String _formatRate(int rate) {
    if (rate < 1000) return '$rate';
    if (rate < 10000) return '${(rate / 1000).toStringAsFixed(1)}k';
    return '${(rate / 1000).round()}k';
  }
}

/// A dot that swells and fades out a soft ring on each [pulse] run.
class const _PulseDot({
  required final Animation<double> pulse,
  required final Color color,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = context.scaled(12);
    return SizedBox.square(
      dimension: size,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, _) {
          final t = Curves.easeOut.transform(pulse.value);
          // At rest (and before the first beat) pulse.value is 0 or 1: no
          // ring, just the dot.
          final ringing = pulse.isAnimating;
          return CustomPaint(
            painter: _PulseDotPainter(color: color, ring: ringing ? t : null),
          );
        },
      ),
    );
  }
}

class const _PulseDotPainter({required final Color color, final double? ring})
    extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final ring = this.ring;
    if (ring != null) {
      canvas.drawCircle(
        center,
        radius * (0.45 + 0.55 * ring),
        Paint()..color = color.withValues(alpha: 0.35 * (1 - ring)),
      );
    }
    canvas.drawCircle(center, radius * 0.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulseDotPainter old) =>
      old.color != color || old.ring != ring;
}

/// Lines per second as a line over a faint fill, scaled to the busiest
/// second shown. Exposed for tests, which read [rates] off it.
class const LiveRateSparklinePainter({
  required final List<int> rates,

  /// Changes whenever [rates] does: the list is mutated in place.
  required final int revision,
  required final Color color,
  required final Color baselineColor,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height - 0.5;
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()
        ..color = baselineColor
        ..strokeWidth = 1,
    );
    if (rates.length < 2) return;

    final peak = math.max(1, rates.reduce(math.max));
    // Right-aligned on a fixed time axis, so a sparkline still filling up
    // grows from the right instead of stretching.
    final step = size.width / (LiveRateIndicator.historyLength - 1);
    final startX = size.width - step * (rates.length - 1);
    const top = 1.5;
    final usable = baseline - top;
    final line = Path();
    for (var i = 0; i < rates.length; i++) {
      final x = startX + step * i;
      final y = baseline - usable * (rates[i] / peak);
      i == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, baseline)
      ..lineTo(startX, baseline)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.14));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(LiveRateSparklinePainter old) =>
      old.revision != revision ||
      old.color != color ||
      old.baselineColor != baselineColor;
}
