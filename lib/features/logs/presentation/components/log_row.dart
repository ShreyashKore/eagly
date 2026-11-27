import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/log_column.dart';
import '../../data/models/log_entry.dart';
import '../../services/log_display_list.dart';
import '../../../../presentation/components/hover_builder.dart';
import '../../../../presentation/theme/app_theme.dart';
import '../../../../utils/log_entry_utils.dart';
import '../../../../utils/log_timestamp.dart';
import '../../../../utils/text_search_pattern.dart';
import '../log_viewer_constants.dart';
import 'log_viewer.dart';

class const LogRow({
  super.key,
  required final LogEntry log,
  required final int index,
  required final double messageWidth,
  required final bool isSelected,
  required final double Function(LogColumn) widthOf,
  required final bool Function(LogColumn) isVisible,
  required final LogColumn? lastVisibleColumn,
  required final TextSearchConfig search,
  required final int? currentMatchLogIndex,
  required final bool wrapText,
  required final TextStyle monoStyle,
  required final bool wholeRowSelectionEnabled,
  required final bool allowSelectionStart,
  final VoidCallback? onRowSelectionChanged,
  final ValueChanged<PointerDownEvent>? onSelectionPointerDown,
  final ValueChanged<PointerMoveEvent>? onSelectionPointerMove,
  final ValueChanged<Offset>? onRowContextMenuRequested,
  required final String Function(LogColumn) contentValueForColumn,

  /// How wide a special entry's divider runs: the viewport, so its centred
  /// label is on screen however wide the scrollable content is. Null fills
  /// whatever width the row is given.
  final double? specialRowWidth,

  /// The run of repeats this row heads, which puts a count chip at the end
  /// of its message; null for a single line.
  final LogRepeat? repeat,

  /// Unfolds or folds [repeat], from its chip.
  final VoidCallback? onToggleRepeat,
}) extends StatelessWidget {
  Color _specialAccentColor(BuildContext context) {
    final theme = context.eaglyTheme;
    return switch (log.type) {
      LogEntryType.started || LogEntryType.resumed => theme.statusLiveColor,
      LogEntryType.paused => theme.statusPausedColor,
      LogEntryType.stopped => theme.statusStoppedColor,
      LogEntryType.error => theme.errorColor,
      LogEntryType.notice => theme.inlineNoticeForeground,
      LogEntryType.log => theme.infoColor,
    };
  }

  IconData _specialIcon() {
    return switch (log.type) {
      LogEntryType.started => Icons.play_arrow_rounded,
      LogEntryType.resumed => Icons.play_circle_outline_rounded,
      LogEntryType.paused => Icons.pause_circle_outline_rounded,
      LogEntryType.stopped => Icons.stop_circle_outlined,
      LogEntryType.error => Icons.error_outline_rounded,
      LogEntryType.notice => Icons.info_outline_rounded,
      LogEntryType.log => Icons.article_outlined,
    };
  }

  /// `HH:mm:ss` of a special entry; the date and milliseconds say nothing a
  /// divider between runs needs. Shown as it is when it doesn't parse.
  String _specialTimeText() {
    final timestamp = log.timestamp.trim();
    return LogTimestampParts.tryParse(timestamp)?.time ?? timestamp;
  }

  /// Text that takes no space and draws nothing, yet is part of what a
  /// selection copies.
  static const _hiddenTextStyle = TextStyle(
    fontSize: 0,
    height: 0,
    color: Colors.transparent,
  );

  TextSpan _selectionSeparatorSpan(String text) {
    return TextSpan(text: text, style: _hiddenTextStyle);
  }

  TextSpan _cellSeparatorSpan() {
    return _selectionSeparatorSpan(' ');
  }

  TextSpan _rowTerminatorSpan() {
    return _selectionSeparatorSpan('\n ');
  }

  /// [text] as selectable spans, search matches highlighted. [styleRuns]
  /// styles it in pieces — each `(end, style)` covers the text up to `end`,
  /// the last ending at `text.length` — and a match spanning two pieces is
  /// highlighted in both.
  Widget _buildSelectableText(
    BuildContext context,
    String text,
    TextStyle style, {
    List<(int, TextStyle)>? styleRuns,
    Color? highlightColor,
    TextOverflow? overflow,
    bool softWrap = false,
    bool appendCellSeparator = false,
    bool appendRowTerminator = false,
    InlineSpan? trailing,
  }) {
    final children = <InlineSpan>[];
    final pattern = TextSearchPattern.fromConfig(search);
    final matches =
        !pattern.isActive || highlightColor == null || !pattern.isValid
        ? const <TextSearchMatch>[]
        : pattern.allMatches(text);
    final runs = styleRuns ?? [(text.length, style)];

    // Cut wherever a style run or a match starts or ends; each piece takes
    // its run's style, highlighted when it lies inside a match.
    final cuts = <int>{
      0,
      text.length,
      for (final (end, _) in runs) end,
      for (final match in matches) ...[match.start, match.end],
    }.toList()..sort();
    var runIndex = 0;
    var matchIndex = 0;
    for (var i = 0; i + 1 < cuts.length; i++) {
      final start = cuts[i];
      final end = cuts[i + 1];
      while (runIndex < runs.length - 1 && runs[runIndex].$1 <= start) {
        runIndex++;
      }
      while (matchIndex < matches.length && matches[matchIndex].end <= start) {
        matchIndex++;
      }
      final runStyle = runs[runIndex].$2;
      final inMatch =
          matchIndex < matches.length && matches[matchIndex].start <= start;
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: inMatch
              ? runStyle.copyWith(
                  backgroundColor: highlightColor,
                  color: context.eaglyTheme.searchHighlightForeground,
                )
              : runStyle,
        ),
      );
    }
    // An empty text is still one span.
    if (children.isEmpty) children.add(TextSpan(text: '', style: style));
    if (trailing != null) children.add(trailing);
    if (appendCellSeparator) {
      children.add(_cellSeparatorSpan());
    }
    if (appendRowTerminator) {
      children.add(_rowTerminatorSpan());
    }

    return Text.rich(
      TextSpan(style: style, children: children),
      style: style,
      overflow: overflow,
      softWrap: softWrap,
    );
  }

  /// The timestamp as its time of day, the milliseconds a step dimmer; the
  /// date moves to the column header. The date is still in the text — drawn
  /// at zero size, like the cell separators — so a selection copies the
  /// timestamp whole. One that doesn't parse is shown as it is.
  Widget _timestampCell(
    BuildContext context,
    String timestamp,
    TextStyle style, {
    Color? highlightColor,
    bool appendCellSeparator = false,
    bool appendRowTerminator = false,
  }) {
    final parts = LogTimestampParts.tryParse(timestamp);
    final dateEnd = parts?.datePrefix.length ?? 0;
    final timeEnd = dateEnd + (parts?.time.length ?? 0);
    return SizedBox(
      width: widthOf(LogColumn.timestamp),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: _buildSelectableText(
          context,
          timestamp,
          style,
          styleRuns: parts == null
              ? null
              : [
                  (dateEnd, style.merge(_hiddenTextStyle)),
                  (timeEnd, style),
                  (
                    timestamp.length,
                    style.copyWith(
                      color: context.eaglyTheme.timestampFractionColor,
                    ),
                  ),
                ],
          highlightColor: highlightColor,
          appendCellSeparator: appendCellSeparator,
          appendRowTerminator: appendRowTerminator,
        ),
      ),
    );
  }

  Widget _levelCell(
    BuildContext context,
    String level,
    Color levelColor, {
    bool appendCellSeparator = false,
    bool appendRowTerminator = false,
  }) {
    // A soft tint with the letter in the level colour: a solid block on
    // every row made the column the loudest thing on screen.
    return SizedBox(
      width: widthOf(LogColumn.level),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Container(
          key: const ValueKey('log-level-badge'),
          decoration: BoxDecoration(
            color: context.eaglyTheme.logBadgeFill(levelColor),
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.center,
          child: _buildSelectableText(
            context,
            level,
            monoStyle.copyWith(color: levelColor, fontWeight: FontWeight.w700),
            appendCellSeparator: appendCellSeparator,
            appendRowTerminator: appendRowTerminator,
          ),
        ),
      ),
    );
  }

  Widget _fixedCell(
    BuildContext context,
    String text,
    double width,
    TextStyle style, {
    Color? highlightColor,
    bool appendCellSeparator = false,
    bool appendRowTerminator = false,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: _buildSelectableText(
          context,
          text,
          style,
          highlightColor: highlightColor,
          appendCellSeparator: appendCellSeparator,
          appendRowTerminator: appendRowTerminator,
        ),
      ),
    );
  }

  Widget _selectionCell(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final child = SizedBox(
      width: kSelectionColumnWidth,
      child: Center(
        child: Icon(
          isSelected ? Icons.check_box : Icons.check_box_outline_blank,
          size: 18,
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.9)
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
    );
    if (wholeRowSelectionEnabled) {
      return child;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        key: ValueKey('row-selection-detector-$index'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: onSelectionPointerDown,
        onPointerMove: onSelectionPointerMove,
        child: child,
      ),
    );
  }

  // Approximates the row height from font metrics to size hit-test areas without
  // IntrinsicHeight (which would add an extra measure pass per row).
  double _approximateRowHeight() => estimateHeight(
    message: log.message,
    monoStyle: monoStyle,
    wrapText: wrapText,
    messageWidth: messageWidth,
  );

  /// A row's height from font metrics alone, without laying it out: one line
  /// of [monoStyle], or — with [wrapText] — as many as [message] wraps to in
  /// [messageWidth]. [textScaler] is the app zoom, when the caller needs the
  /// height as rendered.
  static double estimateHeight({
    required String message,
    required TextStyle monoStyle,
    required bool wrapText,
    required double messageWidth,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final fontSize = textScaler.scale(monoStyle.fontSize ?? 12);
    final lineHeight = monoStyle.height ?? 1.2;
    const verticalPadding = 4.0; // Padding(vertical: 2) → 2 top + 2 bottom
    if (!wrapText || messageWidth <= 0) {
      return fontSize * lineHeight + verticalPadding;
    }
    // Monospace char width ≈ 0.6× font size; estimate how many lines message wraps to.
    final charsPerLine = (messageWidth / (fontSize * 0.6)).clamp(
      1.0,
      double.infinity,
    );
    final lines = (message.length / charsPerLine).ceil().clamp(1, 200);
    return fontSize * lineHeight * lines + verticalPadding;
  }

  Widget _selectionDetector(int detectorIndex) {
    final enabled = allowSelectionStart && onSelectionPointerDown != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: Listener(
        key: ValueKey('row-selection-detector-$index-$detectorIndex'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: enabled ? onSelectionPointerDown : null,
        onPointerMove: onSelectionPointerMove,
        child: ColoredBox(
          color: Colors.transparent,
          child: SizedBox(
            width: LogViewer.columnSpacing,
            height: _approximateRowHeight(),
          ),
        ),
      ),
    );
  }

  Widget _columnGap(int detectorIndex) {
    if (wholeRowSelectionEnabled) {
      return const SizedBox(width: LogViewer.columnSpacing);
    }
    return _selectionDetector(detectorIndex);
  }

  /// A session marker ("Started", "Paused", …) as a divider between runs: a
  /// hairline across the row, broken by the label in the middle. A boxed
  /// tile read as a log line of its own; a rule reads as a seam.
  Widget _buildSpecialRow(
    BuildContext context, {
    Color? highlightColor,
    required bool isCurrentMatch,
  }) {
    final theme = context.eaglyTheme;
    final accentColor = _specialAccentColor(context);
    final lineColor = Theme.of(context).colorScheme.outlineVariant;
    final timeStyle = monoStyle.copyWith(
      color: theme.tertiaryTextColor,
      fontSize: (monoStyle.fontSize ?? 12) - 1,
    );
    final messageStyle = monoStyle.copyWith(color: theme.secondaryTextColor);
    final timeText = _specialTimeText();

    Widget line() => Expanded(child: Container(height: 1, color: lineColor));

    // Sized so the row never overflows, however narrow the pane: the type
    // label takes at most a third, the message the rest, and the time only
    // shows once there is room for it beside them.
    Widget label(double maxWidth) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_specialIcon(), size: 13, color: accentColor),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth / 3),
            child: _buildSelectableText(
              context,
              log.typeLabel,
              monoStyle.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w600,
              ),
              highlightColor: highlightColor,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (log.message.trim().isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: _buildSelectableText(
                context,
                log.message,
                messageStyle,
                highlightColor: highlightColor,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (timeText.isNotEmpty && maxWidth >= _specialRowTimeMinWidth) ...[
            const SizedBox(width: 8),
            _buildSelectableText(
              context,
              timeText,
              timeStyle,
              highlightColor: highlightColor,
            ),
          ],
        ],
      );
    }

    return SelectionContainer.disabled(
      child: Container(
        color: isCurrentMatch ? theme.searchCurrentRowColor : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Align(
          alignment: Alignment.centerLeft,
          // Across what the pane shows, not the whole scrollable width: with
          // wrapping off the content can be thousands of pixels wide, and a
          // label centred in that would start off screen.
          child: SizedBox(
            key: const ValueKey('special-log-row'),
            width: specialRowWidth == null
                ? null
                : math.max(0, specialRowWidth! - 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Each side keeps a stub of line, so even a label cut short
                // by a narrow pane still reads as a divider.
                const stub = _specialRowLineStub + _specialRowLabelGap;
                final labelMaxWidth = constraints.hasBoundedWidth
                    ? math.max(0.0, constraints.maxWidth - 2 * stub)
                    : double.infinity;
                if (labelMaxWidth < _specialRowLabelMinWidth) {
                  return Container(height: 1, color: lineColor);
                }
                return Row(
                  children: [
                    line(),
                    const SizedBox(width: _specialRowLabelGap),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: labelMaxWidth),
                      child: label(labelMaxWidth),
                    ),
                    const SizedBox(width: _specialRowLabelGap),
                    line(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// The chip's text for [repeat] — "×248 over 2.1 s" — for measuring the
  /// message column; see [_RepeatChip].
  static String repeatChipText(LogRepeat repeat) {
    final span = formatRepeatSpan(repeat.span);
    return span == null ? '×${repeat.count}' : '×${repeat.count} over $span';
  }

  static const double _specialRowLineStub = 12;
  static const double _specialRowLabelGap = 8;
  static const double _specialRowLabelMinWidth = 40;
  static const double _specialRowTimeMinWidth = 200;

  /// The level's color is carried by the badge and the message; repeating it
  /// on every cell made a row one solid stripe. The other cells step down:
  /// who logged it (package, tag) at secondary, when and which thread at
  /// tertiary — still there to scan, but the message reads first.
  TextStyle _cellStyle(EaglyTheme theme, LogColumn column, TextStyle message) {
    return switch (column) {
      LogColumn.pid ||
      LogColumn.tag => monoStyle.copyWith(color: theme.secondaryTextColor),
      LogColumn.timestamp ||
      LogColumn.tid => monoStyle.copyWith(color: theme.tertiaryTextColor),
      LogColumn.level || LogColumn.message => message,
    };
  }

  @override
  Widget build(BuildContext context) {
    final logTheme = context.eaglyTheme;
    final levelColor = logTheme.logLevelColor(log.level);
    final rowStyle = monoStyle.copyWith(color: levelColor);
    final visible = LogColumn.values
        .where((c) => !c.isExpandable && isVisible(c))
        .toList();

    final isCurrentMatch = currentMatchLogIndex == index;
    final selectedRowColor = Theme.of(context).colorScheme.primary
        .withValues(alpha: 0.10);

    final Color? highlightColor = search.query.isEmpty
        ? null
        : (isCurrentMatch
              ? logTheme.searchCurrentMatchColor
              : logTheme.searchMatchColor);

    if (log.isSpecialEntry) {
      return _buildSpecialRow(
        context,
        highlightColor: highlightColor,
        isCurrentMatch: isCurrentMatch,
      );
    }

    final rowCells = <Widget>[
      _selectionCell(context),
      for (final col in visible)
        if (col == LogColumn.level)
          _levelCell(
            context,
            log.level,
            levelColor,
            appendCellSeparator: lastVisibleColumn != col,
            appendRowTerminator: lastVisibleColumn == col,
          )
        else if (col == LogColumn.timestamp)
          _timestampCell(
            context,
            contentValueForColumn(col),
            _cellStyle(logTheme, col, rowStyle),
            highlightColor: highlightColor,
            appendCellSeparator: lastVisibleColumn != col,
            appendRowTerminator: lastVisibleColumn == col,
          )
        else
          _fixedCell(
            context,
            contentValueForColumn(col),
            widthOf(col),
            _cellStyle(logTheme, col, rowStyle),
            highlightColor: highlightColor,
            appendCellSeparator: lastVisibleColumn != col,
            appendRowTerminator: lastVisibleColumn == col,
          ),
      if (isVisible(LogColumn.message))
        SizedBox(
          width: messageWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: _buildSelectableText(
              context,
              log.message,
              rowStyle,
              highlightColor: highlightColor,
              softWrap: wrapText,
              appendRowTerminator: lastVisibleColumn == LogColumn.message,
              trailing: repeat == null
                  ? null
                  : WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _RepeatChip(
                          repeat: repeat!,
                          levelColor: levelColor,
                          monoStyle: monoStyle,
                          onPressed: onToggleRepeat,
                        ),
                      ),
                    ),
            ),
          ),
        ),
    ];

    final rowChildren = <Widget>[];
    for (var cellIndex = 0; cellIndex < rowCells.length; cellIndex++) {
      if (cellIndex > 0) {
        if (cellIndex == 1) {
          // Add an extra gap after the selection cell for better separation.
          rowChildren.add(const SizedBox(width: LogViewer.columnSpacing));
        } else {
          rowChildren.add(_columnGap(cellIndex - 1));
        }
      }
      rowChildren.add(rowCells[cellIndex]);
    }

    final rowContent = Container(
      color: isCurrentMatch
          ? logTheme.searchCurrentRowColor
          : (isSelected ? selectedRowColor : null),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rowChildren,
      ),
    );

    if (!wholeRowSelectionEnabled) {
      return rowContent;
    }

    final selectionEnabled =
        allowSelectionStart && onSelectionPointerDown != null;
    return MouseRegion(
      cursor: selectionEnabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: selectionEnabled ? onSelectionPointerDown : null,
        onPointerMove: selectionEnabled ? onSelectionPointerMove : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: onRowContextMenuRequested == null
              ? null
              : (details) => onRowContextMenuRequested!(details.globalPosition),
          child: rowContent,
        ),
      ),
    );
  }
}

