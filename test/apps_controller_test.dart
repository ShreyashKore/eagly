import 'dart:typed_data';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/apps/apps_controller.dart';
import 'package:eagly/features/apps/data/app_info.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
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

  AppsController createController({Device? withDevice}) {
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
    return session!.appsController;
  }

  tearDown(() {
    session?.dispose();
    session = null;
  });

  test('refresh loads apps from the repository', () async {
    final controller = createController();
    service.appsToReturn = const [
      AppInfo(packageName: 'com.example.a', appName: 'Alpha'),
      AppInfo(packageName: 'com.example.b', appName: 'Beta'),
    ];

    await controller.refresh();

    expect(controller.loadState, AppLoadState.ready);
    expect(controller.apps, hasLength(2));
    expect(controller.filteredApps.map((a) => a.displayName), [
      'Alpha',
      'Beta',
    ]);
  });

  test('refresh surfaces an error when the device is disconnected', () async {
    final controller = createController();
    session!.updateDevice(
      device.copyWith(connectionState: DeviceConnectionState.disconnected),
    );

    await controller.refresh();

    expect(controller.loadState, AppLoadState.error);
    expect(controller.error, isNotNull);
  });

  test('setSearchText narrows filteredApps by name or package', () async {
    final controller = createController();
    service.appsToReturn = const [
      AppInfo(packageName: 'com.example.chat', appName: 'Chatter'),
      AppInfo(packageName: 'com.example.notes', appName: 'Notes'),
    ];
    await controller.refresh();

    controller.setSearchText('chat');

    expect(controller.filteredApps, hasLength(1));
    expect(controller.filteredApps.single.packageName, 'com.example.chat');

    controller.setSearchText('com.example.notes');
    expect(controller.filteredApps.single.appName, 'Notes');
  });

  test('uninstall removes the app from the list on success', () async {
    final controller = createController();
    const app = AppInfo(packageName: 'com.example.a', appName: 'Alpha');
    service.appsToReturn = const [app];
    await controller.refresh();

    final message = await controller.uninstall(app);

    expect(service.uninstallRequests, ['com.example.a']);
    expect(message, 'Uninstalled.');
    expect(controller.apps, isEmpty);
  });

  test('uninstall keeps the app in the list on failure', () async {
    final controller = createController();
    const app = AppInfo(packageName: 'com.example.a', appName: 'Alpha');
    service.appsToReturn = const [app];
    await controller.refresh();
    service.uninstallResult = DeviceCommandResult.failure(
      error: 'Device offline.',
    );

    final message = await controller.uninstall(app);

    expect(message, 'Device offline.');
    expect(controller.apps, [app]);
  });

  test(
    'launch calls through to the repository with the package name',
    () async {
      final controller = createController();
      const app = AppInfo(packageName: 'com.example.a', appName: 'Alpha');

      final message = await controller.launch(app);

      expect(service.launchRequests, ['com.example.a']);
      expect(message, 'Opened.');
    },
  );

  test('canLaunchApps and canManageAppState are false on iOS', () {
    final controller = createController(
      withDevice: Device.ios('00008110-001234567890801E', 'device'),
    );

    expect(controller.canLaunchApps, isFalse);
    expect(controller.canManageAppState, isFalse);
    expect(controller.canShowSystemApps, isFalse);
  });

  test(
    'forceStop calls through to the repository with the package name',
    () async {
      final controller = createController();
      const app = AppInfo(packageName: 'com.example.a', appName: 'Alpha');

      final message = await controller.forceStop(app);

      expect(service.forceStopRequests, ['com.example.a']);
      expect(message, 'Force-stopped.');
    },
  );

  test(
    'clearData calls through to the repository with the package name',
    () async {
      final controller = createController();
      const app = AppInfo(packageName: 'com.example.a', appName: 'Alpha');

      final message = await controller.clearData(app);

      expect(service.clearDataRequests, ['com.example.a']);
      expect(message, 'Cleared.');
    },
  );

  test(
    'openAppInfo calls through to the repository with the package name',
    () async {
      final controller = createController();
      const app = AppInfo(packageName: 'com.example.a', appName: 'Alpha');

      await controller.openAppInfo(app);

      expect(service.appInfoRequests, ['com.example.a']);
    },
  );

  test('ensureIconLoaded caches the icon and fetches only once', () async {
    final controller = createController();
    service.iconToReturn = Uint8List.fromList([1, 2, 3]);

    controller.ensureIconLoaded('com.example.a');
    await Future<void>.delayed(Duration.zero);
    controller.ensureIconLoaded('com.example.a');
    await Future<void>.delayed(Duration.zero);

    expect(service.iconFetchRequests, ['com.example.a']);
    expect(controller.iconFor('com.example.a'), [1, 2, 3]);
  });

  test('setShowSystemApps forwards the filter to the repository', () async {
    final controller = createController();
    service.appsToReturn = const [
      AppInfo(packageName: 'com.example.a', appName: 'Alpha'),
    ];
    await controller.refresh();

    controller.setShowSystemApps(true);
    await Future<void>.delayed(Duration.zero);

    expect(controller.showSystemApps, isTrue);
    expect(service.listAppsIncludeSystemAppsRequests, [false, true]);
  });

  test('viewLogs opens a live log tab pre-filtered to the package', () {
    final controller = createController();
    const app = AppInfo(packageName: 'com.example.a', appName: 'Alpha');

    expect(session!.isLogsOpen, isFalse);
    final tabsBefore = session!.logSessionManager.tabs.length;

    controller.viewLogs(app);

    expect(session!.isLogsOpen, isTrue);
    expect(session!.logSessionManager.tabs.length, tabsBefore + 1);
    final tab = session!.logSessionManager.tabs.last;
    expect(tab.classicFilter.packageController.text, 'com.example.a');
  });
}
