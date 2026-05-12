import 'package:flutter/material.dart';
import '../../../data/log_column.dart';
import '../../../data/log_entry.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/text_search_pattern.dart';
import '../log_viewer.dart';

class LogRow extends StatelessWidget {
  final LogEntry log;
  final int index;
  final double messageWidth;
  final bool rowSelectionMode;
  final bool isSelected;
  final double Function(LogColumn) widthOf;
  final bool Function(LogColumn) isVisible;
  final LogColumn? lastVisibleColumn;
  final String searchQuery;
  final bool caseSensitive;
  final bool wholeWord;
  final bool regexSearch;
  final int? currentMatchLogIndex;
  final bool wrapText;
  final TextStyle monoStyle;
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
    required this.searchQuery,
    required this.caseSensitive,
    required this.wholeWord,
    required this.regexSearch,
    required this.currentMatchLogIndex,
    required this.wrapText,
    required this.monoStyle,
    this.onSelectionPointerDown,
    this.onSelectionPointerMove,
    required this.contentValueForColumn,
  });

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
    final pattern = TextSearchPattern(
      query: searchQuery,
      caseSensitive: caseSensitive,
      wholeWord: wholeWord,
      regex: regexSearch,
    );

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
      width: LogViewer.selectionColumnWidth,
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

    final rowContent = Container(
      color: isCurrentMatch
          ? logTheme.searchCurrentRowColor
          : (isSelected ? selectedRowColor : null),
      child: Row(
        children: [
          if (rowSelectionMode) ...[
            _selectionCell(context),
            const SizedBox(width: LogViewer.columnSpacing),
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
            const SizedBox(width: LogViewer.columnSpacing),
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
      cursor: rowSelectionMode ? SystemMouseCursors.click : MouseCursor.defer,
      child: Listener(
        behavior: rowSelectionMode
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        onPointerDown: rowSelectionMode ? onSelectionPointerDown : null,
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
