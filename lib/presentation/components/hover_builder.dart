import 'package:flutter/material.dart';

/// Builds [builder] with whether the pointer is over it, rebuilding as it
/// enters and leaves — so a widget whose only state is its hover look can
/// stay stateless.
class const HoverBuilder({
  super.key,
  final MouseCursor cursor = MouseCursor.defer,
  required final Widget Function(BuildContext context, bool hovered) builder,
}) extends StatefulWidget {
  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  void _setHovered(bool hovered) {
    if (hovered != _hovered) setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: widget.builder(context, _hovered),
    );
  }
}
