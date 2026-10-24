import 'dart:async';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/flutter_scrcpy/flutter_scrcpy.dart';
import 'package:eagly/features/mirror/ios/ios_mirror_session.dart';
import 'package:eagly/services/ios/ios_mirror_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSessionService service;

  setUp(() {
    service = FakeSessionService(
      Device.ios('00008140-001871A02EF2801C', 'device', name: 'iPhone 16e'),
    );
    IosMirrorSession.buttonHold = Duration.zero;
  });

  tearDown(() {
    IosMirrorSession.buttonHold = const Duration(milliseconds: 100);
    IosMirrorSession.firstFrameTimeout = const Duration(seconds: 25);
  });

  /// A PNG header with an IHDR chunk for a [width]×[height] image.
  Uint8List png(int width, int height) {
    final bytes = ByteData(24);
    for (final (i, byte) in [137, 80, 78, 71, 13, 10, 26, 10].indexed) {
      bytes.setUint8(i, byte);
    }
    bytes.setUint32(8, 13);
    bytes.setUint32(12, 0x49484452); // IHDR
    bytes.setUint32(16, width);
    bytes.setUint32(20, height);
    return bytes.buffer.asUint8List();
  }

  Future<IosMirrorSession> startLive() {
    final starting = IosMirrorSession.start(
      service,
      liveCapture: true,
      controlIsCommand: false,
    );
    scheduleMicrotask(() => service.iosCapture!.frame(const Size(1170, 2532)));
    return starting;
  }

  group('toPanel', () {
    test('a portrait picture is the panel itself', () {
      expect(toPanel(0.2, 0.7, IosInterfaceOrientation.portrait), (0.2, 0.7));
    });

    test('home indicator right: the picture\'s top-left is the panel\'s '
        'top-right', () {
      expect(toPanel(0, 0, IosInterfaceOrientation.landscapeRight), (1, 0));
      expect(toPanel(1, 1, IosInterfaceOrientation.landscapeRight), (0, 1));
    });

    test('home indicator left: the picture\'s top-left is the panel\'s '
        'bottom-left', () {
      expect(toPanel(0, 0, IosInterfaceOrientation.landscapeLeft), (0, 1));
      expect(toPanel(1, 1, IosInterfaceOrientation.landscapeLeft), (1, 0));
    });

    test('upside down flips both axes', () {
      expect(toPanel(0.25, 0.1, IosInterfaceOrientation.portraitUpsideDown), (
        0.75,
        0.9,
      ));
    });
  });

  test('pngSize reads the IHDR chunk', () {
    expect(pngSize(png(1170, 2532)), const Size(1170, 2532));
    expect(pngSize(Uint8List(8)), isNull);
  });

  group('starting', () {
    test('input connects only after the first frame', () async {
      final starting = IosMirrorSession.start(
        service,
        liveCapture: true,
        controlIsCommand: false,
      );
      await pumpEventQueue();
      expect(service.iosInputs, isEmpty);

      service.iosCapture!.frame(const Size(1170, 2532));
      final mirror = await starting;

      expect(mirror.video, IosMirrorVideo.liveCapture);
      expect(mirror.textureId, 7);
      expect(mirror.size, const Size(1170, 2532));
      expect(mirror.hasInput, isTrue);
      expect(service.iosInputs, hasLength(1));
      await mirror.stop();
    });

    test('falls back to screenshots, saying why', () async {
      service.iosCapture = null;
      final starting = IosMirrorSession.start(
        service,
        liveCapture: true,
        controlIsCommand: false,
      );
      await pumpEventQueue();
      service.iosScreenshotFeed.add(png(1170, 2532));
      final mirror = await starting;

      expect(mirror.video, IosMirrorVideo.screenshots);
      expect(mirror.frame, isNotNull);
      expect(mirror.size, const Size(1170, 2532));
      expect(mirror.videoNotice, contains('Camera access is off.'));
      await mirror.stop();
    });

    test('fails when there is no way to see the screen', () async {
      service.iosCapture = null;
      service.iosMirrorSupport = IosMirrorSupport.none;

      await expectLater(
        IosMirrorSession.start(
          service,
          liveCapture: true,
          controlIsCommand: false,
        ),
        throwsA(isA<IosMirrorException>()),
      );
    });

    test('fails when no frame arrives', () async {
      IosMirrorSession.firstFrameTimeout = Duration.zero;

      await expectLater(
        IosMirrorSession.start(
          service,
          liveCapture: true,
          controlIsCommand: false,
        ),
        throwsA(isA<IosMirrorException>()),
      );
      expect(service.iosCapture!.stopped, isTrue);
    });

    test(
      'fails with the capture\'s reason when it ends before a frame',
      () async {
        final starting = IosMirrorSession.start(
          service,
          liveCapture: true,
          controlIsCommand: false,
        );
        await pumpEventQueue();
        service.iosCapture!.end('The iPhone was disconnected.');

        await expectLater(
          starting,
          throwsA(
            isA<IosMirrorException>().having(
              (e) => e.message,
              'message',
              'The iPhone was disconnected.',
            ),
          ),
        );
        expect(service.iosInputs, isEmpty);
      },
    );

    test('a stop while it waits for the first frame ends the start', () async {
      IosMirrorSession? pending;
      final starting = IosMirrorSession.start(
        service,
        liveCapture: true,
        controlIsCommand: false,
        onCreated: (session) => pending = session,
      );
      await pumpEventQueue();

      final failed = expectLater(starting, throwsA(isA<IosMirrorException>()));
      await pending!.stop();

      await failed;
      expect(service.iosCapture!.stopped, isTrue);
      expect(service.iosInputs, isEmpty);
    });

    test('is view-only without the input services', () async {
      service.iosMirrorSupport = const IosMirrorSupport(screenshots: true);
      final mirror = await startLive();

      expect(mirror.hasInput, isFalse);
      expect(mirror.inputNotice, startsWith('View only.'));
      mirror.touch(ScrcpyTouchAction.down, 0.5, 0.5);
      expect(service.iosInputs, isEmpty);
      await mirror.stop();
    });
  });

  group('input', () {
    test('touches reach the phone where they land on the picture', () async {
      final mirror = await startLive();

      mirror.touch(ScrcpyTouchAction.down, 0.25, 0.5);
      mirror.touch(ScrcpyTouchAction.up, 0.25, 0.5);

      expect(service.lastIosInput!.touches, [
        (IosTouchPhase.down, 0.25, 0.5),
        (IosTouchPhase.up, 0.25, 0.5),
      ]);
      await mirror.stop();
    });

    test('a landscape picture is mapped back onto the panel', () async {
      service.iosOrientation = IosInterfaceOrientation.landscapeRight;
      final mirror = await startLive();

      service.iosCapture!.frame(const Size(2532, 1170));
      await pumpEventQueue();
      mirror.touch(ScrcpyTouchAction.down, 0, 0);

      expect(service.lastIosInput!.touches.single, (
        IosTouchPhase.down,
        1.0,
        0.0,
      ));
      await mirror.stop();
    });

    test('a pinch maps every finger onto the panel', () async {
      service.iosOrientation = IosInterfaceOrientation.landscapeRight;
      final mirror = await startLive();

      service.iosCapture!.frame(const Size(2532, 1170));
      await pumpEventQueue();
      mirror.multiTouch(const [
        ScrcpyTouchContact(0, 0, 0),
        ScrcpyTouchContact(1, 1, 1),
      ]);
      mirror.multiTouch(const [
        ScrcpyTouchContact(0, 0, 0, touching: false),
        ScrcpyTouchContact(1, 1, 1, touching: false),
      ]);

      expect(service.lastIosInput!.frames, [
        [(0, 1.0, 0.0, true), (1, 0.0, 1.0, true)],
        [(0, 1.0, 0.0, false), (1, 0.0, 1.0, false)],
      ]);
      expect(service.lastIosInput!.touches, isEmpty);
      await mirror.stop();
    });

    test('Home is a press of the Consumer Menu button', () async {
      final mirror = await startLive();

      await mirror.pressButton(IosButton.home);

      expect(service.lastIosInput!.buttons, [
        (0x0C, 0x40, true),
        (0x0C, 0x40, false),
      ]);
      await mirror.stop();
    });

    test('Back is a swipe in from the left edge', () async {
      final mirror = await startLive();

      await mirror.pressButton(IosButton.back);

      final touches = service.lastIosInput!.touches;
      expect(touches.first, (IosTouchPhase.down, 0.01, 0.5));
      expect(touches.last.$1, IosTouchPhase.up);
      expect(touches.last.$2, closeTo(0.6, 1e-9));
      final xs = [for (final (_, x, _) in touches) x];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(touches.every((touch) => touch.$3 == 0.5), isTrue);
      await mirror.stop();
    });

    test('paste puts the desktop text on the phone and presses ⌘V', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return {'text': 'hello'};
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final mirror = await startLive();

      expect(await mirror.pasteFromClipboard(), isTrue);

      final input = service.lastIosInput!;
      expect(input.pasteboard, ['hello']);
      expect(input.keys, [
        (0xE3, true),
        (0x19, true),
        (0x19, false),
        (0xE3, false),
      ]);
      await mirror.stop();
    });

    test(
      'a phone that stops taking input turns the mirror view-only',
      () async {
        final mirror = await startLive();
        service.lastIosInput!.open = false;

        mirror.touch(ScrcpyTouchAction.down, 0.5, 0.5);

        expect(mirror.hasInput, isFalse);
        expect(mirror.inputNotice, contains('stopped taking input'));
        await mirror.stop();
      },
    );
  });

  test('a capture that ends by itself ends the session', () async {
    final mirror = await startLive();

    service.iosCapture!.end('The iPhone was disconnected.');

    expect(await mirror.ended, 'The iPhone was disconnected.');
    await mirror.stop();
  });

  test('stopping lets go of held keys and closes everything', () async {
    final mirror = await startLive();
    mirror.handleKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.shiftLeft,
        logicalKey: LogicalKeyboardKey.shiftLeft,
        timeStamp: Duration.zero,
      ),
    );
    final input = service.lastIosInput!;

    await mirror.stop();

    expect(input.keys, [(0xE1, true), (0xE1, false)]);
    expect(input.closed, isTrue);
    expect(service.iosCapture!.stopped, isTrue);
    expect(await mirror.ended, isNull);
  });

  test('a screenshot is the phone\'s own when it offers one', () async {
    final mirror = await startLive();

    expect(await mirror.captureScreenshot(), [1, 2, 3]);
    await mirror.stop();
  });
}
