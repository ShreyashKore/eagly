import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../data/log_column.dart';
import '../data/log_entry.dart';
import '../services/preferences_service.dart';
import '../utils/log_utils.dart';

class LogViewer extends StatefulWidget {
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
  });

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  late Map<String, double> _widths;
  late Set<String> _hiddenColumns;
  Timer? _saveWidthsTimer;
  final ListController _listController = ListController();

  late TextStyle _monoStyle;

  /// Key placed on the currently-focused match row so we can scroll to it.
  final GlobalKey _currentMatchKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _widths = Map.of(PreferencesService.columnWidths);
    _hiddenColumns = Set.of(PreferencesService.hiddenColumns);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _monoStyle = GoogleFonts.notoSansMono(fontSize: 12, height: 1.2);
  }

  @override
  void didUpdateWidget(LogViewer old) {
    super.didUpdateWidget(old);
    if (widget.currentMatchLogIndex != old.currentMatchLogIndex &&
        widget.currentMatchLogIndex != null) {
      _scrollToMatch(widget.currentMatchLogIndex!);
    }
  }

  @override
  void dispose() {
    _flushWidths();
    _saveWidthsTimer?.cancel();
    super.dispose();
  }

  /// The log-list index of the row that was last successfully scrolled to.
  int? _lastScrolledIndex;

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
    final maxScroll = sc.position.maxScrollExtent;

    // 1. Fast path: row already on screen — no jump needed.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final ctxFast = _currentMatchKey.currentContext;
    if (ctxFast != null) {
      // ignore: use_build_context_synchronously
      await Scrollable.ensureVisible(
        ctxFast,
        duration: const Duration(milliseconds: 150),
        alignment: 0.4,
        curve: Curves.easeOut,
      );
      _lastScrolledIndex = index;
      return;
    }

    _listController.jumpToItem(index: index, scrollController: sc, alignment: 0);
    return;
    // 2. Row not built — estimate offset.
    if (_lastScrolledIndex != null && _lastScrolledIndex != index) {
      // Relative jump: use the delta between the old and new index,
      // scaled by (maxScroll / totalItems) as an approximate row height.
      final approxRowHeight = maxScroll / totalItems;
      final delta = (index - _lastScrolledIndex!) * approxRowHeight;
      sc.jumpTo((sc.offset + delta).clamp(0.0, maxScroll));
    } else {
      // No anchor — fraction-based jump.
      final fraction = index / totalItems;
      sc.jumpTo((fraction * maxScroll).clamp(0.0, maxScroll));
    }

    // 3. Retry loop until the key is built.
    for (int attempt = 0; attempt < 10; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final ctx = _currentMatchKey.currentContext;
      if (ctx != null) {
        // ignore: use_build_context_synchronously
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 150),
          alignment: 0.4,
          curve: Curves.easeOut,
        );
        _lastScrolledIndex = index;
        return;
      }

      // Nudge by one viewport towards the target.
      final viewportHeight = sc.position.viewportDimension;
      final targetEstimate = (index / totalItems) * maxScroll;
      final diff = targetEstimate - sc.offset;
      if (diff.abs() < 1) break; // close enough, key just isn't there
      final nudge = diff.clamp(-viewportHeight, viewportHeight);
      sc.jumpTo((sc.offset + nudge).clamp(0.0, maxScroll));
    }

    _lastScrolledIndex = index;
  }

  /// Builds a [RichText] that highlights every occurrence of [widget.searchQuery]
  /// inside [text] using [highlightColor].  When the search query is empty, or
  /// there is no match in this cell, a plain [Text] is returned instead.
  Widget _buildHighlightedText(
    String text,
    TextStyle style, {
    required Color highlightColor,
    TextOverflow overflow = TextOverflow.ellipsis,
    int? maxLines = 1,
    bool softWrap = false,
  }) {
    final query = widget.searchQuery;
    if (query.isEmpty) {
      return Text(
        text,
        style: style,
        overflow: overflow,
        maxLines: maxLines,
        softWrap: softWrap,
      );
    }

    final searchIn =
        widget.caseSensitive ? text : text.toLowerCase();
    final queryNorm =
        widget.caseSensitive ? query : query.toLowerCase();

    if (!searchIn.contains(queryNorm)) {
      return Text(
        text,
        style: style,
        overflow: overflow,
        maxLines: maxLines,
        softWrap: softWrap,
      );
    }

    final spans = <TextSpan>[];
    int start = 0;
    int idx = searchIn.indexOf(queryNorm, start);
    while (idx != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: style));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + queryNorm.length),
        style: style.copyWith(
          backgroundColor: highlightColor,
          color: Colors.black,
        ),
      ));
      start = idx + queryNorm.length;
      idx = searchIn.indexOf(queryNorm, start);
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }

    return RichText(
      text: TextSpan(children: spans),
      overflow: overflow,
      maxLines: maxLines,
      softWrap: softWrap,
    );
  }

  void _flushWidths() {
    if (_saveWidthsTimer?.isActive ?? false) {
      _saveWidthsTimer!.cancel();
      PreferencesService.columnWidths = _widths;
    }
  }

  void _debounceSaveWidths() {
    _saveWidthsTimer?.cancel();
    _saveWidthsTimer = Timer(const Duration(milliseconds: 500), () {
      PreferencesService.columnWidths = _widths;
    });
  }

  bool _isVisible(LogColumn col) => !_hiddenColumns.contains(col.name);

  List<LogColumn> get _visibleFixedColumns => LogColumn.values
      .where((c) => !c.isExpandable && _isVisible(c))
      .toList();

  double _widthOf(LogColumn col) => _widths[col.name] ?? col.defaultWidth;

  void _updateWidth(LogColumn col, double dx) {
    setState(() {
      _widths[col.name] =
          (_widthOf(col) + dx).clamp(LogColumn.minWidth, col.maxWidth);
    });
    _debounceSaveWidths();
  }

  void _showColumnVisibilityMenu(BuildContext context, Offset position) async {
    final result = await showMenu<LogColumn>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: LogColumn.values.where((c) => !c.isExpandable).map((col) {
        return PopupMenuItem<LogColumn>(
          value: col,
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              final visible = _isVisible(col);
              return CheckboxListTile.adaptive(
                dense: true,
                value: visible,
                title: Text(col.label, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                minVerticalPadding: 0,
                onChanged: (_) {
                  setState(() {
                    if (visible) {
                      _hiddenColumns.add(col.name);
                    } else {
                      _hiddenColumns.remove(col.name);
                    }
                    PreferencesService.hiddenColumns = _hiddenColumns;
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
        PreferencesService.hiddenColumns = _hiddenColumns;
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
    return Column(
      children: [
        _buildHeader(),
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
                  itemBuilder: (_, i) => _buildLogRow(widget.logs[i], i),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final headerStyle = TextStyle();
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(LogColumn.message.label, style: headerStyle),
                ),
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
        behavior: HitTestBehavior.opaque, // This ensures the entire area captures touches
        child: SizedBox(
          width: 8,
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

  Widget _buildLogRow(LogEntry log, int index) {
    final levelColor = LogUtils.colorForLevel(log.level);
    final rowStyle = _monoStyle.copyWith(color: levelColor);
    final visible = _visibleFixedColumns;

    final isCurrentMatch = widget.currentMatchLogIndex == index;

    // Determine highlight colour for search matches in this row.
    // Current match → orange; other matching rows → yellow.
    final Color? highlightColor = widget.searchQuery.isEmpty
        ? null
        : (isCurrentMatch ? Colors.orange[400] : Colors.yellow[400]);

    return RepaintBoundary(
      child: Container(
        key: isCurrentMatch ? _currentMatchKey : null,
        color: isCurrentMatch
            ? Colors.orange.withValues(alpha: 0.12)
            : null,
        child: Row(
          children: [
            for (final col in visible) ...[
              if (col == LogColumn.level)
                _levelCell(log.level, levelColor)
              else
                _fixedCell(
                  _cellValue(col, log),
                  _widthOf(col),
                  rowStyle,
                  highlightColor: highlightColor,
                ),
              const SizedBox(width: 8),
            ],
            if (_isVisible(LogColumn.message))
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: highlightColor != null
                      ? _buildHighlightedText(
                          log.message,
                          rowStyle,
                          highlightColor: highlightColor,
                          overflow: widget.wrapText
                              ? TextOverflow.clip
                              : TextOverflow.ellipsis,
                          maxLines: widget.wrapText ? null : 1,
                          softWrap: widget.wrapText,
                        )
                      : Text(
                          log.message,
                          style: rowStyle,
                          softWrap: widget.wrapText,
                          overflow:
                              widget.wrapText ? null : TextOverflow.ellipsis,
                          maxLines: widget.wrapText ? null : 1,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _levelCell(String level, Color levelColor) {
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
          child: Text(
            level,
            style: _monoStyle.copyWith(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  Widget _fixedCell(String text, double width, TextStyle style,
      {Color? highlightColor}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: highlightColor != null
            ? _buildHighlightedText(text, style, highlightColor: highlightColor)
            : Text(
                text,
                style: style,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
      ),
    );
  }
}
