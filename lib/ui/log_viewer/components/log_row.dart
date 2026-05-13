import 'package:flutter/material.dart';

import '../../../data/log_column.dart';
import '../../../data/log_entry.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/text_search_pattern.dart';
import '../log_viewer.dart';
import '../log_viewer_constants.dart';

class LogRow extends StatelessWidget {
  final LogEntry log;
  final int index;
  final double messageWidth;
  final bool rowSelectionMode;
  final bool isSelected;
  final double Function(LogColumn) widthOf;
  final bool Function(LogColumn) isVisible;
  final LogColumn? lastVisibleColumn;
  final TextSearchConfig search;
  final int? currentMatchLogIndex;
  final bool wrapText;
  final TextStyle monoStyle;
  final bool allowSelectionStart;
  final ValueChanged<PointerDownEvent>? onSelectionPointerDown;
  final ValueChanged<PointerMoveEvent>? onSelectionPointerMove;
  final String Function(LogColumn) contentValueForColumn;

  const LogRow({
    super.key,
    required this.log,
    required this.index,
    required this.messageWidth,
    required this.rowSelectionMode,
    required this.isSelected,
    required this.widthOf,
    required this.isVisible,
    required this.lastVisibleColumn,
    required this.search,
    required this.currentMatchLogIndex,
    required this.wrapText,
    required this.monoStyle,
    required this.allowSelectionStart,
    this.onSelectionPointerDown,
    this.onSelectionPointerMove,
    required this.contentValueForColumn,
  });

