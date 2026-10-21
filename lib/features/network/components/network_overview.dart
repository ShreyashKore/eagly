import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../presentation/theme/app_theme.dart';
import '../data/network_filter.dart';
import '../data/network_timeline.dart';
import '../data/network_transaction.dart';
import '../data/network_transaction_store.dart';
import '../network_controller.dart';
import 'network_presentation.dart';
import 'network_transaction_list.dart' show networkBarColor;

/// The timeline strip above the list, like DevTools' overview: every request
/// the filter lets through as a bar on a shared time axis, packed into lanes,
/// colored by status.
///
/// - Hover reads out the time under the pointer and the request under it.
/// - Click a bar to open that request.
/// - Drag across the strip to show only the requests active in that stretch
///   (the filter's time window); click empty space or double-click to show
///   the whole timeline again.
class const NetworkOverview({
  super.key,
  required final NetworkController controller,
}) extends StatefulWidget {
  @override
  State<NetworkOverview> createState() => _NetworkOverviewState();
}

class _NetworkOverviewState extends State<NetworkOverview> {
  Offset? _hover;
  double? _dragStart;
  double? _dragEnd;
  _Layout? _layout;

  NetworkController get controller => widget.controller;

  _Layout _layoutFor(List<NetworkEntry> entries, int maxLanes) {
    final cached = _layout;
    if (cached != null &&
        identical(cached.entries, entries) &&
        cached.maxLanes == maxLanes) {
      return cached;
    }
    return _layout = _Layout.of(entries, maxLanes);
  }

  void _setWindow(double fromX, double toX, double width, _Layout layout) {
    final range = layout.range;
    if (range == null || width <= 0) return;
    final left = math.min(fromX, toX).clamp(0.0, width) / width;
    final right = math.max(fromX, toX).clamp(0.0, width) / width;
    controller.setFilter(
      controller.filter.copyWith(
        timeWindow: () =>
            NetworkTimeWindow(range.timeAt(left), range.timeAt(right)),
      ),
    );
  }

  void _clearWindow() {
    if (controller.filter.timeWindow == null) return;
    controller.setFilter(controller.filter.copyWith(timeWindow: () => null));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final height = context.scaled(64);
    final axisHeight = context.scaled(16);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final laneArea = height - axisHeight - 6;
          final maxLanes = math.max(1, (laneArea / _laneStride).floor());
          final layout = _layoutFor(controller.timelineEntries, maxLanes);
          final range = layout.range;
          if (range == null) {
            return Center(
              child: Text(
                controller.isEmpty
                    ? 'The timeline fills in as requests arrive'
                    : 'No request here has a start time to place on the timeline',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.tertiaryTextColor,
                ),
              ),
            );
          }
          final hit = _hover == null || _dragStart != null
              ? null
              : layout.hitTest(_hover!, width, axisHeight);

          final painter = _OverviewPainter(
            layout: layout,
            axisHeight: axisHeight,
            selected: controller.selected?.key,
            window: controller.filter.timeWindow,
            drag: _dragStart == null || _dragEnd == null
                ? null
                : (_dragStart!, _dragEnd!),
            hover: _hover,
            hit: hit,
            colors: _OverviewColors(
              axis: theme.colorScheme.outlineVariant,
              label: tokens.tertiaryTextColor,
              shade: theme.colorScheme.surface.withValues(alpha: 0.7),
              brush: theme.colorScheme.primary,
              hoverLine: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              selected: theme.colorScheme.onSurface,
              tooltipBackground: theme.colorScheme.inverseSurface,
              tooltipText: theme.colorScheme.onInverseSurface,
              barColor: (t) => networkBarColor(context, t),
            ),
            labelStyle: theme.textTheme.labelSmall ?? const TextStyle(),
            textScaler: MediaQuery.textScalerOf(context),
          );

          return MouseRegion(
            cursor: hit != null
                ? SystemMouseCursors.click
                : SystemMouseCursors.precise,
            onHover: (event) => setState(() => _hover = event.localPosition),
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final target = layout.hitTest(
                  details.localPosition,
                  width,
                  axisHeight,
                );
                if (target != null) {
                  controller.select(target.key);
                } else {
                  _clearWindow();
                }
              },
              onDoubleTap: _clearWindow,
              onHorizontalDragStart: (details) => setState(() {
                _dragStart = details.localPosition.dx;
                _dragEnd = details.localPosition.dx;
              }),
              onHorizontalDragUpdate: (details) => setState(() {
                _dragEnd = details.localPosition.dx;
                _hover = details.localPosition;
              }),
              onHorizontalDragEnd: (_) {
                final start = _dragStart;
                final end = _dragEnd;
                setState(() {
                  _dragStart = null;
                  _dragEnd = null;
                });
                if (start == null || end == null) return;
                if ((end - start).abs() < 4) {
                  _clearWindow();
                } else {
                  _setWindow(start, end, width, layout);
                }
              },
              onHorizontalDragCancel: () => setState(() {
                _dragStart = null;
                _dragEnd = null;
              }),
              child: Semantics(
                label:
                    'Request timeline, ${formatElapsed(range.duration)} long. '
                    'Drag to show only part of it.',
                child: CustomPaint(painter: painter, size: Size.infinite),
              ),
            ),
          );
        },
      ),
    );
  }
}

