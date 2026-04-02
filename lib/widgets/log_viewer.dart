import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/log_column.dart';
import '../data/log_entry.dart';
import '../services/preferences_service.dart';
import '../utils/log_utils.dart';

class LogViewer extends StatefulWidget {
  final List<LogEntry> logs;
  final ScrollController scrollController;
  final bool wrapText;
  final VoidCallback? onLogRowTap;

  const LogViewer({
    super.key,
    required this.logs,
    required this.scrollController,
    required this.wrapText,
    this.onLogRowTap,
  });

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  late Map<String, double> _widths;
  late Set<String> _hiddenColumns;
  Timer? _saveWidthsTimer;

  late TextStyle _monoStyle;

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
  void dispose() {
    _flushWidths();
    _saveWidthsTimer?.cancel();
    super.dispose();
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
          padding: EdgeInsets.zero,
          value: col,
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              final visible = _isVisible(col);
              return CheckboxListTile.adaptive(
                dense: true,
                value: visible,
                title: Text(col.label, style: const TextStyle(fontSize: 13)),
                visualDensity: VisualDensity.compact,
                onChanged: (_) {
                  setState(() {
                    if (visible) {
                      _hiddenColumns.add(col.name);
                    } else {
                      _hiddenColumns.remove(col.name);
                    }
                    PreferencesService.hiddenColumns = _hiddenColumns;
                  });
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
                child: ListView.builder(
                  controller: widget.scrollController,
                  itemCount: widget.logs.length,
                  itemBuilder: (_, i) => _buildLogRow(widget.logs[i]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final headerStyle = _monoStyle.copyWith(fontWeight: FontWeight.bold);
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

  Widget _buildLogRow(LogEntry log) {
    final levelColor = LogUtils.colorForLevel(log.level);
    final rowStyle = _monoStyle.copyWith(color: levelColor);
    final visible = _visibleFixedColumns;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final col in visible) ...[
            if (col == LogColumn.level)
              _levelCell(log.level, levelColor)
            else
              _fixedCell(_cellValue(col, log), _widthOf(col), rowStyle),
            const SizedBox(width: 8),
          ],
          if (_isVisible(LogColumn.message))
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  log.message,
                  style: rowStyle,
                  softWrap: widget.wrapText,
                  overflow: widget.wrapText ? null : TextOverflow.ellipsis,
                  maxLines: widget.wrapText ? null : 1,
                ),
              ),
            ),
        ],
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

  Widget _fixedCell(String text, double width, TextStyle style) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          text,
          style: style,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}
