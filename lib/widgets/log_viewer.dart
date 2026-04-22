import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../data/log_column.dart';
import '../data/log_entry.dart';
import '../theme/app_theme.dart';

class LogViewer extends StatefulWidget {
  static const double defaultUnwrappedMessageWidth = 1000;

  final List<LogEntry> logs;
  final ScrollController scrollController;
  final bool wrapText;
  final VoidCallback? onLogRowTap;

  /// The active inline search query (separate from the filter bar query).
  final String searchQuery;

  /// Whether the search is case-sensitive.
  final bool caseSensitive;

  /// Index (into [logs]) of the row that should be highlighted as the
  /// currently focused match. `null` means no focused match.
  final int? currentMatchLogIndex;

  /// Called whenever the user toggles column visibility so the parent can
  /// update its hidden-columns set used for search-match computation.
  final ValueChanged<Set<String>>? onHiddenColumnsChanged;

  /// Current column width overrides for this tab.
  final Map<String, double> columnWidths;

  /// Current hidden columns for this tab.
  final Set<String> hiddenColumns;

  /// Called when the user resizes columns so the parent can persist them in
  /// the active tab state.
  final ValueChanged<Map<String, double>>? onColumnWidthsChanged;

  const LogViewer({
    super.key,
    required this.logs,
    required this.scrollController,
    required this.wrapText,
    this.onLogRowTap,
    this.searchQuery = '',
    this.caseSensitive = false,
    this.currentMatchLogIndex,
    this.onHiddenColumnsChanged,
    this.columnWidths = const <String, double>{},
    this.hiddenColumns = const <String>{},
    this.onColumnWidthsChanged,
  });

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  static const double _columnSpacing = 8;
  static const double _columnDragHandleWidth = 8;
  static const double _messageMinWidth = 320;
  static const double _messageHorizontalPadding = 16;

  late Map<String, double> _widths;
  late Set<String> _hiddenColumns;
  Timer? _saveWidthsTimer;
  final ListController _listController = ListController();
  final ScrollController _horizontalScrollController = ScrollController();
  final TextPainter _messageWidthPainter = TextPainter(
    textDirection: TextDirection.ltr,
    maxLines: 1,
  );
  double _largestBuiltMessageWidth = 0;
  bool _messageWidthRefreshScheduled = false;

  TextStyle get _monoStyle => context.logViewTheme.logBodyStyle;