// ── Repeat chip ──

/// How long a run of repeats lasted, as its chip says it: "340 ms", "2.1 s",
/// "4 min 12 s", "1 h 5 min". Null for no span or none at all, where "over"
/// would say nothing.
@visibleForTesting
String? formatRepeatSpan(Duration? span) {
  if (span == null || span <= Duration.zero) return null;
  final ms = span.inMilliseconds;
  if (ms < 1000) return '$ms ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)} s';
  if (span.inMinutes < 60) {
    final seconds = span.inSeconds % 60;
    return seconds == 0
        ? '${span.inMinutes} min'
        : '${span.inMinutes} min $seconds s';
  }
  final minutes = span.inMinutes % 60;
  return minutes == 0 ? '${span.inHours} h' : '${span.inHours} h $minutes min';
}

/// The count at the end of a folded run's message: "×248", and how long the
/// run lasted at the tertiary tier, tinted with the row's level colour like
/// its badge. A click unfolds the run in place; on an unfolded run's first
/// row it folds it back.
class const _RepeatChip({
  required final LogRepeat repeat,
  required final Color levelColor,
  required final TextStyle monoStyle,
  required final VoidCallback? onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.eaglyTheme;
    final fontSize = (monoStyle.fontSize ?? 12) - 1;
    final span = formatRepeatSpan(repeat.span);
    final tooltip = repeat.expanded
        ? 'Fold these ${repeat.count} lines into one row'
        : 'Show all ${repeat.count} lines';
    return SelectionContainer.disabled(
      child: Tooltip(
        message: tooltip,
        child: HoverBuilder(
          cursor: onPressed == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            key: const ValueKey('log-repeat-chip'),
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: theme.logBadgeFill(levelColor),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: hovered
                      ? levelColor.withValues(alpha: 0.5)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '×${repeat.count}',
                          style: TextStyle(
                            color: levelColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (span != null)
                          TextSpan(
                            text: ' over $span',
                            style: TextStyle(color: theme.tertiaryTextColor),
                          ),
                      ],
                    ),
                    style: monoStyle.copyWith(fontSize: fontSize, height: 1.3),
                    maxLines: 1,
                    softWrap: false,
                  ),
                  if (repeat.expanded) ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.unfold_less_rounded,
                      size: fontSize + 2,
                      color: levelColor,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
