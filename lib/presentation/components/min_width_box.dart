import 'package:flutter/widgets.dart';

/// Lays [child] out at least [minWidth] wide, clipping its right edge when the
/// space is narrower — a workspace pane can be dragged far narrower than a
/// row of fixed-size controls fits, and squeezing them throws layout overflow
/// errors. At [minWidth] and wider, [child] gets the space unchanged.
class MinWidthBox extends StatelessWidget {
  const MinWidthBox({super.key, required this.minWidth, required this.child});

  final double minWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= minWidth) return child;
        // A scroll view clips and, unlike a squeezed Flex, never reports the
        // content past its edge as an overflow. Programmatic scrolls (a
        // focused field revealing its caret) still work; the user can't drag.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(width: minWidth, child: child),
        );
      },
    );
  }
}
