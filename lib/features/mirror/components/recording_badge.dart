import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

/// Floats over the mirror while the screen is recorded: a pulsing dot and
/// the time recorded, against screenrecord's limit where there is one. The
/// recording is made from the device's own picture, so none of this ends up
/// in it. It lets clicks through to the mirror; the control strip's button
/// stops the recording.
class const RecordingBadge({
  super.key,
  required final DateTime startedAt,

  /// Null when the recording has no limit (an iPhone's).
  required final Duration? timeLimit,
}) extends StatefulWidget {
  /// From here on the time turns to a warning.
  static const nearLimit = Duration(seconds: 15);

  @override
  State<RecordingBadge> createState() => _RecordingBadgeState();
}

class _RecordingBadgeState extends State<RecordingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // Faster than once a second, so the seconds don't visibly lag the clock.
    _tick = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => setState(() {}),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _tick.cancel();
    _pulse.dispose();
    super.dispose();
  }

  static String _format(Duration duration) {
    final seconds = duration.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final limit = widget.timeLimit;
    final raw = DateTime.now().difference(widget.startedAt);
    final elapsed = raw < Duration.zero ? Duration.zero : raw;
    final reachedLimit = limit != null && elapsed >= limit;
    final warn = limit != null && limit - elapsed <= RecordingBadge.nearLimit;
    final textStyle = theme.textTheme.labelLarge?.copyWith(
      color: scheme.onInverseSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final dimmed = scheme.onInverseSurface.withValues(alpha: 0.6);

    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        label: reachedLimit
            ? 'Recording reached its ${_format(limit)} limit'
            : 'Recording, ${_format(elapsed)}',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.inverseSurface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  // Holds still once nothing more is being recorded.
                  opacity: reachedLimit
                      ? const AlwaysStoppedAnimation(1)
                      : Tween(begin: 0.35, end: 1.0).animate(_pulse),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: reachedLimit ? dimmed : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const Gap(8),
                Text(
                  _format(reachedLimit ? limit : elapsed),
                  style: textStyle?.copyWith(
                    color: warn && !reachedLimit ? Colors.orange : null,
                  ),
                ),
                if (limit != null)
                  Text(
                    reachedLimit
                        ? '  ·  limit reached, stop to save'
                        : ' / ${_format(limit)}',
                    style: textStyle?.copyWith(color: dimmed),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
