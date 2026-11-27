import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../presentation/theme/app_theme.dart';
import '../../data/models/log_entry.dart';
import '../../data/models/log_level.dart';

// ── Marks ──

/// Bits of an overview row: what the lines that fall on it hold.
abstract final class OverviewMark {
  static const int warning = 1;
  static const int error = 2;
  static const int searchMatch = 4;

  /// Both level bits set means an error and a warning share the row; the
  /// error wins.
  static const int levelMask = warning | error;
}

/// Buckets [logs] into [rows] overview rows: each row ORs together the
/// [OverviewMark] bits of the lines that land on it, by index, so an error
/// anywhere in a row's span marks the whole row. [searchMatches] are indices
/// into [logs]. With fewer lines than rows, a line covers every row of its
/// share rather than one, so short logs don't come out as hairlines.
///
/// One pass over [logs], with each distinct level string parsed once — fast
/// enough for 100k lines a few times a second.
@visibleForTesting
Uint8List computeOverviewMarks({
  required List<LogEntry> logs,
  required List<int> searchMatches,
  required int rows,
}) {
  final marks = Uint8List(math.max(0, rows));
  final count = logs.length;
  if (rows <= 0 || count == 0) return marks;

  void mark(int index, int bits) {
    final start = index * rows ~/ count;
    final end = math.max(start + 1, (index + 1) * rows ~/ count);
    for (var row = start; row < end && row < rows; row++) {
      marks[row] |= bits;
    }
  }

  final levelBits = <String, int>{};
  for (var i = 0; i < count; i++) {
    final level = logs[i].level;
    final bits = levelBits[level] ??= _levelBits(level);
    if (bits != 0) mark(i, bits);
  }
  for (final index in searchMatches) {
    if (index >= 0 && index < count) mark(index, OverviewMark.searchMatch);
  }
  return marks;
}

int _levelBits(String level) => switch (LogLevel.fromStored(level).code) {
  'fault' || 'error' => OverviewMark.error,
  'warning' => OverviewMark.warning,
  _ => 0,
};

// ── Ruler ──

/// A narrow strip beside the log list's scrollbar that marks where errors,
/// warnings and search matches sit across the whole filtered log — the
/// scrollbar says where you are, this says where to look. A click or drag
/// jumps the list there. It takes no space while it has nothing to mark.
///
/// Marks are placed by line index, not by pixel offset: rows are measured
/// lazily, so offsets are partly estimates, and an index is exact.
class const LogOverviewRuler({
  super.key,
  required final List<LogEntry> logs,

  /// Indices into [logs] of the current search's matches; empty with no
  /// search.
  final List<int> searchMatches = const [],

  /// Called with the index of the line under the pointer.
  required final ValueChanged<int> onJumpTo,

  /// Height of the column header the strip sits beside, so it starts where
  /// the rows do.
  required final double headerHeight,
}) extends StatefulWidget {
  static const double width = 12;

  /// The most often the marks are recomputed while lines stream in.
  @visibleForTesting
  static Duration refreshInterval = const Duration(milliseconds: 250);

  @override
  State<LogOverviewRuler> createState() => _LogOverviewRulerState();
}

class _LogOverviewRulerState extends State<LogOverviewRuler> {
  Uint8List _marks = Uint8List(0);
  bool _hasMarks = false;
  int _rows = 0;

  /// Bumped whenever [_marks] is replaced, for the painter.
  int _revision = 0;

  /// What [_marks] was computed from; see [_signature].
  Object? _computedFrom;
  final Stopwatch _sinceCompute = Stopwatch();
  Timer? _trailingRefresh;

  @override
  void initState() {
    super.initState();
    _compute(_rowsToCompute);
  }

  /// The strip's height in rows once it has been laid out. Before that — or
  /// while hidden, when it isn't laid out at all — a row per line (capped)
  /// still answers whether there is anything to mark.
  int get _rowsToCompute =>
      _rows > 0 ? _rows : math.min(widget.logs.length, 1 << 12);

  @override
  void didUpdateWidget(LogOverviewRuler old) {
    super.didUpdateWidget(old);
    if (_signature() == _computedFrom) return;
    final wait = LogOverviewRuler.refreshInterval - _sinceCompute.elapsed;
    if (wait <= Duration.zero) {
      _compute(_rowsToCompute);
    } else {
      // Throttled while lines stream in; the trailing refresh makes sure
      // the last batch is still drawn.
      _trailingRefresh ??= Timer(wait, () {
        _trailingRefresh = null;
        if (mounted && _signature() != _computedFrom) {
          setState(() => _compute(_rowsToCompute));
        }
      });
    }
  }

  @override
  void dispose() {
    _trailingRefresh?.cancel();
    super.dispose();
  }

