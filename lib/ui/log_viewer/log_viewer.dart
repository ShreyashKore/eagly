import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../data/log_column.dart';
import '../../data/log_entry.dart';
import '../../services/preferences_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/text_search_pattern.dart';
import 'components/log_row.dart';

enum LogViewerCopyAction { copyRow, copyMessage, copyTimestampAndMessage }

typedef LogRowSelectionStart = bool? Function(int index, {bool shiftPressed});

class LogViewer extends StatefulWidget {
  static const double columnSpacing = 8;
  static const double defaultUnwrappedMessageWidth = 1000;

  final List<LogEntry> logs;
  final ScrollController scrollController;
  final bool wrapText;
  final VoidCallback? onLogRowTap;
  final bool rowSelectionMode;
  final Set<int> selectedRowIndices;
  final LogRowSelectionStart? onRowSelectionStart;
  final ValueChanged<Set<int>>? onSelectedRowsChanged;
  final void Function(int index, bool selected)? onRowSelectionChanged;
  final Future<void> Function(int? index, LogViewerCopyAction action)?
  onRowCopyAction;
  final VoidCallback? onClearRowSelection;

  /// The active inline search query (separate from the filter bar query).
  final String searchQuery;

  /// Whether the search is case-sensitive.
  final bool caseSensitive;
  final bool wholeWord;
  final bool regexSearch;

