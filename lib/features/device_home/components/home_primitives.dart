import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/feature_view.dart';
import '../../../presentation/theme/app_theme.dart';

/// Shared building blocks for the device home dashboard: card chrome, dense
/// label/value grids, gauges and sparklines.

// ── Card chrome ──────────────────────────────────────────────────────────

/// A dashboard card: small icon + title header, optional [trailing] action,
/// then [child]. Padding is deliberately tight — this screen packs a lot.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 14),
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
                const Gap(7),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                      fontSize: 10.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const Gap(10),
            child,
          ],
        ),
      ),
    );
  }
}

// ── Label / value grid ───────────────────────────────────────────────────

/// One label/value pair rendered stacked — label above, value below — which
/// packs far denser than a two-column row at desktop widths.
class SpecItem {
  const SpecItem(this.label, this.value, {this.copyable = false, this.mono});

  final String label;
  final String value;
  final bool copyable;

  /// Defaults to [copyable] (ids/serials read better in monospace).
  final bool? mono;
}

/// Lays [items] out in as many columns as the available width allows.
class SpecGrid extends StatelessWidget {
  const SpecGrid({super.key, required this.items, this.minColumnWidth = 132});

  final List<SpecItem> items;
  final double minColumnWidth;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final width = constraints.maxWidth;
        final columns = math.max(
          1,
          (width + spacing) ~/ (minColumnWidth + spacing),
        );
        final itemWidth = (width - spacing * (columns - 1)) / columns - 0.01;
        return Wrap(
          spacing: spacing,
          runSpacing: 10,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _SpecTile(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _SpecTile extends StatelessWidget {
  const _SpecTile({required this.item});

  final SpecItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = item.mono ?? item.copyable;
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w500,
      fontFamily: mono ? 'monospace' : null,
      fontSize: mono ? 11.5 : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 10.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Gap(2),
        Row(
          children: [
            Expanded(
              child: SelectableText(item.value, maxLines: 1, style: valueStyle),
            ),
            if (item.copyable) CopyButton(value: item.value, label: item.label),
          ],
        ),
      ],
    );
  }
}

/// Compact copy-to-clipboard affordance used next to ids and serials.
class CopyButton extends StatelessWidget {
  const CopyButton({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Copy $label',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          FeatureView.showSnackBar(context, 'Copied $label to clipboard.');
        },
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            Icons.copy_rounded,
            size: 13,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

// ── Status affordances ───────────────────────────────────────────────────

enum StatusTone { good, warn, bad, neutral }

extension StatusToneColor on StatusTone {
  Color color(BuildContext context) {
    final tokens = context.eaglyTheme;
    return switch (this) {
      StatusTone.good => tokens.statusLiveColor,
      StatusTone.warn => tokens.warningColor,
      StatusTone.bad => tokens.errorColor,
      StatusTone.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }
}

/// Small pill: tinted dot (or icon) + text. The workhorse for the metadata
/// strip in the hero card and the readiness chips.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
    this.showDot = false,
    this.mono = false,
    this.trailing,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;
  final bool showDot;
  final bool mono;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = tone.color(context);
    final tinted = tone != StatusTone.neutral;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: tinted
            ? accent.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: tinted
              ? accent.withValues(alpha: 0.28)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            _Dot(color: accent),
            const Gap(6),
          ] else if (icon != null) ...[
            Icon(
              icon,
              size: 13,
              color: tinted ? accent : theme.colorScheme.onSurfaceVariant,
            ),
            const Gap(5),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              fontFamily: mono ? 'monospace' : null,
              color: tinted ? accent : theme.colorScheme.onSurface,
            ),
          ),
          if (trailing != null) ...[const Gap(2), trailing!],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 5),
        ],
      ),
    );
  }
}

/// On/off capability tile (Wi-Fi, Bluetooth, …) — an icon that reads at a
/// glance instead of a "Wi-Fi: On" text row.
class ToggleTile extends StatelessWidget {
  const ToggleTile({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = enabled
        ? context.eaglyTheme.statusLiveColor
        : theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: '$label — ${enabled ? 'On' : 'Off'}',
      child: Container(
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: enabled
              ? accent.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? accent.withValues(alpha: 0.25)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 17,
              color: enabled
                  ? accent
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            const Gap(4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9.5,
                color: enabled
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Gauges & charts ──────────────────────────────────────────────────────

/// Animated 270° arc gauge with a value in the middle.
class MetricGauge extends StatelessWidget {
  const MetricGauge({
    super.key,
    required this.value,
    required this.color,
    this.size = 68,
    this.stroke = 6,
    this.center,
  });

  /// 0..1; `null` renders an empty track (data unavailable).
  final double? value;
  final Color color;
  final double size;
  final double stroke;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: (value ?? 0).clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _GaugePainter(
              value: animated,
              color: color,
              track: theme.colorScheme.surfaceContainerHighest,
              stroke: stroke,
            ),
            child: Center(child: center),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  static const _startAngle = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(arcRect, _startAngle, _sweep, false, base);

    if (value <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: _startAngle,
        endAngle: _startAngle + _sweep,
        colors: [color.withValues(alpha: 0.55), color],
        transform: GradientRotation(_startAngle),
      ).createShader(arcRect);
    canvas.drawArc(arcRect, _startAngle, _sweep * value, false, fill);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Tiny filled line chart of recent samples (0..1 each).
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.samples,
    required this.color,
    this.height = 26,
  });

  final List<double> samples;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(samples: samples, color: color),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.samples, required this.color});

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    final dx = size.width / (samples.length - 1);
    final points = <Offset>[
      for (var i = 0; i < samples.length; i++)
        Offset(
          i * dx,
          size.height - samples[i].clamp(0.0, 1.0) * (size.height - 2) - 1,
        ),
    ];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }

    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.samples != samples || old.color != color;
}

/// Horizontal usage bar with a label row above it.
class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 6,
  });

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) => SizedBox(
          height: height,
          child: Stack(
            children: [
              Container(color: theme.colorScheme.surfaceContainerHighest),
              FractionallySizedBox(
                widthFactor: animated,
                child: Container(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared threshold colouring for "higher is worse" metrics.
Color usageColor(
  BuildContext context,
  double percent, {
  double warn = 75,
  double bad = 90,
}) {
  final tokens = context.eaglyTheme;
  if (percent >= bad) return tokens.errorColor;
  if (percent >= warn) return tokens.warningColor;
  return tokens.statusLiveColor;
}