const double _barHeight = 3;
const double _laneGap = 2;
const double _laneStride = _barHeight + _laneGap;

/// Where each request sits: its lane and its span as fractions of [range].
class _Layout {
  _Layout(this.entries, this.maxLanes, this.range, this.bars);

  /// Greedy lane packing: each request goes in the first lane that is free
  /// when it starts; once [maxLanes] are full it shares the lane that frees
  /// up first.
  factory _Layout.of(List<NetworkEntry> entries, int maxLanes) {
    final range = NetworkTimeRange.of(entries)?.padded();
    if (range == null) return _Layout(entries, maxLanes, null, const []);
    final spans = [
      for (final entry in entries)
        if (spanOf(entry.transaction) case final span?)
          (
            entry: entry,
            start: range.fractionOf(span.start),
            end: range.fractionOf(span.end ?? range.end),
            pending: span.end == null,
          ),
    ]..sort((a, b) => a.start.compareTo(b.start));

    final laneEnds = <double>[];
    final bars = <_Bar>[];
    // Bars are at least this wide on screen; keep a sliver of air between.
    const minimum = 0.002;
    for (final span in spans) {
      var lane = laneEnds.indexWhere((end) => end <= span.start);
      if (lane < 0) {
        if (laneEnds.length < maxLanes) {
          lane = laneEnds.length;
          laneEnds.add(0);
        } else {
          lane = 0;
          for (var i = 1; i < laneEnds.length; i++) {
            if (laneEnds[i] < laneEnds[lane]) lane = i;
          }
        }
      }
      laneEnds[lane] = math.max(span.end, span.start + minimum) + minimum;
      bars.add(
        _Bar(span.entry, lane, span.start, span.end, pending: span.pending),
      );
    }
    return _Layout(entries, maxLanes, range, bars);
  }

  final List<NetworkEntry> entries;
  final int maxLanes;
  final NetworkTimeRange? range;
  final List<_Bar> bars;

  /// The request whose bar is under [position], if any.
  NetworkEntry? hitTest(Offset position, double width, double axisHeight) {
    final lane = ((position.dy - axisHeight - 3) / _laneStride).floor();
    if (lane < 0 || lane >= maxLanes) return null;
    const slop = 3.0;
    for (final bar in bars.reversed) {
      if (bar.lane != lane) continue;
      final left = bar.start * width - slop;
      final right = math.max(bar.end * width, bar.start * width + 2) + slop;
      if (position.dx >= left && position.dx <= right) return bar.entry;
    }
    return null;
  }
}

class const _Bar(
  final NetworkEntry entry,
  final int lane,
  final double start,
  final double end, {
  required final bool pending,
});

class const _OverviewColors({
  required final Color axis,
  required final Color label,
  required final Color shade,
  required final Color brush,
  required final Color hoverLine,
  required final Color selected,
  required final Color tooltipBackground,
  required final Color tooltipText,
  required final Color Function(NetworkTransaction) barColor,
});

class _OverviewPainter extends CustomPainter {
  _OverviewPainter({
    required this.layout,
    required this.axisHeight,
    required this.selected,
    required this.window,
    required this.drag,
    required this.hover,
    required this.hit,
    required this.colors,
    required this.labelStyle,
    required this.textScaler,
  });

  final _Layout layout;
  final double axisHeight;
  final NetworkTransactionKey? selected;
  final NetworkTimeWindow? window;
  final (double, double)? drag;
  final Offset? hover;
  final NetworkEntry? hit;
  final _OverviewColors colors;
  final TextStyle labelStyle;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final range = layout.range;
    if (range == null) return;
    _paintAxis(canvas, size, range);

