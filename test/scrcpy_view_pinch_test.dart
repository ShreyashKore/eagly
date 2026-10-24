import 'package:eagly/features/flutter_scrcpy/flutter_scrcpy.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final touches = <(ScrcpyTouchAction, double, double)>[];
  final frames = <List<(int, double, double, bool)>>[];
  final fingers = find.byKey(const ValueKey('scrcpy-pinch-fingers'));

  /// A 200×400 picture. [pinches] false is the Android mirror, which passes
  /// no `onMultiTouch`.
  Future<Offset> pumpView(WidgetTester tester, {bool pinches = true}) async {
    touches.clear();
    frames.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 400,
            child: ScrcpyView(
              aspectRatio: 0.5,
              onTouch: (action, x, y) => touches.add((action, x, y)),
              onMultiTouch: pinches
                  ? (contacts) => frames.add([
                      for (final c in contacts) (c.id, c.nx, c.ny, c.touching),
                    ])
                  : null,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );
    return tester.getTopLeft(find.byType(ScrcpyView));
  }

  Matcher finger(int id, double x, double y, bool touching) => isA<Object>()
      .having((f) => (f as (int, double, double, bool)).$1, 'id', id)
      .having(
        (f) => (f as (int, double, double, bool)).$2,
        'x',
        closeTo(x, 1e-9),
      )
      .having(
        (f) => (f as (int, double, double, bool)).$3,
        'y',
        closeTo(y, 1e-9),
      )
      .having(
        (f) => (f as (int, double, double, bool)).$4,
        'touching',
        touching,
      );

  tearDown(() async {
    // The keyboard state outlives a test; let go of Option.
    if (HardwareKeyboard.instance.isAltPressed) {
      await simulateKeyUpEvent(LogicalKeyboardKey.altLeft);
    }
  });

  testWidgets('an Option-drag is two fingers mirrored through the centre', (
    tester,
  ) async {
    final origin = await pumpView(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);

    final drag = await tester.startGesture(
      origin + const Offset(50, 100),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveTo(origin + const Offset(100, 100));
    await drag.up();

    expect(frames, [
      [(0, 0.25, 0.25, true), (1, 0.75, 0.75, true)],
      [(0, 0.5, 0.25, true), (1, 0.5, 0.75, true)],
      [(0, 0.5, 0.25, false), (1, 0.5, 0.75, false)],
    ]);
    expect(touches, isEmpty);
  });

  testWidgets('both fingers show while Option is held over the picture', (
    tester,
  ) async {
    final origin = await pumpView(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: origin + const Offset(50, 100));
    await mouse.moveTo(origin + const Offset(60, 100));
    await tester.pump();
    expect(fingers, findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(fingers, findsOneWidget);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(fingers, findsNothing);
    await mouse.removePointer();
  });

  testWidgets('without Option a drag is one finger', (tester) async {
    final origin = await pumpView(tester);

    final drag = await tester.startGesture(
      origin + const Offset(50, 100),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveTo(origin + const Offset(100, 100));
    await drag.up();

    expect(touches, [
      (ScrcpyTouchAction.down, 0.25, 0.25),
      (ScrcpyTouchAction.move, 0.5, 0.25),
      (ScrcpyTouchAction.up, 0.5, 0.25),
    ]);
    expect(frames, isEmpty);
  });

  testWidgets('a view without onMultiTouch keeps an Option-drag one finger', (
    tester,
  ) async {
    final origin = await pumpView(tester, pinches: false);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);

    final drag = await tester.startGesture(
      origin + const Offset(50, 100),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(fingers, findsNothing);
    await drag.up();

    expect(touches.map((t) => t.$1), [
      ScrcpyTouchAction.down,
      ScrcpyTouchAction.up,
    ]);
  });

  testWidgets('a trackpad pinch spreads two fingers around the pointer', (
    tester,
  ) async {
    final origin = await pumpView(tester);
    final centre = origin + const Offset(100, 200);
    final trackpad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );

    // Fingers start 0.3 of the shorter side apart, so 30 px either side.
    await trackpad.panZoomStart(centre);
    await trackpad.panZoomUpdate(centre, scale: 1.5);
    await trackpad.panZoomUpdate(centre, scale: 3);
    await trackpad.panZoomEnd();

    expect(frames, [
      [finger(0, 0.35, 0.5, true), finger(1, 0.65, 0.5, true)],
      [finger(0, 0.2, 0.5, true), finger(1, 0.8, 0.5, true)],
      [finger(0, 0.2, 0.5, false), finger(1, 0.8, 0.5, false)],
    ]);
    expect(touches, isEmpty);
  });

  testWidgets('a trackpad rotation turns the fingers around their centre', (
    tester,
  ) async {
    final origin = await pumpView(tester);
    final centre = origin + const Offset(100, 200);
    final trackpad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );

    await trackpad.panZoomStart(centre);
    await trackpad.panZoomUpdate(centre, rotation: 0.1);
    await trackpad.panZoomUpdate(centre, rotation: 0.1 + 3.141592653589793 / 2);
    await trackpad.panZoomEnd();

    expect(frames[1], [
      finger(0, 0.5, 0.5 - 30 / 400, true),
      finger(1, 0.5, 0.5 + 30 / 400, true),
    ]);
  });

  testWidgets('a two-finger scroll is not a pinch', (tester) async {
    final origin = await pumpView(tester);
    final centre = origin + const Offset(100, 200);
    final trackpad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );

    await trackpad.panZoomStart(centre);
    await trackpad.panZoomUpdate(centre, pan: const Offset(0, 40));
    await trackpad.panZoomEnd();

    expect(frames, isEmpty);
    expect(touches, isEmpty);
  });
}
