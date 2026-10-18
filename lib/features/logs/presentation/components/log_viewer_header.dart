import 'package:flutter/material.dart';

import '../../../../presentation/theme/app_theme.dart';
import '../../data/models/log_column.dart';
import '../log_viewer_constants.dart';

class const LogViewerHeader({
  super.key,
  required final bool rowSelectionMode,
  required final TextStyle headerStyle,
  required final List<LogColumn> visibleFixedColumns,
  required final bool messageVisible,
  required final double messageWidth,
  required final bool wrapText,
  required final double Function(LogColumn) widthOf,
  required final void Function(LogColumn column, double dx) onFixedColumnResize,
  required final ValueChanged<double> onMessageResize,
  required final ValueChanged<Offset> onShowColumnVisibilityMenu,
  final bool isIos = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          onShowColumnVisibilityMenu(details.globalPosition),
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        height: context.scaled(28),
        child: Row(
          children: [
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
            for (final column in visibleFixedColumns) ...[
              _HeaderCell(
                text: column.labelFor(isIos: isIos),
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
                  if (!wrapText) _ColumnDragHandle(onDrag: onMessageResize),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class const _HeaderCell({
  required final String text,
  required final double width,
  required final TextStyle style,
}) extends StatelessWidget {
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

class const _ColumnDragHandle({required final ValueChanged<double> onDrag})
    extends StatelessWidget {
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
