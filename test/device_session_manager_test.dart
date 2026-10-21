import 'dart:io';

import 'package:eagly/constants/app_constants.dart';
import 'package:eagly/data/app_install_conflict.dart';
import 'package:eagly/data/device.dart';
import 'package:eagly/features/file_manager/data/device_file_entry.dart';
import 'package:eagly/features/file_manager/file_manager_controller.dart';
import 'package:eagly/features/file_manager/services/device_file_system.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
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
  late FakeIosDeviceService iosDevicesService;
  late DevicesRepository repository;
  late Directory tempDir;
  DeviceSessionManager? manager;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() {
    adbTool = FakeAdbTool();
    iosDevicesService = FakeIosDeviceService();
    repository = DevicesRepository.forTesting(
      adbTool: adbTool,
      iosDeviceService: iosDevicesService,
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

  test('reloading a tab swaps in a fresh session in the same slot', () async {
    adbTool.androidDevices = [
      Device('emulator-5554', 'device', platform: DevicePlatform.android),
      Device('emulator-5556', 'device', platform: DevicePlatform.android),
    ];
    manager = buildManager();
    await sync();
    manager!.select('emulator-5554');
    final original = manager!.selected;

    await manager!.reload('emulator-5554');

    expect(manager!.sessions.map((session) => session.id), [
      'emulator-5554',
      'emulator-5556',
    ]);
    expect(manager!.selectedId, 'emulator-5554');
    expect(manager!.selected, isNot(same(original)));
    expect(manager!.selected?.isActivated, isTrue);
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

    test('installs a compatible APK dropped onto the device screen', () async {
      final session = buildSession(Device.android('emulator-5554', 'device'));
      final apk = File('${tempDir.path}/sample.apk')..writeAsStringSync('apk');

      final result = await session.handleDroppedPaths([apk.path]);

      expect(result, isNotNull);
      expect(result!.installed, ['sample.apk']);
      expect(result.errors, isEmpty);
      expect(result.message, contains('Installed sample.apk'));
    });

    group('over a conflicting installed copy', () {
      const conflict = AppInstallConflict(
        kind: AppInstallConflictKind.signature,
        packageName: 'com.example.app',
      );
      late FakeSessionService service;
      late DeviceSessionController session;
      late File apk;

      setUp(() {
        final device = Device.android('emulator-5554', 'device');
        service = FakeSessionService(device)
          ..installResult = const DeviceCommandResult(
            error: 'signed with a different key',
            installConflict: conflict,
          );
        session = DeviceSessionController(device: device, service: service);
        addTearDown(session.dispose);
        apk = File('${tempDir.path}/sample.apk')..writeAsStringSync('apk');
      });

      test('a failed install carries the conflict and file to retry', () async {
        final result = await session.installAppFromPath(apk.path);

        expect(result.isSuccess, isFalse);
        expect(result.conflict, same(conflict));
        expect(result.filePath, apk.path);
        expect(service.uninstallRequests, isEmpty);
      });

      test('a drop lists it apart from the errors', () async {
        final result = await session.handleDroppedPaths([apk.path]);

        expect(result!.errors, isEmpty);
        expect(result.conflicts.single.conflict, same(conflict));
      });

      test('forcing it uninstalls the installed copy, then installs', () async {
        service.installResult = DeviceCommandResult.success(message: 'ok');

        final result = await session.forceInstallAppFromPath(
          apk.path,
          conflict,
        );

        expect(result.isSuccess, isTrue);
        expect(service.uninstallRequests, ['com.example.app']);
        expect(service.installRequests, [apk.path]);
      });

      test('a failed uninstall stops before installing', () async {
        service.uninstallResult = DeviceCommandResult.failure(error: 'nope');

        final result = await session.forceInstallAppFromPath(
          apk.path,
          conflict,
        );

        expect(result.error, contains('Could not uninstall com.example.app'));
        expect(service.installRequests, isEmpty);
      });
    });

    group('onto a file-manager folder', () {
      late _RecordingFileSystem fileSystem;

      setUp(() {
        fileSystem = _RecordingFileSystem();
        FileManagerController.fileSystemFactory = (_) => fileSystem;
      });

      tearDown(() => FileManagerController.fileSystemFactory = null);

      test('copies plain files into the given folder', () async {
        final session = buildSession(Device.android('emulator-5554', 'device'));
        final txt = File('${tempDir.path}/notes.txt')..writeAsStringSync('x');

        final result = await session.handleDroppedPaths([
          txt.path,
        ], copyDirectory: '/sdcard/DCIM');

        expect(fileSystem.uploads, [(txt.path, '/sdcard/DCIM')]);
        expect(result!.copied, ['notes.txt']);
        expect(result.message, 'Copied notes.txt to /sdcard/DCIM.');
      });

      test('copies a compatible APK instead of installing it', () async {
        final service = FakeSessionService(
          Device.android('emulator-5554', 'device'),
        );
        final session = DeviceSessionController(
          device: service.device,
          service: service,
        );
        addTearDown(session.dispose);
        final apk = File('${tempDir.path}/sample.apk')
          ..writeAsStringSync('apk');

        final result = await session.handleDroppedPaths(
          [apk.path],
          copyDirectory: '/sdcard/DCIM',
          installApps: false,
        );

        expect(service.installRequests, isEmpty);
        expect(fileSystem.uploads, [(apk.path, '/sdcard/DCIM')]);
        expect(result!.installed, isEmpty);
        expect(result.copied, ['sample.apk']);
      });

      test('installs the APK and still copies the rest there', () async {
        final session = buildSession(Device.android('emulator-5554', 'device'));
        final apk = File('${tempDir.path}/sample.apk')
          ..writeAsStringSync('apk');
        final txt = File('${tempDir.path}/notes.txt')..writeAsStringSync('x');

        final result = await session.handleDroppedPaths([
          apk.path,
          txt.path,
        ], copyDirectory: '/sdcard/DCIM');

        expect(result!.installed, ['sample.apk']);
        expect(fileSystem.uploads, [(txt.path, '/sdcard/DCIM')]);
      });

      test('copies an other-platform installable as a file', () async {
        final session = buildSession(Device.android('emulator-5554', 'device'));
        final ipa = File('${tempDir.path}/Sample.ipa')
          ..writeAsStringSync('ipa');

        final result = await session.handleDroppedPaths([
          ipa.path,
        ], copyDirectory: '/sdcard/DCIM');

        expect(result!.errors, isEmpty);
        expect(result.copied, ['Sample.ipa']);
      });
    });

    test(
      'rejects an other-platform installable rather than copying it',
      () async {
        final session = buildSession(Device.android('emulator-5554', 'device'));
        final ipa = File('${tempDir.path}/Sample.ipa')
          ..writeAsStringSync('ipa');

        final result = await session.handleDroppedPaths([ipa.path]);

        expect(result, isNotNull);
        expect(result!.installed, isEmpty);
        expect(result.copied, isEmpty);
        expect(result.errors.single, contains('APK'));
      },
    );

    test('reports an error when dropping onto a disconnected device', () async {
      final session = buildSession(
        Device.android(
          'emulator-5554',
          'offline',
          connectionState: DeviceConnectionState.disconnected,
        ),
      );
      final apk = File('${tempDir.path}/sample.apk')..writeAsStringSync('apk');

      final result = await session.handleDroppedPaths([apk.path]);

      expect(result, isNotNull);
      expect(result!.installed, isEmpty);
      expect(result.errors.single, contains('Reconnect'));
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

/// Records uploads instead of pushing them to a device.
class _RecordingFileSystem implements DeviceFileSystem {
  final uploads = <(String, String)>[];

  @override
  Future<void> upload({
    required String localPath,
    required String deviceDirectory,
  }) async {
    uploads.add((localPath, deviceDirectory));
  }

  @override
  String get dropTargetDirectory => '/sdcard/Download';

  @override
  String get initialPath => '/sdcard';

  @override
  Future<List<DeviceFileEntry>> list(String path) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