  /// Index (into [logs]) of the row that should be highlighted as the
  /// currently focused match. `null` means no focused match.
  final int? currentMatchLogIndex;
  final ValueChanged<String?>? onSelectedTextChanged;
  final VoidCallback? onUserScroll;

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
    this.rowSelectionMode = false,
    this.selectedRowIndices = const <int>{},
    this.onRowSelectionStart,
    this.onSelectedRowsChanged,
    this.onRowSelectionChanged,
    this.onRowCopyAction,
    this.onClearRowSelection,
    this.searchQuery = '',
    this.caseSensitive = false,
    this.wholeWord = false,
    this.regexSearch = false,
    this.currentMatchLogIndex,
    this.onSelectedTextChanged,
    this.onUserScroll,
    this.onHiddenColumnsChanged,
    this.columnWidths = const <String, double>{},
    this.hiddenColumns = const <String>{},
    this.onColumnWidthsChanged,
  });

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  static const double _columnDragHandleWidth = 8;
  static const double _messageMinWidth = 320;
  static const double _messageHorizontalPadding = 16;

  late Map<String, double> _widths;
  late Set<String> _hiddenColumns;
  Timer? _saveWidthsTimer;
  final ListController _listController = ListController();
  final ScrollController _horizontalScrollController = ScrollController();
  final GlobalKey _rowViewportKey = GlobalKey();
  final TextPainter _messageWidthPainter = TextPainter(
    textDirection: TextDirection.ltr,
    maxLines: 1,
  );
  double _largestBuiltMessageWidth = 0;
  bool _messageWidthRefreshScheduled = false;

  // For pinch-to-zoom handling
  double? _scaleBaseFontSize;
  bool _isDraggingRowSelection = false;
  bool _dragSelectionValue = false;
  int? _dragSelectionPointer;
  int? _dragStartIndex;
  int? _dragCurrentIndex;
  Offset? _dragStartLocalPosition;
  Offset? _dragCurrentLocalPosition;
  Set<int> _dragBaseSelection = <int>{};
  Set<int> _dragAppliedSelection = <int>{};
  final Map<int, BuildContext> _rowContexts = <int, BuildContext>{};
  final SplayTreeMap<int, Rect> _rowBoundsByIndex = SplayTreeMap<int, Rect>();

  TextStyle get _monoStyle => _applyFont(context.logViewTheme.logBodyStyle);

  TextStyle _applyFont(TextStyle base) =>
      base.copyWith(fontSize: PreferencesService.logFontSize);

  bool get _textSelectionEnabled =>
      widget.selectedRowIndices.isEmpty && !_isDraggingRowSelection;

  bool get _wholeRowSelectionEnabled =>
      widget.rowSelectionMode && !_textSelectionEnabled;

  TextSearchPattern get _searchPattern => TextSearchPattern(
    query: widget.searchQuery,
    caseSensitive: widget.caseSensitive,
    wholeWord: widget.wholeWord,
    regex: widget.regexSearch,
  );

  /// Key placed on the currently-focused match row so we can scroll to it.
  final GlobalKey _currentMatchKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _widths = Map.of(widget.columnWidths);
    _hiddenColumns = Set.of(widget.hiddenColumns);
    widget.scrollController.addListener(_handleVerticalScroll);
    // Rebuild when the global log font size preference changes.
    PreferencesService.logFontSizeListenable.addListener(_onFontSizeChanged);
  }

  @override
  void didUpdateWidget(LogViewer old) {
    super.didUpdateWidget(old);
    final didSearchTargetChange =
        widget.currentMatchLogIndex != old.currentMatchLogIndex ||
        widget.searchQuery != old.searchQuery ||
        widget.caseSensitive != old.caseSensitive ||
        widget.wholeWord != old.wholeWord ||
        widget.regexSearch != old.regexSearch;
    if (didSearchTargetChange && widget.currentMatchLogIndex != null) {
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
    if (widget.scrollController != old.scrollController) {
      old.scrollController.removeListener(_handleVerticalScroll);
      widget.scrollController.addListener(_handleVerticalScroll);
    }
    if (!widget.rowSelectionMode && old.rowSelectionMode) {
      _resetDragSelectionState();
    }
    if (widget.selectedRowIndices.isNotEmpty && old.selectedRowIndices.isEmpty) {
      widget.onSelectedTextChanged?.call(null);
    }
  }

  @override
  void dispose() {
    _flushWidths();
    _saveWidthsTimer?.cancel();
    _horizontalScrollController.dispose();
    widget.scrollController.removeListener(_handleVerticalScroll);
    PreferencesService.logFontSizeListenable.removeListener(_onFontSizeChanged);
    super.dispose();
  }

  Rect? get _dragSelectionRect {
    final start = _dragStartLocalPosition;
    final current = _dragCurrentLocalPosition;
    if (!_isDraggingRowSelection || start == null || current == null) {
      return null;
    }
    return Rect.fromPoints(start, current);
  }

  void _onFontSizeChanged() {
    if (!mounted) return;
    // Changing font size affects measurements — force rebuild so sizes recalc.
    setState(() {
      _largestBuiltMessageWidth = 0;
    });
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

    for (var attempt = 0; attempt < 6; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (_revealCurrentMatchHorizontally(index)) {
        return;
      }
    }
  }

  void _handleVerticalScroll() {
    _refreshVisibleRowBounds();
    final localPosition = _dragCurrentLocalPosition;
    if (_isDraggingRowSelection && localPosition != null) {
      _applyDragSelectionForLocalPosition(localPosition);
    }
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
      width += _widthOf(col) + LogViewer.columnSpacing;
    }
    return width;
  }

  void _endRowSelectionDrag([int? pointer]) {
    if (pointer != null && _dragSelectionPointer != pointer) return;
    if (!_isDraggingRowSelection && _dragSelectionPointer == null) return;
    setState(_resetDragSelectionState);
  }

  bool _isSelectableRowIndex(int index) {
    return index >= 0 &&
        index < widget.logs.length &&
        widget.logs[index].isUserSelectable;
  }

  void _startRowSelectionDrag(int index, PointerDownEvent event) {
    if ((event.buttons & kPrimaryButton) == 0) {
      _endRowSelectionDrag(event.pointer);
      return;
    }
    if (widget.onRowSelectionStart == null) {
      _endRowSelectionDrag(event.pointer);
      return;
    }

    widget.onLogRowTap?.call();
    final localPosition = _globalToViewportLocal(event.position);
    final startIndex = localPosition != null
        ? (_indexForViewportY(localPosition.dy) ?? index)
        : index;
    if (!_isSelectableRowIndex(startIndex)) {
      _endRowSelectionDrag(event.pointer);
      return;
    }
    final shouldSelect = widget.onRowSelectionStart?.call(
      startIndex,
      shiftPressed: HardwareKeyboard.instance.isShiftPressed,
    );
    if (shouldSelect == null) {
      _endRowSelectionDrag(event.pointer);
      return;
    }

    final baseSelection = Set<int>.of(widget.selectedRowIndices);
    if (shouldSelect) {
      baseSelection.add(startIndex);
    } else {
      baseSelection.remove(startIndex);
    }

    setState(() {
      _isDraggingRowSelection = true;
      _dragSelectionValue = shouldSelect;
      _dragSelectionPointer = event.pointer;
      _dragStartIndex = startIndex;
      _dragCurrentIndex = startIndex;
      _dragStartLocalPosition = localPosition;
      _dragCurrentLocalPosition = localPosition;
      _dragBaseSelection = Set<int>.of(baseSelection);
      _dragAppliedSelection = Set<int>.of(baseSelection);
    });
  }

  void _extendRowSelectionDrag(int index, PointerMoveEvent event) {
    if (!widget.rowSelectionMode && !_isDraggingRowSelection) {
      _endRowSelectionDrag(event.pointer);
      return;
    }
    if (!_isDraggingRowSelection) return;
    if (_dragSelectionPointer != event.pointer) return;
    if ((event.buttons & kPrimaryButton) == 0) {
      _endRowSelectionDrag(event.pointer);
      return;
    }
    final localPosition = _globalToViewportLocal(event.position);
    if (localPosition == null) return;
    _applyDragSelectionForLocalPosition(localPosition);
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
      widestLine = math.max(widestLine, _measureTextWidth(line, _monoStyle));
    }
    return widestLine + _messageHorizontalPadding;
  }

  double _measureTextWidth(String text, TextStyle style) {
    _messageWidthPainter.text = TextSpan(
      text: text.isEmpty ? ' ' : text,
      style: style,
    );
    _messageWidthPainter.layout();
    return _messageWidthPainter.width;
  }

  double _columnStart(LogColumn column) {
    var offset = 0.0;

    for (final visibleColumn in _visibleFixedColumns) {
      if (visibleColumn == column) {
        return offset;
      }
      offset += _widthOf(visibleColumn) + LogViewer.columnSpacing;
    }

    return offset;
  }

  _HorizontalRevealTarget? _currentMatchTarget(int index) {
    if (index < 0 || index >= widget.logs.length) return null;

    final pattern = _searchPattern;
    if (!pattern.isActive || !pattern.isValid) return null;

    final log = widget.logs[index];
    if (log.isSpecialEntry) {
      final match = pattern.firstMatch(log.specialSearchableText);
      if (match != null) {
        return const _HorizontalRevealTarget(left: 0, right: 320);
      }
      return null;
    }

    final visibleColumns = [
      ..._visibleFixedColumns,
      if (_isVisible(LogColumn.message)) LogColumn.message,
    ];

    for (final column in visibleColumns) {
      final match = pattern.firstMatch(_cellValue(column, log));
      if (match == null) continue;

      final columnStart = _columnStart(column);
      if (column == LogColumn.level) {
        return _HorizontalRevealTarget(
          left: columnStart,
          right: columnStart + _widthOf(column),
        );
      }

      final padding = 8.0;
      final text = _cellValue(column, log);
      final linePrefix = _linePrefixUntilMatch(text, match.start);
      final matchedLineText = _matchedLineSegment(text, match.start, match.end);
      final textLeft =
          columnStart + padding + _measureTextWidth(linePrefix, _monoStyle);
      final textRight =
          textLeft +
          math.max(_measureTextWidth(matchedLineText, _monoStyle), 24.0);
      return _HorizontalRevealTarget(left: textLeft, right: textRight);
    }

    return null;
  }

  String _linePrefixUntilMatch(String text, int matchStart) {
    final lastLineBreak = text.lastIndexOf('\n', math.max(0, matchStart - 1));
    final lineStart = lastLineBreak == -1 ? 0 : lastLineBreak + 1;
    return text.substring(lineStart, matchStart);
  }

  String _matchedLineSegment(String text, int matchStart, int matchEnd) {
    final lineBreakIndex = text.indexOf('\n', matchStart);
    final lineEnd = lineBreakIndex == -1 ? text.length : lineBreakIndex;
    return text.substring(matchStart, math.min(matchEnd, lineEnd));
  }

  bool _revealCurrentMatchHorizontally(int index) {
    if (!_horizontalScrollController.hasClients) return false;

    final target = _currentMatchTarget(index);
    if (target == null) return false;

    final position = _horizontalScrollController.position;
    final viewportWidth = position.viewportDimension;
    final currentOffset = _horizontalScrollController.offset;
    final minOffset = math.max(0.0, target.left - 24);
    final maxOffset = math.max(0.0, target.right + 48 - viewportWidth);

    var desiredOffset = currentOffset;
    if (target.left < currentOffset + 24) {
      desiredOffset = minOffset;
    } else if (target.right > currentOffset + viewportWidth - 48) {
      desiredOffset = maxOffset;
    }

    final clampedOffset = desiredOffset.clamp(0.0, position.maxScrollExtent);
    if ((clampedOffset - currentOffset).abs() < 1) {
      return true;
    }

    _horizontalScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
    return true;
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
              return Row(
                children: [
                  Checkbox(
                    visualDensity: VisualDensity.compact,
                    value: visible,
                    onChanged: (_) {
                      setState(() {
                        if (visible) {
                          _hiddenColumns.add(col.name);
                        } else {
                          _hiddenColumns.remove(col.name);
                        }
                        widget.onHiddenColumnsChanged?.call(
                          Set.of(_hiddenColumns),
                        );
                        setMenuState(() {});
                        Navigator.of(context).pop();
                      });
                    },
                  ),
                  Text(
                    col.label,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontSize: 12),
                  ),
                ],
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

  void _registerRowContext(int index, BuildContext context) {
    _rowContexts[index] = context;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _rowContexts[index] != context) return;
      _updateRowBoundsForContext(index, context);
    });
  }

  void _unregisterRowContext(int index, BuildContext context) {
    if (_rowContexts[index] == context) {
      _rowContexts.remove(index);
      _rowBoundsByIndex.remove(index);
    }
  }

  void _refreshVisibleRowBounds() {
    final staleIndices = <int>[];
    for (final entry in _rowContexts.entries) {
      final updated = _updateRowBoundsForContext(entry.key, entry.value);
      if (!updated) {
        staleIndices.add(entry.key);
      }
    }
    for (final index in staleIndices) {
      _rowContexts.remove(index);
      _rowBoundsByIndex.remove(index);
    }
  }

  bool _updateRowBoundsForContext(int index, BuildContext context) {
    final rect = _measureRowRect(context);
    if (rect == null) return false;
    _rowBoundsByIndex[index] = rect;
    return true;
  }

  Rect? _measureRowRect(BuildContext rowContext) {
    final viewportContext = _rowViewportKey.currentContext;
    if (!mounted || viewportContext == null || !viewportContext.mounted) {
      return null;
    }
    if (!rowContext.mounted) {
      return null;
    }
    final viewportRenderBox = viewportContext.findRenderObject() as RenderBox?;
    final rowRenderBox = rowContext.findRenderObject() as RenderBox?;
    if (viewportRenderBox == null ||
        rowRenderBox == null ||
        !viewportRenderBox.attached ||
        !rowRenderBox.attached) {
      return null;
    }

    final topLeft = rowRenderBox.localToGlobal(
      Offset.zero,
      ancestor: viewportRenderBox,
    );
    final bottomRight = rowRenderBox.localToGlobal(
      rowRenderBox.size.bottomRight(Offset.zero),
      ancestor: viewportRenderBox,
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  Offset? _globalToViewportLocal(Offset globalPosition) {
    final viewportContext = _rowViewportKey.currentContext;
    if (!mounted || viewportContext == null || !viewportContext.mounted) {
      return null;
    }
    final viewportRenderBox = viewportContext.findRenderObject() as RenderBox?;
    if (viewportRenderBox == null || !viewportRenderBox.attached) {
      return null;
    }
    return viewportRenderBox.globalToLocal(globalPosition);
  }

  int? _indexForViewportY(double viewportY) {
    if (_rowBoundsByIndex.isEmpty) return null;

    int? previousIndex;
    Rect? previousRect;
    for (final entry in _rowBoundsByIndex.entries) {
      final rect = entry.value;
      if (viewportY < rect.top) {
        if (previousRect == null) {
          return entry.key;
        }
        final distanceToPrevious = (viewportY - previousRect.bottom).abs();
        final distanceToCurrent = (rect.top - viewportY).abs();
        return distanceToPrevious <= distanceToCurrent
            ? previousIndex
            : entry.key;
      }
      if (viewportY <= rect.bottom) {
        return entry.key;
      }
      previousIndex = entry.key;
      previousRect = rect;
    }
    return previousIndex;
  }

  Set<int> _selectionForDragRange(int currentIndex) {
    final startIndex = _dragStartIndex;
    if (startIndex == null) {
      return Set<int>.of(_dragAppliedSelection);
    }

    final rangeStart = math.min(startIndex, currentIndex);
    final rangeEnd = math.max(startIndex, currentIndex);
    final selection = Set<int>.of(_dragBaseSelection);
    for (var index = rangeStart; index <= rangeEnd; index++) {
      if (!_isSelectableRowIndex(index)) {
        continue;
      }
      if (_dragSelectionValue) {
        selection.add(index);
      } else {
        selection.remove(index);
      }
    }
    return selection;
  }

  void _applySelectedRows(Set<int> desiredSelection) {
    final changed = !setEquals(_dragAppliedSelection, desiredSelection);
    if (!changed) return;

    if (widget.onSelectedRowsChanged != null) {
      widget.onSelectedRowsChanged!(desiredSelection);
    } else {
      final additions = desiredSelection.difference(_dragAppliedSelection);
      final removals = _dragAppliedSelection.difference(desiredSelection);
      for (final index in additions) {
        widget.onRowSelectionChanged?.call(index, true);
      }
      for (final index in removals) {
        widget.onRowSelectionChanged?.call(index, false);
      }
    }
    _dragAppliedSelection = Set<int>.of(desiredSelection);
  }

  void _applyDragSelectionForLocalPosition(Offset localPosition) {
    final currentIndex =
        _indexForViewportY(localPosition.dy) ??
        _dragCurrentIndex ??
        _dragStartIndex;
    setState(() {
      _dragCurrentLocalPosition = localPosition;
      _dragCurrentIndex = currentIndex;
    });

    if (currentIndex == null) return;
    final desiredSelection = _selectionForDragRange(currentIndex);
    _applySelectedRows(desiredSelection);
  }

  void _resetDragSelectionState() {
    _isDraggingRowSelection = false;
    _dragSelectionPointer = null;
    _dragSelectionValue = false;
    _dragStartIndex = null;
    _dragCurrentIndex = null;
    _dragStartLocalPosition = null;
    _dragCurrentLocalPosition = null;
    _dragBaseSelection = <int>{};
    _dragAppliedSelection = <int>{};
  }

  Future<void> _showRowCopyMenu({
    required Offset globalPosition,
    required int index,
  }) async {
    final action = await showMenu<LogViewerCopyAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(
          value: LogViewerCopyAction.copyRow,
          child: Text('Copy'),
        ),
        PopupMenuItem(
          value: LogViewerCopyAction.copyMessage,
          child: Text('Copy message'),
        ),
        PopupMenuItem(
          value: LogViewerCopyAction.copyTimestampAndMessage,
          child: Text('Copy time + message'),
        ),
      ],
    );
    if (action == null) return;
    await widget.onRowCopyAction?.call(index, action);
  }

  Widget _buildRowSelectionToolbar() {
    final count = widget.selectedRowIndices.length;
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Material(
          key: const ValueKey('row-selection-toolbar'),
          elevation: 6,
          color: theme.colorScheme.surfaceContainerHigh,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    count == 1 ? '1 row selected' : '$count rows selected',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: widget.onClearRowSelection,
                  icon: const Icon(Icons.clear_all_rounded),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final messageWidth = _messageColumnWidth(viewportWidth);
        final contentWidth = _contentWidth(viewportWidth);
        final logViewport = _buildLogViewport(messageWidth);
        final interactiveViewport = _textSelectionEnabled
            ? SelectionArea(
                key: const ValueKey('log-viewer-selection-area'),
                onSelectionChanged: (selectedContent) {
                  widget.onSelectedTextChanged?.call(
                    selectedContent?.plainText,
                  );
                },
                contextMenuBuilder: (ctx, selectableRegionState) {
                  return AdaptiveTextSelectionToolbar.selectableRegion(
                    selectableRegionState: selectableRegionState,
                  );
                },
                child: logViewport,
              )
            : logViewport;

        return Stack(
          children: [
            Scrollbar(
              controller: _horizontalScrollController,
              thumbVisibility: true,
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
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification.metrics.axis != Axis.vertical) {
                              return false;
                            }
                            final isUserScroll =
                                notification is UserScrollNotification ||
                                notification is ScrollStartNotification &&
                                    notification.dragDetails != null ||
                                notification is ScrollUpdateNotification &&
                                    notification.dragDetails != null ||
                                notification is OverscrollNotification &&
                                    notification.dragDetails != null;
                            if (isUserScroll) {
                              widget.onUserScroll?.call();
                            }
                            return false;
                          },
                          child: Scrollbar(
                            controller: widget.scrollController,
                            thumbVisibility: true,
                            child: GestureDetector(
                              // Support pinch-to-zoom on trackpads / touchpads to change log font size.
                              onScaleStart: (details) {
                                // Record the base font size at gesture start.
                                _scaleBaseFontSize =
                                    PreferencesService.logFontSize;
                              },
                              onScaleUpdate: (details) {
                                // Only react when there are multiple pointers (pinch gesture).
                                if (details.pointerCount < 2) return;
                                final base =
                                    _scaleBaseFontSize ??
                                    PreferencesService.logFontSize;
                                final target = base * details.scale;
                                // Use integer steps to avoid jitter; PreferencesService
                                // will clamp and avoid redundant writes.
                                final rounded = target.roundToDouble();
                                PreferencesService.logFontSize = rounded;
                              },
                              onScaleEnd: (_) {
                                _scaleBaseFontSize = null;
                              },
                              child: Listener(
                                onPointerDown: _wholeRowSelectionEnabled
                                    ? null
                                    : (event) {
                                        if ((event.buttons & kPrimaryButton) ==
                                            0) {
                                          return;
                                        }
                                        widget.onLogRowTap?.call();
                                      },
                                onPointerUp: (event) =>
                                    _endRowSelectionDrag(event.pointer),
                                onPointerCancel: (event) =>
                                    _endRowSelectionDrag(event.pointer),
                                child: interactiveViewport,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Sticky column-visibility button pinned to the top-right corner.
            // It stays in place regardless of horizontal scroll.
            Positioned(
              top: 0,
              right: 0,
              height: 29, // match header + divider height (28 + 1)
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Tooltip(
                  message: 'Column visibility',
                  child: InkWell(
                    child: Icon(
                      Icons.view_column_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onTap: () {
                      // Show popup anchored to the button's position.
                      final renderBox =
                          context.findRenderObject() as RenderBox?;
                      final offset =
                          renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
                      final size = renderBox?.size ?? Size.zero;
                      _showColumnVisibilityMenu(
                        context,
                        Offset(offset.dx + size.width - 4, offset.dy + 28),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (widget.selectedRowIndices.isNotEmpty) _buildRowSelectionToolbar(),
          ],
        );
      },
    );
  }

  Widget _buildHeader(double messageWidth) {
    final headerStyle = _applyFont(context.logViewTheme.logHeaderStyle);
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
    return LogRow(
      key: widget.currentMatchLogIndex == index ? _currentMatchKey : null,
      log: log,
      index: index,
      messageWidth: messageWidth,
      rowSelectionMode: widget.rowSelectionMode,
      isSelected: widget.selectedRowIndices.contains(index),
      widthOf: _widthOf,
      isVisible: _isVisible,
      lastVisibleColumn: _lastVisibleColumn,
      searchQuery: widget.searchQuery,
      caseSensitive: widget.caseSensitive,
      wholeWord: widget.wholeWord,
      regexSearch: widget.regexSearch,
      currentMatchLogIndex: widget.currentMatchLogIndex,
      wrapText: widget.wrapText,
      monoStyle: _monoStyle,
      wholeRowSelectionEnabled: _wholeRowSelectionEnabled,
      allowSelectionStart: log.isUserSelectable,
      onSelectionPointerDown: (event) => _startRowSelectionDrag(index, event),
      onSelectionPointerMove: (event) => _extendRowSelectionDrag(index, event),
      onRowContextMenuRequested: (globalPosition) {
        _showRowCopyMenu(globalPosition: globalPosition, index: index);
      },
      contentValueForColumn: (col) => _cellValue(col, log),
    );
  }

  Widget _buildLogViewport(double messageWidth) {
    final selectionRect = _dragSelectionRect;
    return Stack(
      key: _rowViewportKey,
      fit: StackFit.expand,
      children: [
        _buildLogList(messageWidth),
        if (selectionRect != null)
          Positioned.fromRect(
            rect: selectionRect,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('row-selection-rect'),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLogList(double messageWidth) {
    return SuperListView.builder(
      controller: widget.scrollController,
      listController: _listController,
      itemCount: widget.logs.length,
      itemBuilder: (_, i) {
        final log = widget.logs[i];
        _recordBuiltMessageWidth(log.message);
        return _RowBoundsReporter(
          index: i,
          onMounted: _registerRowContext,
          onUnmounted: _unregisterRowContext,
          key: ValueKey(log.id),
          child: _buildLogRow(log, i, messageWidth),
        );
      },
    );
  }
}


class _HorizontalRevealTarget {
  const _HorizontalRevealTarget({required this.left, required this.right});

  final double left;
  final double right;
}

class _RowBoundsReporter extends StatefulWidget {
  const _RowBoundsReporter({
    required this.index,
    required this.onMounted,
    required this.onUnmounted,
    required this.child,
    required super.key,
  });

  final int index;
  final void Function(int index, BuildContext context) onMounted;
  final void Function(int index, BuildContext context) onUnmounted;
  final Widget child;

  @override
  State<_RowBoundsReporter> createState() => _RowBoundsReporterState();
}

class _RowBoundsReporterState extends State<_RowBoundsReporter> {
  @override
  void initState() {
    super.initState();
    _reportMounted();
  }

  @override
  void didUpdateWidget(covariant _RowBoundsReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      widget.onUnmounted(oldWidget.index, context);
    }
    _reportMounted();
  }

  @override
  void dispose() {
    widget.onUnmounted(widget.index, context);
    super.dispose();
  }

  void _reportMounted() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onMounted(widget.index, context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
