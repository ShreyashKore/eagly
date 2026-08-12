import 'package:flutter/material.dart';

/// Thin draggable divider that resizes a side pane horizontally.
class PaneResizeHandle extends StatelessWidget {
  const PaneResizeHandle({
    super.key,
    required this.paneWidth,
    required this.onResize,
  });

  /// Returns the pane's current width.
  final double Function() paneWidth;

  /// Applies a new pane width.
  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) =>
            onResize(paneWidth() + details.delta.dx),
        child: Container(
          width: 8,
          height: double.infinity,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
          child: Center(
            child: Container(
              width: 2,
              height: 24,
              color: theme.colorScheme.outline.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}
