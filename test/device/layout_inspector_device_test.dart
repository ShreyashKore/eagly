/// Checks the Layout pane's capture routes against a real Android device or
/// emulator (docs/LAYOUT_INSPECTOR.md). Opt-in, so skipped in CI:
///
/// ```bash
/// EAGLY_TEST_ANDROID_SERIAL=<adb serial> \
///   fvm flutter test test/device/layout_inspector_device_test.dart
/// ```
///
/// It pushes the helper to /data/local/tmp, swipes up on the home screen
/// once (live updates need the UI to change) and presses Home after.
/// Anything else holding UI Automation — a UI test, Appium, Maestro — makes
/// it fail with `busy`.
library;

import 'dart:io';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/layout_inspector/data/layout_parsers.dart';
import 'package:eagly/features/layout_inspector/data/layout_snapshot.dart';
import 'package:eagly/features/layout_inspector/services/inspector_helper.dart';
import 'package:eagly/services/device_session_repository.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:eagly/session/workspace_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _serial = Platform.environment['EAGLY_TEST_ANDROID_SERIAL'];

final String _adb = () {
  final os = Platform.isMacOS
      ? 'macos'
      : Platform.isWindows
      ? 'windows'
      : 'linux';
  return '${Directory.current.path}/platform-tools/$os/adb';
}();

Future<String> _adbOut(List<String> args) async {
  final result = await Process.run(_adb, ['-s', _serial!, ...args]);
  return '${result.stdout}${result.stderr}';
}

Future<void> _eventually(
  String what,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for $what.');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Whether UI Automation is free: `uiautomator dump` is refused while the
/// helper holds it.
Future<bool> _uiAutomationFree() async =>
    (await _adbOut(['exec-out', 'uiautomator', 'dump', '/dev/tty']))
        .contains('</hierarchy>');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = _serial == null ? 'Set EAGLY_TEST_ANDROID_SERIAL' : false;
  late Device device;
  late DeviceSessionRepository repository;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() {
    device = Device(_serial ?? '', 'device', platform: DevicePlatform.android);
    repository = DeviceSessionRepository(device: device, adbPath: _adb);
  });

  tearDown(() => _adbOut(['shell', 'input', 'keyevent', 'HOME']));

  test('the helper walks every window and takes a screenshot', () async {
    final helper = await repository.startInspectorHelper();
    try {
      final started = DateTime.now();
      final snapshot = parseHelperSnapshot(
        await helper.snapshot(),
        capturedAt: started,
      );
      final took = DateTime.now().difference(started);
      expect(
        snapshot.windows.map((window) => window.type),
        contains('application'),
      );
      expect(snapshot.nodeCount, greaterThan(5));
      expect(snapshot.displaySize.width, greaterThan(0));
      expect(snapshot.screenshot, isNotNull);
      // A JPEG.
      expect(snapshot.screenshot!.take(2), [0xFF, 0xD8]);
      expect(took, lessThan(const Duration(seconds: 2)));
    } finally {
      await helper.close();
    }
    expect(await _uiAutomationFree(), isTrue);
  }, skip: skip);

  test('a second helper is refused as busy, not crashed', () async {
    final first = await repository.startInspectorHelper();
    try {
      await expectLater(
        repository.startInspectorHelper(),
        throwsA(
          isA<InspectorHelperException>().having(
            (error) => error.isBusy,
            'isBusy',
            isTrue,
          ),
        ),
      );
    } finally {
      await first.close();
    }
  }, skip: skip);

  test('uiautomator and dumpsys, the route that needs no helper', () async {
    final snapshot = await repository.captureLayoutWithUiAutomator();
    expect(snapshot.source, LayoutSource.uiautomator);
    expect(snapshot.nodeCount, greaterThan(1));
    expect(snapshot.displaySize.width, greaterThan(0));

    final views = await repository.dumpViewHierarchy();
    expect(views, isNotNull);
    views!.annotate(snapshot);
    expect(snapshot.nodes.where((node) => node.view != null), isNotEmpty);
  }, skip: skip);

  test(
    'the pane follows the screen live, then lets UI Automation go',
    () async {
      final session = DeviceSessionController(
        device: device,
        service: repository,
      );
      final controller = session.layoutInspectorController;
      try {
        session.openPane(WorkspacePane.layoutInspector);
        await _eventually('a capture', () => controller.snapshot != null);
        expect(controller.snapshot!.source, LayoutSource.helper);
        expect(
          controller.snapshot!.nodes.where((node) => node.view != null),
          isNotEmpty,
          reason: 'dumpsys View classes joined in',
        );

        await controller.setLive(true);
        final before = controller.snapshot!.capturedAt;
        final size = controller.snapshot!.displaySize;
        await _adbOut([
          'shell',
          'input',
          'swipe',
          '${size.width ~/ 2}',
          '${size.height * 0.85 ~/ 1}',
          '${size.width ~/ 2}',
          '${size.height * 0.25 ~/ 1}',
          '300',
        ]);
        await _eventually(
          'a capture after the swipe',
          () => controller.snapshot!.capturedAt.isAfter(before),
        );

        session.closePane(WorkspacePane.layoutInspector);
        expect(controller.live, isFalse);
      } finally {
        session.dispose();
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(await _uiAutomationFree(), isTrue);
    },
    skip: skip,
  );
}