  /// Cheap identity of the inputs. The filtered list is updated in place as
  /// lines arrive and are trimmed, so its length and end ids stand in for
  /// its contents.
  Object _signature() {
    final logs = widget.logs;
    return (
      identityHashCode(logs),
      logs.length,
      logs.firstOrNull?.id,
      logs.lastOrNull?.id,
      identityHashCode(widget.searchMatches),
      widget.searchMatches.length,
    );
  }

  void _compute(int rows) {
    _marks = computeOverviewMarks(
      logs: widget.logs,
      searchMatches: widget.searchMatches,
      rows: rows,
    );
    _hasMarks = _marks.any((bits) => bits != 0);
    _computedFrom = _signature();
    _revision++;
    _sinceCompute
      ..reset()
      ..start();
  }

  void _jumpTo(Offset localPosition, double height) {
    final count = widget.logs.length;
    if (count == 0 || height <= 0) return;
    final fraction = (localPosition.dy / height).clamp(0.0, 1.0);
    widget.onJumpTo(math.min(count - 1, (fraction * count).floor()));
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasMarks || widget.logs.isEmpty) return const SizedBox.shrink();
    final theme = context.eaglyTheme;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: LogOverviewRuler.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Carries the header's band across, so the strip reads as part of
          // the list rather than something laid beside it.
          Container(
            height: widget.headerHeight,
            color: scheme.surfaceContainerHighest,
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final height = constraints.maxHeight;
                final rows = height.isFinite ? height.floor() : 0;
                if (rows != _rows) {
                  _rows = rows;
                  _compute(rows);
                }
                void jump(PointerEvent event) {
                  if (event.buttons & kPrimaryButton == 0) return;
                  _jumpTo(event.localPosition, height);
                }

                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Listener(
                    key: const ValueKey('log-overview-ruler'),
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: jump,
                    onPointerMove: jump,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size(LogOverviewRuler.width, height),
                        painter: LogOverviewRulerPainter(
                          marks: _marks,
                          revision: _revision,
                          errorColor: theme.errorColor,
                          warningColor: theme.warningColor,
                          searchColor: theme.searchCurrentMatchColor,
                          edgeColor: scheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints [marks], one per row, each at least [minMarkHeight] tall so a
/// single line still shows. Level marks fill the strip; while a search has
/// matches they keep the left half and the matches take the right, so
/// neither hides the other.
@visibleForTesting
class const LogOverviewRulerPainter({
  required final Uint8List marks,

  /// Changes whenever [marks] does.
  required final int revision,
  required final Color errorColor,
  required final Color warningColor,
  required final Color searchColor,
  required final Color edgeColor,
}) extends CustomPainter {
  static const double minMarkHeight = 2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 1, size.height),
      Paint()..color = edgeColor,
    );
    if (marks.isEmpty) return;
    final rowHeight = size.height / marks.length;
    final hasSearch = marks.any((bits) => bits & OverviewMark.searchMatch != 0);
    const left = 2.0;
    final right = size.width - 1;
    final levelRight = hasSearch ? (left + right) / 2 : right;

    final error = Paint()..color = errorColor;
    final warning = Paint()..color = warningColor;
    final search = Paint()..color = searchColor;

    // Runs of equal rows become one rect, so a solid block of errors is one
    // draw call rather than hundreds.
    void paintRuns(int Function(int bits) kindOf, double l, double r) {
      var runStart = 0;
      var runKind = 0;
      void flush(int end) {
        if (runKind == 0) return;
        final paint = switch (runKind) {
          OverviewMark.searchMatch => search,
          OverviewMark.error => error,
          _ => warning,
        };
        final top = runStart * rowHeight;
        final height = math.max(minMarkHeight, (end - runStart) * rowHeight);
        canvas.drawRect(Rect.fromLTWH(l, top, r - l, height), paint);
      }

      for (var row = 0; row < marks.length; row++) {
        final kind = kindOf(marks[row]);
        if (kind == runKind) continue;
        flush(row);
        runStart = row;
        runKind = kind;
      }
      flush(marks.length);
    }

    paintRuns(
      (bits) {
        if (bits & OverviewMark.error != 0) return OverviewMark.error;
        return bits & OverviewMark.warning;
      },
      left,
      levelRight,
    );
    if (hasSearch) {
      paintRuns((bits) => bits & OverviewMark.searchMatch, levelRight, right);
    }
  }

  @override
  bool shouldRepaint(LogOverviewRulerPainter old) =>
      old.revision != revision ||
      old.errorColor != errorColor ||
      old.warningColor != warningColor ||
      old.searchColor != searchColor ||
      old.edgeColor != edgeColor;
}
