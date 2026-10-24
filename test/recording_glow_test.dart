import 'package:eagly/features/flutter_scrcpy/flutter_scrcpy.dart';
import 'package:eagly/features/mirror/components/recording_glow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const limit = Duration(minutes: 3);

  Future<void> pumpGlow(
    WidgetTester tester,
    Duration elapsed, {
    Duration? timeLimit = limit,
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Center(
          child: SizedBox(
            width: 180,
            height: 390,
            child: RecordingGlow(
              startedAt: DateTime.now().subtract(elapsed),
              timeLimit: timeLimit,
            ),
          ),
        ),
      ),
    );
    // Past the fade-in, so only the beat can still be moving.
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the glow keeps beating while recording', (tester) async {
    await pumpGlow(tester, const Duration(seconds: 10));
    expect(tester.hasRunningAnimations, isTrue);

    await pumpGlow(tester, const Duration(minutes: 10), timeLimit: null);
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('it stops once the limit has ended the recording', (
    tester,
  ) async {
    await pumpGlow(tester, const Duration(minutes: 4));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('it stops when the limit runs out on screen', (tester) async {
    await pumpGlow(tester, limit - const Duration(seconds: 2));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('nothing moves when the platform asks for less motion', (
    tester,
  ) async {
    await pumpGlow(
      tester,
      const Duration(seconds: 10),
      disableAnimations: true,
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the mirror lays the overlay over its picture', (tester) async {
    var touches = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ScrcpyView(
          aspectRatio: 9 / 19.5,
          onTouch: (_, _, _) => touches++,
          overlay: RecordingGlow(startedAt: DateTime.now(), timeLimit: null),
          child: const ColoredBox(
            key: Key('picture'),
            color: Color(0xFF000000),
          ),
        ),
      ),
    );

    final picture = tester.getSize(find.byKey(const Key('picture')));
    expect(tester.getSize(find.byType(RecordingGlow)), picture);

    // Touches still reach the device through it.
    await tester.tap(find.byType(ScrcpyView));
    expect(touches, greaterThan(0));
  });
}
