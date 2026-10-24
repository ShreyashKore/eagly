import 'package:flutter/material.dart';

import '../../../presentation/theme/app_theme.dart';
import '../data/layout_snapshot.dart';
import '../layout_inspector_controller.dart';

/// The captured screen with the nodes drawn over it. Hovering outlines the
/// node under the pointer; clicking selects it in the tree.
///
/// The screenshot was taken with the tree, so the boxes line up with it
/// even after the device has moved on.
class const LayoutScreenCanvas({
  super.key,
  required final LayoutInspectorController controller,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final theme = Theme.of(context);
    if (snapshot == null) return const SizedBox.shrink();
    final display = snapshot.displaySize;
    if (display.isEmpty) {
      return Center(
        child: Text(
          'No screen size in this capture.',
          style: TextStyle(color: context.eaglyTheme.secondaryTextColor),
        ),
      );
    }

    return Container(
      color: theme.colorScheme.surfaceContainer,
      padding: const EdgeInsets.all(12),
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: display.width / display.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = constraints.maxWidth / display.width;
            Offset toDevice(Offset local) => local / scale;
            return MouseRegion(
              cursor: SystemMouseCursors.precise,
              onHover: (event) => controller.hover(
                controller.nodeAt(toDevice(event.localPosition)),
              ),
              onExit: (_) => controller.hover(null),
              child: GestureDetector(
                onTapUp: (details) => controller.select(
                  controller.nodeAt(toDevice(details.localPosition)),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (snapshot.screenshot case final screenshot?)
                        Image.memory(
                          screenshot,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        )
                      else
                        ColoredBox(color: theme.colorScheme.surface),
                      CustomPaint(
                        painter: _BoundsPainter(
                          snapshot: snapshot,
                          scale: scale,
                          selected: controller.selected,
                          hovered: controller.hovered,
                          showAll: controller.showAllBounds,
                          selectedColor: theme.colorScheme.primary,
                          hoveredColor: theme.colorScheme.tertiary,
                          allColor: theme.colorScheme.secondary,
                          labelStyle: theme.textTheme.labelSmall!,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BoundsPainter({
  required final LayoutSnapshot snapshot,
  required final double scale,
  required final LayoutNode? selected,
  required final LayoutNode? hovered,
  required final bool showAll,
  required final Color selectedColor,
  required final Color hoveredColor,
  required final Color allColor,
  required final TextStyle labelStyle,
}) extends CustomPainter {
  Rect _scaled(Rect rect) => Rect.fromLTRB(
    rect.left * scale,
    rect.top * scale,
    rect.right * scale,
    rect.bottom * scale,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (showAll) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = allColor.withValues(alpha: 0.55);
      for (final node in snapshot.nodes) {
        if (!node.isVisible || node.bounds.isEmpty) continue;
        canvas.drawRect(_scaled(node.bounds).deflate(0.5), paint);
      }
    }
    final hover = hovered;
    if (hover != null && hover != selected) {
      _highlight(canvas, size, hover, hoveredColor, fill: 0.12);
    }
    final selection = selected;
    if (selection != null) {
      _highlight(canvas, size, selection, selectedColor, fill: 0.2);
    }
  }

  void _highlight(
    Canvas canvas,
    Size size,
    LayoutNode node,
    Color color, {
    required double fill,
  }) {
    final rect = _scaled(node.bounds);
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: fill));
    canvas.drawRect(
      rect.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
    _label(canvas, size, rect, node, color);
  }

  /// A tag with the node's class and size, above the box, or below it when
  /// there is no room above, kept inside the canvas.
  void _label(
    Canvas canvas,
    Size size,
    Rect rect,
    LayoutNode node,
    Color color,
  ) {
    final bounds = node.bounds;
    final text = TextPainter(
      text: TextSpan(
        text:
            '${node.view?.shortClassName ?? node.shortClassName}  '
            '${bounds.width.round()}×${bounds.height.round()}',
        style: labelStyle.copyWith(
          color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: (size.width - 8).clamp(0.0, double.infinity));
    final tag = Size(text.width + 8, text.height + 4);
    var top = rect.top - tag.height;
    if (top < 0) top = rect.bottom;
    if (top + tag.height > size.height) top = rect.top;
    final left = rect.left.clamp(
      0.0,
      (size.width - tag.width).clamp(0.0, double.infinity),
    );
    final tagRect = Offset(left, top) & tag;
    canvas.drawRRect(
      RRect.fromRectAndRadius(tagRect, const Radius.circular(3)),
      Paint()..color = color,
    );
    text.paint(canvas, tagRect.topLeft + const Offset(4, 2));
  }

  @override
  bool shouldRepaint(_BoundsPainter old) =>
      old.snapshot != snapshot ||
      old.scale != scale ||
      old.selected != selected ||
      old.hovered != hovered ||
      old.showAll != showAll ||
      old.selectedColor != selectedColor;
}
