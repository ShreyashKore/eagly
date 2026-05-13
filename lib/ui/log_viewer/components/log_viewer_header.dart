import 'package:flutter/material.dart';

import '../../../data/log_column.dart';
import '../log_viewer_constants.dart';

class LogViewerHeader extends StatelessWidget {
  const LogViewerHeader({
    super.key,
    required this.rowSelectionMode,
    required this.headerStyle,
    required this.visibleFixedColumns,
    required this.messageVisible,
    required this.messageWidth,
    required this.wrapText,
    required this.widthOf,
    required this.onFixedColumnResize,
    required this.onMessageResize,
    required this.onShowColumnVisibilityMenu,
  });

  final bool rowSelectionMode;
  final TextStyle headerStyle;
  final List<LogColumn> visibleFixedColumns;
  final bool messageVisible;
  final double messageWidth;
  final bool wrapText;
  final double Function(LogColumn) widthOf;
  final void Function(LogColumn column, double dx) onFixedColumnResize;
  final ValueChanged<double> onMessageResize;
  final ValueChanged<Offset> onShowColumnVisibilityMenu;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          onShowColumnVisibilityMenu(details.globalPosition),
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        height: 28,
        child: Row(
          children: [
            if (rowSelectionMode) ...[
              SizedBox(
                width: kSelectionColumnWidth,
                child: Center(
                  child: Icon(
                    Icons.checklist_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: kColumnSpacing),
            ],
            for (final column in visibleFixedColumns) ...[
              _HeaderCell(
                text: column.label,
                width: widthOf(column),
                style: headerStyle,
              ),
              _ColumnDragHandle(
                onDrag: (dx) => onFixedColumnResize(column, dx),
              ),
            ],
            if (messageVisible)
              Row(
                children: [
                  SizedBox(
                    width: messageWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(LogColumn.message.label, style: headerStyle),
                    ),
                  ),
                  if (!wrapText)
                    _ColumnDragHandle(onDrag: onMessageResize),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.text,
    required this.width,
    required this.style,
  });

  final String text;
  final double width;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
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
}

class _ColumnDragHandle extends StatelessWidget {
  const _ColumnDragHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: kColumnDragHandleWidth,
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
}

