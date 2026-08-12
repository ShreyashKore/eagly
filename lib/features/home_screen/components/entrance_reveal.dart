import 'package:flutter/material.dart';

/// Snappy "pop in" reveal: the tab expands horizontally from its leading edge
/// while fading and scaling up, so a newly connected device slides into place.
class EntranceReveal extends StatelessWidget {
  const EntranceReveal({
    super.key,
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return SizeTransition(
      axis: Axis.horizontal,
      axisAlignment: -1,
      sizeFactor: eased,
      child: FadeTransition(
        opacity: eased,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      ),
    );
  }
}
