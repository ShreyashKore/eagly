import 'package:eagly/data/device.dart';
import 'package:eagly/features/mirror/mirror_controller.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSessionService service;
  late Device device;
  DeviceSessionController? session;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  MirrorController createMirror({Device? withDevice}) {
    device =
        withDevice ??
        Device(
          'emulator-5554',
          'device',
          platform: DevicePlatform.android,
          brand: 'Google',
          model: 'Pixel 8',
        );
    service = FakeSessionService(device);
    session = DeviceSessionController(device: device, service: service);
    return session!.mirrorController;
  }

  tearDown(() {
    session?.dispose();
    session = null;
  });

  test('mirror starts for a connected Android device', () async {
    final mirror = createMirror();

    await mirror.start();

    expect(mirror.screenMirrorState, ScreenMirrorState.running);
    expect(mirror.isScreenMirrorRunning, isTrue);
    expect(service.startedMirrorCount, 1);
  });

  test('mirror is unsupported for iOS devices', () async {
    final mirror = createMirror(
      withDevice: Device.ios('00008110-001234567890801E', 'device'),
    );

    await mirror.start();

    expect(mirror.screenMirrorState, ScreenMirrorState.unsupported);
    expect(service.startedMirrorCount, 0);
  });

  test('mirror stops when the device disconnects', () async {
    final mirror = createMirror();

    await mirror.start();
    expect(mirror.isScreenMirrorRunning, isTrue);

    session!.updateDevice(
      device.copyWith(connectionState: DeviceConnectionState.disconnected),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(mirror.screenMirrorState, ScreenMirrorState.stopped);
    expect(service.stoppedMirrorCount, 1);
  });

  test('opening the mirror via the session starts the stream', () async {
    final mirror = createMirror();

    session!.openMirror();
    expect(session!.isMirrorOpen, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(mirror.isScreenMirrorRunning, isTrue);
    expect(service.startedMirrorCount, 1);

    session!.closeMirror();
    expect(session!.isMirrorOpen, isFalse);
  });

  test('changing quality restarts a running mirror', () async {
    final mirror = createMirror();

    await mirror.start();
    expect(service.startedMirrorCount, 1);

    await mirror.setQuality(MirrorQuality.high);

    expect(mirror.mirrorQuality, MirrorQuality.high);
    expect(service.startedMirrorCount, 2);
  });

  group('keyboard forwarding', () {
    FakeScrcpyControlChannel? channel;

    KeyEvent keyDown(LogicalKeyboardKey key, {String? character}) =>
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: key,
          character: character,
          timeStamp: Duration.zero,
        );

    Future<MirrorController> runningMirror() async {
      final mirror = createMirror();
      final opened = await FakeScrcpyControlChannel.open();
      channel = opened;
      service.mirrorControlChannel = opened;
      await mirror.start();
      return mirror;
    }

    tearDown(() async {
      await channel?.close();
      channel = null;
    });

    test('a typed character reaches the device as INJECT_TEXT', () async {
      final mirror = await runningMirror();

      final result = mirror.handleKeyEvent(
        keyDown(LogicalKeyboardKey.keyA, character: 'a'),
      );

      expect(result, KeyEventResult.handled);
      // type(1) + length(4, big-endian) + utf-8 payload.
      expect(await channel!.settle(), [1, 0, 0, 0, 1, 0x61]);
    });

    test('a navigation key reaches the device as INJECT_KEYCODE', () async {
      final mirror = await runningMirror();

      mirror.handleKeyEvent(keyDown(LogicalKeyboardKey.enter));

      // type(1) + action(1) + keycode(4) + repeat(4) + metaState(4).
      expect(await channel!.settle(), [
        0,
        0,
        0,
        0,
        0,
        66,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
    });

    test(
      'losing focus releases a key the device still thinks is down',
      () async {
        final mirror = await runningMirror();
        mirror.handleKeyEvent(keyDown(LogicalKeyboardKey.arrowDown));
        await channel!.settle();

        mirror.handleKeyboardFocusChange(false);

        // The trailing message is a key-up (action 1) for KEYCODE_DPAD_DOWN.
        final tail = (await channel!.settle()).sublist(14);
        expect(tail, [0, 1, 0, 0, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0]);
      },
    );

    test('keys are not forwarded without a control channel', () async {
      final mirror = createMirror();
      await mirror.start();

      expect(
        mirror.handleKeyEvent(keyDown(LogicalKeyboardKey.keyA, character: 'a')),
        KeyEventResult.ignored,
      );
    });
  });
}
