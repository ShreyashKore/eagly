import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/log_entry.dart';
import '../utils/log_utils.dart';

class LogViewer extends StatefulWidget {
  final List<LogEntry> logs;
  final ScrollController scrollController;
  final bool wrapText;

  const LogViewer({
    super.key,
    required this.logs,
    required this.scrollController,
    required this.wrapText,
  });

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  // Column widths — initial values based on typical content width
  double _timestampWidth = 170.0;
  double _pidWidth = 130.0;
  double _tidWidth = 60.0;
  double _levelWidth = 35.0;
  double _tagWidth = 150.0;
  // Message column takes remaining space

  // Minimum column widths
  static const double _minColumnWidth = 30.0;

  // Maximum column widths for non-message columns
  static const double _maxTimestampWidth = 250.0;
  static const double _maxPidWidth = 200.0;
  static const double _maxTidWidth = 100.0;
  static const double _maxLevelWidth = 60.0;
  static const double _maxTagWidth = 300.0;

  late TextStyle _monoStyle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _monoStyle = GoogleFonts.notoSansMono(fontSize: 12, height: 1.2);
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
              child: ListView.builder(
                controller: widget.scrollController,
                itemCount: widget.logs.length,
                itemBuilder: (_, i) => _buildLogRow(widget.logs[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final headerStyle = _monoStyle.copyWith(fontWeight: FontWeight.bold);
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      height: 28,
      child: Row(
        children: [
          _headerCell('Timestamp', _timestampWidth, headerStyle),
          _columnDragHandle((dx) => setState(() {
                _timestampWidth = (_timestampWidth + dx)
                    .clamp(_minColumnWidth, _maxTimestampWidth);
              })),
          _headerCell('PID/Package', _pidWidth, headerStyle),
          _columnDragHandle((dx) => setState(() {
                _pidWidth =
                    (_pidWidth + dx).clamp(_minColumnWidth, _maxPidWidth);
              })),
          _headerCell('TID', _tidWidth, headerStyle),
          _columnDragHandle((dx) => setState(() {
                _tidWidth =
                    (_tidWidth + dx).clamp(_minColumnWidth, _maxTidWidth);
              })),
          _headerCell('Level', _levelWidth, headerStyle),
          _columnDragHandle((dx) => setState(() {
                _levelWidth =
                    (_levelWidth + dx).clamp(_minColumnWidth, _maxLevelWidth);
              })),
          _headerCell('Tag', _tagWidth, headerStyle),
          _columnDragHandle((dx) => setState(() {
                _tagWidth =
                    (_tagWidth + dx).clamp(_minColumnWidth, _maxTagWidth);
              })),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('Message', style: headerStyle),
            ),
          ),
        ],
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
    final displayId = log.packageName ?? log.pid;
    final levelColor = LogUtils.colorForLevel(log.level);
    final rowStyle = _monoStyle.copyWith(color: levelColor);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fixedCell(log.timestamp, _timestampWidth, rowStyle),
          const SizedBox(width: 8),
          _fixedCell(displayId, _pidWidth, rowStyle),
          const SizedBox(width: 8),
          _fixedCell(log.tid, _tidWidth, rowStyle),
          const SizedBox(width: 8),
          SizedBox(
            width: _levelWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Container(
                decoration: BoxDecoration(
                  color: levelColor,
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.center,
                child: Text(
                  log.level,
                  style: _monoStyle.copyWith(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _fixedCell(log.tag, _tagWidth, rowStyle),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
