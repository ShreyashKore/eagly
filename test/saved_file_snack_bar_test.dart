import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:eagly/presentation/components/saved_file_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [width]×[height] PNG, standing in for a device screenshot.
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.teal, BlendMode.src);
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  final originKey = GlobalKey();

  Future<ScaffoldMessengerState> pumpHost(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // Not AppTheme: its Google Fonts fail to load inside runAsync, which
        // decoding the screenshot needs.
        theme: ThemeData(
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(key: originKey, width: 200, height: 400),
          ),
        ),
      ),
    );
    return tester.state(find.byType(ScaffoldMessenger));
  }

  /// Pumps ~60 fps frames for [duration]: the flight's move starts on the
  /// frame after its flash ends, which one long pump would skip past.
  Future<void> pumpFrames(WidgetTester tester, Duration duration) async {
    const frame = Duration(milliseconds: 16);
    for (var elapsed = Duration.zero; elapsed < duration; elapsed += frame) {
      await tester.pump(frame);
    }
  }

  /// The thumbnail's opacity: 0 while the picture is still flying into it.
  double thumbnailOpacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find.descendant(
          of: find.byTooltip('Open'),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;

  testWidgets('the screenshot flies from its origin into the thumbnail', (
    tester,
  ) async {
    final png = (await tester.runAsync(() => _png(100, 200)))!;
    final messenger = await pumpHost(tester);

    await tester.runAsync(
      () => showSavedFileSnackBar(
        messenger,
        message: 'Screenshot saved to Eagly/shot.png',
        path: '/tmp/Eagly/shot.png',
        preview: png,
        previewOrigin: originKey.currentContext,
      ),
    );
    await tester.pump();

    expect(find.text('Screenshot saved to Eagly/shot.png'), findsOneWidget);
    // The thumbnail and the picture in flight.
    expect(find.byType(Image), findsNWidgets(2));
    expect(thumbnailOpacity(tester), 0);

    // The flight starts over the origin, the picture fitted inside it.
    final flying = tester.getRect(find.byType(Image).last);
    expect(flying.center, tester.getCenter(find.byKey(originKey)));
    expect(flying.size, const Size(200, 400));

    // Past the flash, halfway through the move.
    await pumpFrames(tester, const Duration(milliseconds: 460));
    final thumbnail = tester.getRect(
      find.descendant(of: find.byTooltip('Open'), matching: find.byType(Image)),
    );
    final midFlight = tester.getRect(find.byType(Image).last);
    expect(midFlight.height, lessThan(300));
    expect(midFlight.height, greaterThan(thumbnail.height));

    await pumpFrames(tester, const Duration(milliseconds: 400));
    expect(find.byType(Image), findsOneWidget);
    expect(thumbnailOpacity(tester), 1);
    // A 1:2 picture fills the thumbnail's height.
    expect(thumbnail.size, const Size(36, 72));
  });

  testWidgets('with reduced motion the thumbnail just appears', (tester) async {
    final png = (await tester.runAsync(() => _png(100, 200)))!;
    final messenger = await pumpHost(tester, disableAnimations: true);

    await tester.runAsync(
      () => showSavedFileSnackBar(
        messenger,
        message: 'Screenshot saved',
        path: '/tmp/shot.png',
        preview: png,
        previewOrigin: originKey.currentContext,
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(thumbnailOpacity(tester), 1);
  });

  testWidgets("a video's still carries a play mark", (tester) async {
    final png = (await tester.runAsync(() => _png(200, 100)))!;
    final messenger = await pumpHost(tester);

    await tester.runAsync(
      () => showSavedFileSnackBar(
        messenger,
        message: 'Recording saved',
        path: '/tmp/clip.mp4',
        preview: png,
        previewIsVideo: true,
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byTooltip('Open'),
        matching: find.byIcon(Icons.play_arrow_rounded),
      ),
      findsOneWidget,
    );
    // A 2:1 still fills the thumbnail's width.
    expect(
      tester.getSize(
        find.descendant(
          of: find.byTooltip('Open'),
          matching: find.byType(Image),
        ),
      ),
      const Size(112, 56),
    );
  });

  testWidgets('without a preview there is no thumbnail', (tester) async {
    final messenger = await pumpHost(tester);

    await showSavedFileSnackBar(
      messenger,
      message: 'Recording saved',
      path: '/tmp/clip.mp4',
    );
    await tester.pump();

    expect(find.text('Recording saved'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byTooltip('Open'), findsNothing);
  });
}