  Color _specialAccentColor(BuildContext context) {
    final logTheme = context.logViewTheme;
    return switch (log.type) {
      LogEntryType.started || LogEntryType.resumed => logTheme.statusLiveColor,
      LogEntryType.paused => logTheme.statusPausedColor,
      LogEntryType.stopped => logTheme.statusStoppedColor,
      LogEntryType.error => logTheme.errorColor,
      LogEntryType.notice => logTheme.inlineNoticeForeground,
      LogEntryType.log => logTheme.infoColor,
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

  String _specialMetaText() {
    return [
      if (log.timestamp.trim().isNotEmpty) log.timestamp.trim(),
      if (log.processName?.trim().isNotEmpty ?? false) log.processName!.trim(),
    ].join(' • ');
  }

  TextSpan _rowTerminatorSpan() {
    return const TextSpan(
      text: '\n ',
      style: TextStyle(fontSize: 0, height: 0, color: Colors.transparent),
    );
  }

  Widget _buildSelectableText(
    BuildContext context,
    String text,
    TextStyle style, {
    Color? highlightColor,
    TextOverflow? overflow,
    bool softWrap = false,
    bool appendRowTerminator = false,
  }) {
    final children = <InlineSpan>[];
    final pattern = TextSearchPattern.fromConfig(search);

    if (!pattern.isActive || highlightColor == null || !pattern.isValid) {
      children.add(TextSpan(text: text, style: style));
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

    final matches = pattern.allMatches(text);
    if (matches.isEmpty) {
      children.add(TextSpan(text: text, style: style));
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

    var start = 0;
    for (final match in matches) {
      if (match.start > start) {
        children.add(
          TextSpan(text: text.substring(start, match.start), style: style),
        );
      }
      children.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: style.copyWith(
            backgroundColor: highlightColor,
            color: context.logViewTheme.searchHighlightForeground,
          ),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      children.add(TextSpan(text: text.substring(start), style: style));
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

  Widget _levelCell(
    BuildContext context,
    String level,
    Color levelColor, {
    bool appendRowTerminator = false,
  }) {
    return SizedBox(
      width: widthOf(LogColumn.level),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Container(
          decoration: BoxDecoration(
            color: levelColor,
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.center,
          child: _buildSelectableText(
            context,
            level,
            monoStyle.copyWith(
              color: context.logViewTheme.logBadgeForeground,
              fontWeight: FontWeight.bold,
            ),
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
          appendRowTerminator: appendRowTerminator,
        ),
      ),
    );
  }

  Widget _selectionCell(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: kSelectionColumnWidth,
      child: Center(
        child: Icon(
          isSelected ? Icons.check_box : Icons.check_box_outline_blank,
          size: 18,
          color: isSelected
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildSpecialRow(
    BuildContext context, {
    Color? highlightColor,
    required bool isCurrentMatch,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = _specialAccentColor(context);
    final tileColor = accentColor.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.07 : 0.045,
    );
    final captionStyle = monoStyle.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontSize: (monoStyle.fontSize ?? 12) - 1,
    );
    final messageStyle = monoStyle.copyWith(color: colorScheme.onSurface);
    final metaText = _specialMetaText();

    return SelectionContainer.disabled(
      child: Container(
        color: isCurrentMatch
            ? context.logViewTheme.searchCurrentRowColor
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            key: const ValueKey('special-log-row'),
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: accentColor.withValues(
                    alpha: isCurrentMatch ? 0.32 : 0.18,
                  ),
                  width: 0.8,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_specialIcon(), size: 13, color: accentColor),
                  const SizedBox(width: 6),
                  _buildSelectableText(
                    context,
                    log.typeLabel,
                    monoStyle.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                    highlightColor: highlightColor,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (log.message.trim().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSelectableText(
                        context,
                        log.message,
                        messageStyle,
                        highlightColor: highlightColor,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (metaText.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: _buildSelectableText(
                        context,
                        metaText,
                        captionStyle,
                        highlightColor: highlightColor,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  @override
  Widget build(BuildContext context) {
    final logTheme = context.logViewTheme;
    final levelColor = logTheme.logLevelColor(log.level);
    final rowStyle = monoStyle.copyWith(color: levelColor);
    final visible = LogColumn.values
        .where((c) => !c.isExpandable && isVisible(c))
        .toList();

    final isCurrentMatch = currentMatchLogIndex == index;
    final selectedRowColor = Theme.of(
      context,
    ).colorScheme.primary.withValues(alpha: 0.10);

    final Color? highlightColor = searchQuery.isEmpty
        ? null
        : (isCurrentMatch
              ? logTheme.searchCurrentMatchColor
              : logTheme.searchMatchColor);

    if (log.isSpecialEntry) {
      final rowContent = _buildSpecialRow(
        context,
        highlightColor: highlightColor,
        isCurrentMatch: isCurrentMatch,
      );

      return MouseRegion(
        cursor: rowSelectionMode && allowSelectionStart
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        child: Listener(
          behavior: rowSelectionMode
              ? HitTestBehavior.opaque
              : HitTestBehavior.deferToChild,
          onPointerDown: rowSelectionMode && allowSelectionStart
              ? onSelectionPointerDown
              : null,
          onPointerMove: rowSelectionMode ? onSelectionPointerMove : null,
          child: rowContent,
        ),
      );
    }

    final rowContent = Container(
      color: isCurrentMatch
          ? logTheme.searchCurrentRowColor
          : (isSelected ? selectedRowColor : null),
      child: Row(
        children: [
          if (rowSelectionMode) ...[
            _selectionCell(context),
            const SizedBox(width: kColumnSpacing),
          ],
          for (final col in visible) ...[
            if (col == LogColumn.level)
              _levelCell(
                context,
                log.level,
                levelColor,
                appendRowTerminator: lastVisibleColumn == col,
              )
            else
              _fixedCell(
                context,
                contentValueForColumn(col),
                widthOf(col),
                rowStyle,
                highlightColor: highlightColor,
                appendRowTerminator: lastVisibleColumn == col,
              ),
            const SizedBox(width: kColumnSpacing),
          ],
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
                ),
              ),
            ),
        ],
      ),
    );

    return MouseRegion(
      cursor: rowSelectionMode && allowSelectionStart
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: Listener(
        behavior: rowSelectionMode
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        onPointerDown: rowSelectionMode && allowSelectionStart
            ? onSelectionPointerDown
            : null,
        onPointerMove: rowSelectionMode ? onSelectionPointerMove : null,
        child: GestureDetector(
          behavior: rowSelectionMode
              ? HitTestBehavior.opaque
              : HitTestBehavior.deferToChild,
          child: rowContent,
        ),
      ),
    );
  }
}