    final top = axisHeight + 3;
    for (final bar in layout.bars) {
      final left = bar.start * size.width;
      final right = math.max(bar.end * size.width, left + 2);
      final rect = Rect.fromLTRB(
        left,
        top + bar.lane * _laneStride,
        right,
        top + bar.lane * _laneStride + _barHeight,
      );
      final color = colors.barColor(bar.entry.transaction);
      canvas.drawRect(
        rect,
        Paint()..color = bar.pending ? color.withValues(alpha: 0.5) : color,
      );
      if (bar.entry.key == selected || identical(bar.entry, hit)) {
        canvas.drawRect(
          rect.inflate(1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = colors.selected,
        );
      }
    }

    // The picked window: everything outside it dimmed.
    final shown = drag ?? _windowX(size, range);
    if (shown != null) {
      final left = math.min(shown.$1, shown.$2).clamp(0.0, size.width);
      final right = math.max(shown.$1, shown.$2).clamp(0.0, size.width);
      final shade = Paint()..color = colors.shade;
      canvas.drawRect(Rect.fromLTRB(0, 0, left, size.height), shade);
      canvas.drawRect(Rect.fromLTRB(right, 0, size.width, size.height), shade);
      final edge = Paint()
        ..color = colors.brush
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(left, 0), Offset(left, size.height), edge);
      canvas.drawLine(Offset(right, 0), Offset(right, size.height), edge);
      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        Paint()..color = colors.brush.withValues(alpha: 0.06),
      );
    }

    final hover = this.hover;
    if (hover != null) {
      canvas.drawLine(
        Offset(hover.dx, axisHeight),
        Offset(hover.dx, size.height),
        Paint()
          ..color = colors.hoverLine
          ..strokeWidth = 1,
      );
      final at = range.timeAt(hover.dx / size.width);
      final hit = this.hit;
      final text = hit == null
          ? formatElapsed(at.difference(range.start))
          : '${hit.transaction.request.method} ${displayPath(hit.transaction)}'
                '  ·  ${statusLabel(hit.transaction)}'
                '${hit.transaction.elapsed == null ? '' : '  ·  ${formatElapsed(hit.transaction.elapsed!)}'}';
      _paintTooltip(canvas, size, hover, text);
    }
  }

  (double, double)? _windowX(Size size, NetworkTimeRange range) {
    final window = this.window;
    if (window == null) return null;
    return (
      range.fractionOf(window.start) * size.width,
      range.fractionOf(window.end) * size.width,
    );
  }

  void _paintAxis(Canvas canvas, Size size, NetworkTimeRange range) {
    final totalMs = range.duration.inMicroseconds / 1000;
    final step = _niceStep(totalMs, size.width);
    final axis = Paint()
      ..color = colors.axis
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, axisHeight),
      Offset(size.width, axisHeight),
      axis,
    );
    for (var ms = step; ms < totalMs; ms += step) {
      final x = ms / totalMs * size.width;
      canvas.drawLine(Offset(x, axisHeight - 4), Offset(x, size.height), axis);
      final label = TextPainter(
        text: TextSpan(
          text: formatElapsed(Duration(microseconds: (ms * 1000).round())),
          style: labelStyle.copyWith(color: colors.label, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      if (x + 3 + label.width < size.width) {
        label.paint(canvas, Offset(x + 3, (axisHeight - label.height) / 2));
      }
    }
  }

  void _paintTooltip(Canvas canvas, Size size, Offset at, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(color: colors.tooltipText, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(40, size.width - 16));
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 3);
    final width = painter.width + padding.horizontal;
    final height = painter.height + padding.vertical;
    var left = at.dx + 10;
    if (left + width > size.width - 4) left = at.dx - 10 - width;
    left = left.clamp(4.0, math.max(4.0, size.width - width - 4));
    final top = (size.height - height - 4).clamp(0.0, size.height);
    final rect = Rect.fromLTWH(left, top, width, height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = colors.tooltipBackground.withValues(alpha: 0.92),
    );
    painter.paint(canvas, Offset(left + padding.left, top + padding.top));
  }

  /// A 1/2/5 × 10ⁿ ms step giving roughly one tick per 90 px.
  static double _niceStep(double totalMs, double width) {
    final target = totalMs / math.max(1, width / 90);
    final magnitude = math
        .pow(10, (math.log(math.max(target, 1e-3)) / math.ln10).floor())
        .toDouble();
    for (final multiple in [1, 2, 5, 10]) {
      if (magnitude * multiple >= target) return magnitude * multiple;
    }
    return magnitude * 10;
  }

  @override
  bool shouldRepaint(_OverviewPainter old) =>
      !identical(old.layout, layout) ||
      old.selected != selected ||
      old.window != window ||
      old.drag != drag ||
      old.hover != hover ||
      !identical(old.hit, hit) ||
      old.axisHeight != axisHeight;
}
