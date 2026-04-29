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

enum LogViewerCopyAction { copyMessage, copyTimestampAndMessage }

typedef LogRowSelectionStart = bool? Function(int index, {bool shiftPressed});

class LogViewer extends StatefulWidget {
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
  final Future<void> Function(int index, LogViewerCopyAction action)?
  onRowCopyAction;

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
    this.rowSelectionMode = false,
    this.selectedRowIndices = const <int>{},
    this.onRowSelectionStart,
    this.onSelectedRowsChanged,
    this.onRowSelectionChanged,
    this.onRowCopyAction,
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
  static const double _selectionColumnWidth = 40;
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
    if (widget.scrollController != old.scrollController) {
      old.scrollController.removeListener(_handleVerticalScroll);
      widget.scrollController.addListener(_handleVerticalScroll);
    }
    if (!widget.rowSelectionMode && old.rowSelectionMode) {
      _resetDragSelectionState();
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
    var width = widget.rowSelectionMode
        ? _selectionColumnWidth + _columnSpacing
        : 0.0;
    for (final col in _visibleFixedColumns) {
      width += _widthOf(col) + _columnSpacing;
    }
    return width;
  }

  void _endRowSelectionDrag([int? pointer]) {
    if (pointer != null && _dragSelectionPointer != pointer) return;
    if (!_isDraggingRowSelection && _dragSelectionPointer == null) return;
    setState(_resetDragSelectionState);
  }

  void _startRowSelectionDrag(int index, PointerDownEvent event) {
    if (!widget.rowSelectionMode) return;
    if ((event.buttons & kPrimaryButton) == 0) return;

    widget.onLogRowTap?.call();
    final localPosition = _globalToViewportLocal(event.position);
    final startIndex = localPosition != null
        ? (_indexForViewportY(localPosition.dy) ?? index)
        : index;
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
    if (!widget.rowSelectionMode || !_isDraggingRowSelection) return;
    if (_dragSelectionPointer != event.pointer) return;
    if ((event.buttons & kPrimaryButton) == 0) {
      _endRowSelectionDrag(event.pointer);
      return;
    }
    final localPosition = _globalToViewportLocal(event.position);
    if (localPosition == null) return;
    _applyDragSelectionForLocalPosition(localPosition);
  }

  Future<void> _showRowCopyMenu(int index, Offset position) async {
    final result = await showMenu<LogViewerCopyAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem<LogViewerCopyAction>(
          value: LogViewerCopyAction.copyMessage,
          child: Text('Copy message'),
        ),
        PopupMenuItem<LogViewerCopyAction>(
          value: LogViewerCopyAction.copyTimestampAndMessage,
          child: Text('Copy time + message'),
        ),
      ],
    );

    if (result != null) {
      await widget.onRowCopyAction?.call(index, result);
    }
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
    final viewportRenderBox =
        _rowViewportKey.currentContext?.findRenderObject() as RenderBox?;
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
    final viewportRenderBox =
        _rowViewportKey.currentContext?.findRenderObject() as RenderBox?;
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
                    child: Scrollbar(
                      controller: widget.scrollController,
                      child: GestureDetector(
                        onTap: widget.onLogRowTap,
                        // Support pinch-to-zoom on trackpads / touchpads to change log font size.
                        onScaleStart: (details) {
                          // Record the base font size at gesture start.
                          _scaleBaseFontSize = PreferencesService.logFontSize;
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
                          onPointerUp: (event) =>
                              _endRowSelectionDrag(event.pointer),
                          onPointerCancel: (event) =>
                              _endRowSelectionDrag(event.pointer),
                          child: widget.rowSelectionMode
                              ? _buildLogViewport(messageWidth)
                              : SelectionArea(
                                  contextMenuBuilder: (_, __) =>
                                      const SizedBox.shrink(),
                                  child: _buildLogViewport(messageWidth),
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
            if (widget.rowSelectionMode) ...[
              SizedBox(
                width: _selectionColumnWidth,
                child: Center(
                  child: Icon(
                    Icons.checklist_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: _columnSpacing),
            ],
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
    return _LogRow(
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
      currentMatchLogIndex: widget.currentMatchLogIndex,
      wrapText: widget.wrapText,
      monoStyle: _monoStyle,
      onSelectionPointerDown: (event) => _startRowSelectionDrag(index, event),
      onSelectionPointerMove: (event) => _extendRowSelectionDrag(index, event),
      onSecondaryTap: (position) => _showRowCopyMenu(index, position),
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
        if (widget.rowSelectionMode && selectionRect != null)
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
          child: _buildLogRow(log, i, messageWidth),
        );
      },
    );
  }
}

class _LogRow extends StatelessWidget {
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
  final int? currentMatchLogIndex;
  final bool wrapText;
  final TextStyle monoStyle;
  final ValueChanged<PointerDownEvent>? onSelectionPointerDown;
  final ValueChanged<PointerMoveEvent>? onSelectionPointerMove;
  final ValueChanged<Offset>? onSecondaryTap;
  final String Function(LogColumn) contentValueForColumn;

  const _LogRow({
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
    required this.currentMatchLogIndex,
    required this.wrapText,
    required this.monoStyle,
    this.onSelectionPointerDown,
    this.onSelectionPointerMove,
    this.onSecondaryTap,
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
    final query = searchQuery;
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

    final searchIn = caseSensitive ? text : text.toLowerCase();
    final queryNorm = caseSensitive ? query : query.toLowerCase();

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
      width: _LogViewerState._selectionColumnWidth,
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

    return MouseRegion(
      cursor: rowSelectionMode ? SystemMouseCursors.click : MouseCursor.defer,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: rowSelectionMode ? onSelectionPointerDown : null,
        onPointerMove: rowSelectionMode ? onSelectionPointerMove : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapUp: (details) =>
              onSecondaryTap?.call(details.globalPosition),
          child: Container(
            key: isCurrentMatch ? key : null,
            color: isCurrentMatch
                ? logTheme.searchCurrentRowColor
                : (isSelected ? selectedRowColor : null),
            child: Row(
              children: [
                if (rowSelectionMode) ...[
                  _selectionCell(context),
                  const SizedBox(width: _LogViewerState._columnSpacing),
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
                  const SizedBox(width: _LogViewerState._columnSpacing),
                ],
                if (isVisible(LogColumn.message))
                  SizedBox(
                    width: messageWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: _buildSelectableText(
                        context,
                        log.message,
                        rowStyle,
                        highlightColor: highlightColor,
                        softWrap: wrapText,
                        appendRowTerminator:
                            lastVisibleColumn == LogColumn.message,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RowBoundsReporter extends StatefulWidget {
  const _RowBoundsReporter({
    required this.index,
    required this.onMounted,
    required this.onUnmounted,
    required this.child,
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
