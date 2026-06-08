import 'dart:io';

import 'package:eagly/data/device.dart';
import 'package:eagly/services/device_repository.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:eagly/session/device_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdbTool adbTool;
  late FakeIdeviceIdTool ideviceIdTool;
  late FakeIdeviceInfoTool ideviceInfoTool;
  late DeviceRepository repository;
  late Directory tempDir;
  DeviceSessionManager? manager;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() {
    adbTool = FakeAdbTool();
    ideviceIdTool = FakeIdeviceIdTool();
    ideviceInfoTool = FakeIdeviceInfoTool();
    repository = DeviceRepository.forTesting(
      adbTool: adbTool,
      ideviceIdTool: ideviceIdTool,
      ideviceInfoTool: ideviceInfoTool,
    );
    tempDir = Directory.systemTemp.createTempSync('device-session-test');
  });

  tearDown(() async {
    manager?.dispose();
    manager = null;
    repository.dispose();
    await adbTool.disposeTool();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  DeviceSessionManager buildManager() {
    return DeviceSessionManager(
      repository: repository,
      serviceFactory: (device) => FakeSessionService(device),
    );
  }

  Future<void> sync() async {
    await repository.refreshDevices(force: true);
    await Future<void>.delayed(Duration.zero);
  }

  test('creates a session and auto-selects a single connected device', () async {
    adbTool.androidDevices = [
      Device('emulator-5554', 'device', platform: DevicePlatform.android),
    ];
    manager = buildManager();

    await sync();

    expect(manager!.sessions.map((session) => session.id), ['emulator-5554']);
    expect(manager!.selectedId, 'emulator-5554');
    expect(manager!.selected?.isActivated, isTrue);
  });

  test('keeps a disconnected device tab and marks it closable', () async {
    adbTool.androidDevices = [
      Device('emulator-5554', 'device', platform: DevicePlatform.android),
    ];
    manager = buildManager();
    await sync();

    adbTool.androidDevices = const [];
    await sync();

    expect(manager!.sessions, hasLength(1));
    expect(manager!.sessions.single.isConnected, isFalse);
    expect(manager!.canClose('emulator-5554'), isTrue);
  });

  test('closing a disconnected tab removes its session', () async {
    adbTool.androidDevices = [
      Device('emulator-5554', 'device', platform: DevicePlatform.android),
    ];
    manager = buildManager();
    await sync();

    adbTool.androidDevices = const [];
    await sync();

    manager!.close('emulator-5554');

    expect(manager!.sessions, isEmpty);
    expect(manager!.selectedId, isNull);
    expect(manager!.isHome, isTrue);
  });

  test('recreates the session when the device reconnects', () async {
    adbTool.androidDevices = [
      Device('emulator-5554', 'device', platform: DevicePlatform.android),
    ];
    manager = buildManager();
    await sync();

    adbTool.androidDevices = const [];
    await sync();
    manager!.close('emulator-5554');
    expect(manager!.sessions, isEmpty);

    adbTool.androidDevices = [
      Device('emulator-5554', 'device', platform: DevicePlatform.android),
    ];
    await sync();

    expect(manager!.sessions, hasLength(1));
    expect(manager!.sessions.single.isConnected, isTrue);
  });

  test('does not auto-select when multiple devices are connected', () async {
    adbTool.androidDevices = [
      Device('emulator-5554', 'device', platform: DevicePlatform.android),
      Device('emulator-5556', 'device', platform: DevicePlatform.android),
    ];
    manager = buildManager();
    await sync();

    expect(manager!.sessions, hasLength(2));
    expect(manager!.selectedId, isNull);
    expect(manager!.isHome, isTrue);
  });

  group('device-level install', () {
    DeviceSessionController buildSession(Device device) {
      final session = DeviceSessionController(
        device: device,
        service: FakeSessionService(device),
      );
      addTearDown(session.dispose);
      return session;
    }

    test('installs a compatible APK dropped on the device', () async {
      final session = buildSession(Device.android('emulator-5554', 'device'));
      final apk = File('${tempDir.path}/sample.apk')..writeAsStringSync('apk');

      final result = await session.installDroppedPaths([apk.path]);

      expect(result.isSuccess, isTrue);
      expect(result.message, contains('Installed sample.apk'));
    });

    test('rejects an incompatible installable for the device', () async {
      final session = buildSession(Device.android('emulator-5554', 'device'));
      final ipa = File('${tempDir.path}/Sample.ipa')..writeAsStringSync('ipa');

      final result = await session.installDroppedPaths([ipa.path]);

      expect(result.isSuccess, isFalse);
    });

    test('rejects dropping multiple installables at once', () async {
      final session = buildSession(Device.android('emulator-5554', 'device'));

      final result = await session.installDroppedPaths([
        '${tempDir.path}/a.apk',
        '${tempDir.path}/b.apk',
      ]);

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('single app binary'));
    });
  });
}
