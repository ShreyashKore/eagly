import 'package:flutter/material.dart';

/// Wraps the log content in the horizontal scroller and the explicit
/// vertical/horizontal scrollbars. The horizontal scrollbar is only shown
/// when the content can actually overflow (i.e. `wrapText == false`).
class LogViewerScrollArea extends StatelessWidget {
  const LogViewerScrollArea({
    super.key,
    required this.verticalController,
    required this.horizontalController,
    required this.wrapText,
    required this.child,
  });

  final ScrollController verticalController;
  final ScrollController horizontalController;
  final bool wrapText;

  /// The log content, already sized to the full content width.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Wrap SingleChildScrollView in a ScrollConfiguration that disables
    // ALL ambient scrollbars. This prevents Flutter's ScrollBehavior from
    // auto-painting a second ghost thumb on desktop/web — our explicit
    // Scrollbar widgets above are the only ones that should render.
    final scrollableContent = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        controller: horizontalController,
        scrollDirection: Axis.horizontal,
        child: child,
      ),
    );

    // Vertical scrollbar — pinned to screen right, vertical axis only.
    return Scrollbar(
      controller: verticalController,
      thumbVisibility: true,
      notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
      // Horizontal scrollbar — pinned to screen bottom, shown only when
      // content actually overflows (i.e. wrapText == false).
      child: wrapText
          ? scrollableContent
          : Scrollbar(
              controller: horizontalController,
              thumbVisibility: true,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: scrollableContent,
            ),
    );
  }
}
