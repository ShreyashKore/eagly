import 'package:flutter/material.dart';

import '../log_viewer_constants.dart';

/// Draggable divider between header cells that resizes the column to its
/// left via [onDrag] deltas.
class ColumnDragHandle extends StatelessWidget {
  const ColumnDragHandle({super.key, required this.onDrag});

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
