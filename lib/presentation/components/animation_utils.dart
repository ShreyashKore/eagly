import 'package:flutter/material.dart';

/// Collapses/expands a section along [axis] by sliding the child out while
/// the container shrinks. The child is never scaled — it clips at the edge.
class AnimatedSection extends StatelessWidget {
  const AnimatedSection({
    required this.visible,
    required this.child,
    this.axis = Axis.horizontal,
    this.fade = false,
    super.key,
  });

  final bool visible;
  final Widget child;
  final Axis axis;
  final bool fade;

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

class AnimatedContent extends StatelessWidget {
  const AnimatedContent({
    this.duration = const Duration(milliseconds: 250),
    required this.child,
    super.key,
  });

  final Duration duration;
  final Widget child;

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