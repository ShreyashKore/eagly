import 'package:flutter/material.dart';

/// Collapses/expands a section along [axis] by sliding the child out while
/// the container shrinks. The child is never scaled — it clips at the edge.
class const AnimatedSection({
  required final bool visible,
  required final Widget child,
  final Axis axis = Axis.horizontal,
  final bool fade = false,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final alignment = axis == Axis.horizontal
        ? Alignment.centerLeft
        : Alignment.topCenter;

    return TweenAnimationBuilder<double>(
      tween: Tween(end: visible ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      builder: (context, factor, child) => ClipRect(
        child: Align(
          alignment: alignment,
          widthFactor: axis == Axis.horizontal ? factor : 1.0,
          heightFactor: axis == Axis.vertical ? factor : 1.0,
          child: fade ? Opacity(opacity: factor, child: child) : child,
        ),
      ),
      child: child,
    );
  }
}

class const AnimatedContent({
  final Duration duration = const Duration(milliseconds: 250),
  required final Widget child,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: duration,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: child,
      ),
    );
  }
}
