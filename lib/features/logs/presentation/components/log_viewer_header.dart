import 'package:flutter/foundation.dart';
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

  /// The date of the rows on screen, for the timestamp column's title: the
  /// rows show only the time of day. Null keeps the plain title.
  final ValueListenable<String?>? timestampDate,
}) extends StatelessWidget {
  /// `Time · Oct 18` once a date is known; the column's name otherwise.
  static String timestampTitle(String? date) =>
      date == null ? LogColumn.timestamp.label : 'Time · $date';

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
              if (column == LogColumn.timestamp && timestampDate != null)
                ValueListenableBuilder(
                  valueListenable: timestampDate!,
                  builder: (context, date, _) => _HeaderCell(
                    text: timestampTitle(date),
                    width: widthOf(column),
                    style: headerStyle,
                  ),
                )
              else
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
