import 'dart:io';

import 'package:eagly/constants/app_constants.dart';
import 'package:eagly/data/device.dart';
import 'package:eagly/services/devices_repository.dart';
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
  late DevicesRepository repository;
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
    repository = DevicesRepository.forTesting(
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

  test(
    'creates a session and auto-selects a single connected device',
    () async {
      adbTool.androidDevices = [
        Device('emulator-5554', 'device', platform: DevicePlatform.android),
      ];
      manager = buildManager();

      await sync();

      expect(manager!.sessions.map((session) => session.id), ['emulator-5554']);
      expect(manager!.selectedId, 'emulator-5554');
      expect(manager!.selected?.isActivated, isTrue);
    },
  );

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

  group('imported logs workspace (device-less import)', () {
    /// A minimal valid Android Studio logcat JSON export with one entry.
    const validExportJson =
        '{"logcatMessages":[{"header":{"entryType":"log","logLevel":"INFO",'
        '"pid":1,"tid":2,"tag":"T","applicationId":"com.example",'
        '"processName":"p","timestamp":{"seconds":1,"nanos":0}},'
        '"message":"hello world"}]}';

    File writeLog(String name) =>
        File('${tempDir.path}/$name')..writeAsStringSync(validExportJson);

    test('opens a file into a new workspace tab and selects it', () async {
      manager = buildManager();
      final file = writeLog('a.json');

      final result = await manager!.importLog(path: file.path);

      expect(result.isSuccess, isTrue);
      expect(manager!.sessions, hasLength(1));
      final workspace = manager!.sessions.single;
      expect(workspace.id, AppConstants.importedWorkspaceId);
      expect(workspace.isImportedWorkspace, isTrue);
      expect(manager!.selectedId, AppConstants.importedWorkspaceId);

      final tabs = workspace.logSessionManager.tabs;
      expect(tabs, hasLength(1));
      expect(tabs.single.isImported, isTrue);
    });

    test('reuses the same workspace for additional imports', () async {
      manager = buildManager();

      await manager!.importLog(path: writeLog('a.json').path);
      await manager!.importLog(path: writeLog('b.json').path);

      expect(manager!.sessions, hasLength(1));
      expect(manager!.sessions.single.logSessionManager.tabs, hasLength(2));
    });

    test(
      'closing the workspace builds a fresh one on the next import',
      () async {
        manager = buildManager();
        await manager!.importLog(path: writeLog('a.json').path);

        manager!.close(AppConstants.importedWorkspaceId);
        expect(manager!.sessions, isEmpty);

        final result = await manager!.importLog(path: writeLog('b.json').path);

        expect(result.isSuccess, isTrue);
        expect(manager!.sessions, hasLength(1));
        expect(manager!.sessions.single.logSessionManager.tabs, hasLength(1));
      },
    );

    test('a cancelled/failed import creates no workspace', () async {
      manager = buildManager();

      final result = await manager!.importLog(
        path: '${tempDir.path}/missing.json',
      );

      expect(result.isSuccess, isFalse);
      expect(manager!.sessions, isEmpty);
    });
  });
}