  /// Key placed on the currently-focused match row so we can scroll to it.
  final GlobalKey _currentMatchKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _widths = Map.of(widget.columnWidths);
    _hiddenColumns = Set.of(widget.hiddenColumns);
  }

  @override
  void didUpdateWidget(LogViewer old) {
    super.didUpdateWidget(old);
    if (widget.currentMatchLogIndex != old.currentMatchLogIndex &&
        widget.currentMatchLogIndex != null) {
      _scrollToMatch(widget.currentMatchLogIndex!);
    }
    if (widget.logs.isEmpty && old.logs.isNotEmpty) {
      _largestBuiltMessageWidth = 0;
    }
    if (!mapEquals(widget.columnWidths, old.columnWidths)) {
      _widths = Map.of(widget.columnWidths);
    }
    if (!setEquals(widget.hiddenColumns, old.hiddenColumns)) {
      _hiddenColumns = Set.of(widget.hiddenColumns);
    }
  }

  @override
  void dispose() {
    _flushWidths();
    _saveWidthsTimer?.cancel();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  /// Scrolls so the matched row is visible.
  ///
  /// **Strategy**: First check if the target row is already built (common
  /// when the next match is close to the current one). If so, just use
  /// [Scrollable.ensureVisible] — no jumping required.
  ///
  /// If the row isn't built, estimate a scroll offset relative to the last
  /// known position (proportional jump based on index delta). Only fall
  /// back to a full fraction-based jump when we have no prior anchor.
  /// Then retry up to a few frames until the key appears.
  Future<void> _scrollToMatch(int index) async {
    if (!widget.scrollController.hasClients) return;
    final totalItems = widget.logs.length;
    if (totalItems == 0) return;

    final sc = widget.scrollController;

    // // 1. Fast path: row already on screen — no jump needed.
    // await WidgetsBinding.instance.endOfFrame;
    // if (!mounted) return;
    // final ctxFast = _currentMatchKey.currentContext;
    // if (ctxFast != null && ctxFast.mounted) {
    //   await Scrollable.ensureVisible(
    //     ctxFast,
    //     duration: const Duration(milliseconds: 150),
    //     alignment: 0.4,
    //     curve: Curves.easeOut,
    //   );
    //   return;
    // }

    _listController.animateToItem(
      index: index,
      scrollController: sc,
      curve: (d) => Curves.easeOut,
      duration: (d) => Duration(milliseconds: 100),
      alignment: 0.3,
    );
  }

  LogColumn? get _lastVisibleColumn {
    for (final col in LogColumn.values.reversed) {
      if (_isVisible(col)) {
        return col;
      }
    }
    return null;
  }

  double get _fixedColumnsExtent {
    var width = 0.0;
    for (final col in _visibleFixedColumns) {
      width += _widthOf(col) + _columnSpacing;
    }
    return width;
  }

  double _messageColumnWidth(double viewportWidth) {
    if (!_isVisible(LogColumn.message)) return 0;
    if (widget.wrapText) {
      return math.max(_messageMinWidth, viewportWidth - _fixedColumnsExtent);
    }
    return math.max(
      LogViewer.defaultUnwrappedMessageWidth,
      math.max(_largestBuiltMessageWidth, _widths[LogColumn.message.name] ?? 0),
    );
  }

  double _measureMessageWidth(String message) {
    var widestLine = 0.0;
    for (final line in message.split('\n')) {
      _messageWidthPainter.text = TextSpan(
        text: line.isEmpty ? ' ' : line,
        style: _monoStyle,
      );
      _messageWidthPainter.layout();
      widestLine = math.max(widestLine, _messageWidthPainter.width);
    }
    return widestLine + _messageHorizontalPadding;
  }

  void _scheduleMessageWidthRefresh() {
    if (_messageWidthRefreshScheduled) return;
    _messageWidthRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _messageWidthRefreshScheduled = false;
      if (!mounted) return;
      setState(() {});
    });
  }

  void _recordBuiltMessageWidth(String message) {
    if (widget.wrapText || !_isVisible(LogColumn.message)) return;
    final measuredWidth = _measureMessageWidth(message);
    if (measuredWidth <= _largestBuiltMessageWidth) return;
    _largestBuiltMessageWidth = measuredWidth;
    _scheduleMessageWidthRefresh();
  }

  double _contentWidth(double viewportWidth) {
    final width =
        _fixedColumnsExtent +
        _messageColumnWidth(viewportWidth) +
        (!_isVisible(LogColumn.message) || widget.wrapText
            ? 0
            : _columnDragHandleWidth);
    return math.max(viewportWidth, width);
  }

  TextSpan _rowTerminatorSpan() {
    return const TextSpan(
      text: '\n ',
      style: TextStyle(fontSize: 0, height: 0, color: Colors.transparent),
    );
  }

  /// Builds selectable text and highlights every occurrence of
  /// [widget.searchQuery] inside [text] using [highlightColor].
  Widget _buildSelectableText(
    String text,
    TextStyle style, {
    Color? highlightColor,
    TextOverflow? overflow,
    bool softWrap = false,
    bool appendRowTerminator = false,
  }) {
    final query = widget.searchQuery;
    final children = <InlineSpan>[];

    if (query.isEmpty || highlightColor == null) {
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

    final searchIn = widget.caseSensitive ? text : text.toLowerCase();
    final queryNorm = widget.caseSensitive ? query : query.toLowerCase();

    if (!searchIn.contains(queryNorm)) {
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

    int start = 0;
    int idx = searchIn.indexOf(queryNorm, start);
    while (idx != -1) {
      if (idx > start) {
        children.add(TextSpan(text: text.substring(start, idx), style: style));
      }
      children.add(
        TextSpan(
          text: text.substring(idx, idx + queryNorm.length),
          style: style.copyWith(
            backgroundColor: highlightColor,
            color: context.logViewTheme.searchHighlightForeground,
          ),
        ),
      );
      start = idx + queryNorm.length;
      idx = searchIn.indexOf(queryNorm, start);
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

  void _flushWidths() {
    if (_saveWidthsTimer?.isActive ?? false) {
      _saveWidthsTimer!.cancel();
    }
    widget.onColumnWidthsChanged?.call(Map.of(_widths));
  }

  void _debounceSaveWidths() {
    _saveWidthsTimer?.cancel();
    _saveWidthsTimer = Timer(const Duration(milliseconds: 500), () {
      widget.onColumnWidthsChanged?.call(Map.of(_widths));
    });
  }

  bool _isVisible(LogColumn col) => !_hiddenColumns.contains(col.name);

  List<LogColumn> get _visibleFixedColumns =>
      LogColumn.values.where((c) => !c.isExpandable && _isVisible(c)).toList();

  double _widthOf(LogColumn col) => _widths[col.name] ?? col.defaultWidth;

  void _updateWidth(LogColumn col, double dx) {
    setState(() {
      _widths[col.name] = (_widthOf(col) + dx).clamp(
        LogColumn.minWidth,
        col.maxWidth,
      );
    });
    _debounceSaveWidths();
  }

  void _updateMessageWidth(double dx, double currentWidth) {
    setState(() {
      _widths[LogColumn.message.name] = math.max(
        _messageMinWidth,
        currentWidth + dx,
      );
    });
    _debounceSaveWidths();
  }

  void _showColumnVisibilityMenu(BuildContext context, Offset position) async {
    final result = await showMenu<LogColumn>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: LogColumn.values.where((c) => !c.isExpandable).map((col) {
        return PopupMenuItem<LogColumn>(
          value: col,
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              final visible = _isVisible(col);
              return CheckboxListTile.adaptive(
                dense: true,
                value: visible,
                title: Text(
                  col.label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontSize: 12),
                ),
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                onChanged: (_) {
                  setState(() {
                    if (visible) {
                      _hiddenColumns.add(col.name);
                    } else {
                      _hiddenColumns.remove(col.name);
                    }
                  });
                  widget.onHiddenColumnsChanged?.call(Set.of(_hiddenColumns));
                  setMenuState(() {});
                },
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        );
      }).toList(),
    );
    // If user taps on a column name directly (selects it as value), toggle it
    if (result != null) {
      setState(() {
        if (_isVisible(result)) {
          _hiddenColumns.add(result.name);
        } else {
          _hiddenColumns.remove(result.name);
        }
      });
      widget.onHiddenColumnsChanged?.call(Set.of(_hiddenColumns));
    }
  }

  String _cellValue(LogColumn col, LogEntry log) {
    return switch (col) {
      LogColumn.timestamp => log.timestamp,
      LogColumn.pid => log.packageName ?? log.pid,
      LogColumn.tid => log.tid,
      LogColumn.level => log.level,
      LogColumn.tag => log.tag,
      LogColumn.message => log.message,
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final messageWidth = _messageColumnWidth(viewportWidth);
        final contentWidth = _contentWidth(viewportWidth);

        return Scrollbar(
          controller: _horizontalScrollController,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              child: Column(
                children: [
                  _buildHeader(messageWidth),
                  const Divider(height: 1, thickness: 1),
                  Expanded(
                    child: SelectionArea(
                      child: Scrollbar(
                        controller: widget.scrollController,
                        child: GestureDetector(
                          onTap: widget.onLogRowTap,
                          child: SuperListView.builder(
                            controller: widget.scrollController,
                            listController: _listController,
                            itemCount: widget.logs.length,
                            itemBuilder: (_, i) {
                              final log = widget.logs[i];
                              _recordBuiltMessageWidth(log.message);
                              return _buildLogRow(log, i, messageWidth);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(double messageWidth) {
    final headerStyle = context.logViewTheme.logHeaderStyle;
    final visible = _visibleFixedColumns;

    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showColumnVisibilityMenu(context, details.globalPosition),
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        height: 28,
        child: Row(
          children: [
            for (final col in visible) ...[
              _headerCell(col.label, _widthOf(col), headerStyle),
              _columnDragHandle((dx) {
                _updateWidth(col, dx);
              }),
            ],
            if (_isVisible(LogColumn.message))
              Row(
                children: [
                  SizedBox(
                    width: messageWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(LogColumn.message.label, style: headerStyle),
                    ),
                  ),
                  if (!widget.wrapText)
                    _columnDragHandle((dx) {
                      _updateMessageWidth(dx, messageWidth);
                    }),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text, double width, TextStyle style) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: style, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  Widget _columnDragHandle(void Function(double dx) onDrag) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        behavior: HitTestBehavior.opaque,
        // This ensures the entire area captures touches
        child: SizedBox(
          width: _columnDragHandleWidth,
          child: Center(
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogRow(LogEntry log, int index, double messageWidth) {
    final logTheme = context.logViewTheme;
    final levelColor = logTheme.logLevelColor(log.level);
    final rowStyle = _monoStyle.copyWith(color: levelColor);
    final visible = _visibleFixedColumns;
    final lastVisibleColumn = _lastVisibleColumn;

    final isCurrentMatch = widget.currentMatchLogIndex == index;

    // Determine highlight colour for search matches in this row.
    // Current match → orange; other matching rows → yellow.
    final Color? highlightColor = widget.searchQuery.isEmpty
        ? null
        : (isCurrentMatch
              ? logTheme.searchCurrentMatchColor
              : logTheme.searchMatchColor);

    return Container(
      key: isCurrentMatch ? _currentMatchKey : null,
      color: isCurrentMatch ? logTheme.searchCurrentRowColor : null,
      child: Row(
        children: [
          for (final col in visible) ...[
            if (col == LogColumn.level)
              _levelCell(
                log.level,
                levelColor,
                appendRowTerminator: lastVisibleColumn == col,
              )
            else
              _fixedCell(
                _cellValue(col, log),
                _widthOf(col),
                rowStyle,
                highlightColor: highlightColor,
                appendRowTerminator: lastVisibleColumn == col,
              ),
            const SizedBox(width: _columnSpacing),
          ],
          if (_isVisible(LogColumn.message))
            SizedBox(
              width: messageWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: _buildSelectableText(
                  log.message,
                  rowStyle,
                  highlightColor: highlightColor,
                  softWrap: widget.wrapText,
                  appendRowTerminator: lastVisibleColumn == LogColumn.message,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _levelCell(
    String level,
    Color levelColor, {
    bool appendRowTerminator = false,
  }) {
    return SizedBox(
      width: _widthOf(LogColumn.level),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Container(
          decoration: BoxDecoration(
            color: levelColor,
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.center,
          child: _buildSelectableText(
            level,
            _monoStyle.copyWith(
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
          text,
          style,
          highlightColor: highlightColor,
          appendRowTerminator: appendRowTerminator,
        ),
      ),
    );
  }
}
