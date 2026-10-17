import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Lays [child] out at least [minWidth] wide, clipping its right edge when the
/// space is narrower — a workspace pane can be dragged far narrower than a
/// row of fixed-size controls fits, and squeezing them throws layout overflow
/// errors. At [minWidth] and wider, [child] gets the space unchanged.
class const MinWidthBox({
  super.key,
  required final double minWidth,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math.max(minWidth, constraints.maxWidth);
        // The same tree on both sides of [minWidth]: swapping widget types at
        // the threshold would rebuild [child] from scratch every time the
        // width crossed it — losing a text field's keyboard connection
        // mid-animation, or a list's scroll position mid-drag.
        //
        // A scroll view clips and, unlike a squeezed Flex, never reports the
        // content past its edge as an overflow. Programmatic scrolls (a
        // focused field revealing its caret) still work; the user can't drag.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: math.min(
                math.max(constraints.minWidth, minWidth),
                maxWidth,
              ),
              maxWidth: maxWidth,
            ),
            child: child,
          ),
        );
      },
    );
  }
}
