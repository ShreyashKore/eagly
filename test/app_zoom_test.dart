import 'package:eagly/presentation/theme/app_zoom.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A long, scrolled-to-the-bottom, selectable list — the log viewer in
/// miniature. Zoom must not move it while the user drags a selection over it.
///
/// A `Transform.scale`-based zoom fails this: `Scrollable`'s selection
/// delegate adds the (unscaled) scroll offset to a position it maps through
/// the layer transform, so the drag target lands `offset * (zoom - 1)` pixels
/// away and the edge auto-scroller drives the viewport off under the pointer.
Future<(List<double>, String?)> dragSelectionAtBottom(
  WidgetTester tester,
  double zoomLevel,
) async {
  final scrollController = ScrollController();
  addTearDown(scrollController.dispose);
  String? selected;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppZoom(
          zoomLevel: zoomLevel,
          child: SelectionArea(
            onSelectionChanged: (content) => selected = content?.plainText,
            child: ListView.builder(
              controller: scrollController,
              itemCount: 3000,
              itemExtent: 24,
              itemBuilder: (context, index) => Text('Log line $index'),
            ),
          ),
        ),
      ),
    ),
  );

  // Where new logs land, 500 px of headroom left to scroll into.
  scrollController.jumpTo(scrollController.position.maxScrollExtent - 500);
  await tester.pump();

  final offsets = <double>[scrollController.offset];
  final gesture = await tester.startGesture(
    const Offset(120, 300),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 16));

  // Drag well inside the viewport — nowhere near an edge, so nothing should
  // auto-scroll.
  for (var i = 0; i < 6; i++) {
    await gesture.moveBy(const Offset(10, -20));
    await tester.pump(const Duration(milliseconds: 16));
    offsets.add(scrollController.offset);
  }
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    offsets.add(scrollController.offset);
  }

  await gesture.up();
  await tester.pumpAndSettle();
  return (offsets, selected);
}

void main() {
  testWidgets('zoom scales text without changing the coordinate space', (
    tester,
  ) async {
    late TextScaler textScaler;
    await tester.pumpWidget(
      MaterialApp(
        home: AppZoom(
          zoomLevel: 1.3,
          child: Builder(
            builder: (context) {
              textScaler = MediaQuery.textScalerOf(context);
              return const Text('Log line');
            },
          ),
        ),
      ),
    );

    expect(textScaler.scale(10), closeTo(13, 0.001));
    // No layer transform: the app stays in one coordinate space.
    expect(find.byType(Transform), findsNothing);
  });

  for (final zoomLevel in <double>[0.8, 1.0, 1.3]) {
    testWidgets('selection drag at the bottom does not scroll at $zoomLevel', (
      tester,
    ) async {
      final (offsets, selected) = await dragSelectionAtBottom(
        tester,
        zoomLevel,
      );

      expect(
        offsets,
        everyElement(offsets.first),
        reason: 'the viewport moved on its own during a selection drag',
      );
      expect(selected, isNotNull, reason: 'the drag selected nothing');
      expect(selected, isNotEmpty);
    });
  }
}
