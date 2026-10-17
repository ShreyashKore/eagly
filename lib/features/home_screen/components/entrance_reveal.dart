import 'package:flutter/material.dart';

/// Snappy "pop in" reveal: the tab expands horizontally from its leading edge
/// while fading and scaling up, so a newly connected device slides into place.
class const EntranceReveal({
  super.key,
  required final Animation<double> animation,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return SizeTransition(
      axis: Axis.horizontal,
      alignment: Alignment.centerLeft,
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
