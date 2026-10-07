import 'dart:async';
import 'dart:typed_data';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/apps/apps_controller.dart';
import 'package:eagly/features/apps/data/app_info.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/services/app_icon_cache.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

/// In-memory [AppIconCache] so icon tests never touch the real filesystem.
class FakeAppIconCache implements AppIconCache {
  final Map<String, Uint8List?> memory = {};
  final List<String> storedPackages = [];

  void seed(String packageName, Uint8List bytes) => memory[packageName] = bytes;

  @override
  Future<Uint8List?> load(String packageName) async {
    if (memory.containsKey(packageName)) return memory[packageName];
    memory[packageName] = null;
    return null;
  }

  @override
  Future<void> store(String packageName, Uint8List bytes) async {
    memory[packageName] = bytes;
    storedPackages.add(packageName);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSessionService service;
  late Device device;
  late FakeAppIconCache iconCache;
  DeviceSessionController? session;
  AppsController? controller;

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
    iconCache = FakeAppIconCache();
    session = DeviceSessionController(device: device, service: service);
    controller = AppsController(session!, iconCache: iconCache);
    return controller!;
  }

  tearDown(() {
    AppsController.iconRetryBaseDelay = const Duration(seconds: 2);
    AppsController.iconRetryMaxDelay = const Duration(minutes: 2);
    controller?.dispose();
    controller = null;
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

  test('ensureIconLoaded fetches the icon once and caches it', () {
    fakeAsync((async) {
      final controller = createController();
      service.iconToReturn = Uint8List.fromList([1, 2, 3]);
      const app = AppInfo(packageName: 'com.example.a', appName: 'Alpha');

      controller.ensureIconLoaded(app);
      async.elapse(Duration.zero);
      controller.ensureIconLoaded(app);
      async.elapse(Duration.zero);

      expect(service.iconFetchRequests, ['com.example.a']);
      expect(controller.iconFor('com.example.a'), [1, 2, 3]);
      expect(iconCache.storedPackages, ['com.example.a']);
    });
  });

  test('shows the cached icon while the fresh fetch is in flight', () {
    fakeAsync((async) {
      final controller = createController();
      const app = AppInfo(packageName: 'com.example.a', appName: 'Alpha');
      iconCache.seed('com.example.a', Uint8List.fromList([9]));
      service.iconToReturn = Uint8List.fromList([7]);
      service.iconGate = Completer<void>();

      controller.ensureIconLoaded(app);

      // Let the disk-cache load land (a microtask) with the fetch still held.
      async.flushMicrotasks();
      expect(controller.iconFor('com.example.a'), [9]);
      expect(service.iconFetchRequests, ['com.example.a']);

      service.iconGate!.complete();
      async.elapse(Duration.zero);
      expect(controller.iconFor('com.example.a'), [7]);
      expect(iconCache.storedPackages, ['com.example.a']);
    });
  });

  test('keeps the cached icon when the fresh fetch fails', () {
    fakeAsync((async) {
      AppsController.iconRetryBaseDelay = const Duration(seconds: 10);
      final controller = createController();
      const app = AppInfo(packageName: 'com.example.a', appName: 'Alpha');
      final cached = Uint8List.fromList([9]);
      iconCache.seed('com.example.a', cached);
      service.iconToReturn = null;

      controller.ensureIconLoaded(app);
      async.elapse(const Duration(milliseconds: 1));

      expect(controller.iconFor('com.example.a'), cached);
    });
  });

  test('retries a failed fetch with backoff then gives up', () {
    fakeAsync((async) {
      AppsController.iconRetryBaseDelay = const Duration(milliseconds: 1);
      AppsController.iconRetryMaxDelay = const Duration(milliseconds: 4);
      final controller = createController();
      service.iconToReturn = null;
      const app = AppInfo(packageName: 'com.example.a', appName: 'Alpha');

      controller.ensureIconLoaded(app);
      async.elapse(const Duration(seconds: 1));

      expect(service.iconFetchRequests, List.filled(5, 'com.example.a'));
      expect(controller.iconFor('com.example.a'), isNull);
    });
  });

  test('fetches newly updated apps before the rest of the queue', () {
    fakeAsync((async) {
      final controller = createController();
      service.iconToReturn = Uint8List.fromList([1]);
      service.iconGate = Completer<void>();

      final base = DateTime(2026, 1, 1);
      AppInfo app(String name, Duration age) =>
          AppInfo(packageName: name, updateTime: base.add(age));

      // Four apps fill the concurrency slots in request order; the remaining
      // two queue, and the more recently updated of them must go first.
      controller.ensureIconLoaded(app('com.low1', const Duration(minutes: 1)));
      controller.ensureIconLoaded(app('com.low2', const Duration(minutes: 2)));
      controller.ensureIconLoaded(app('com.low3', const Duration(minutes: 3)));
      controller.ensureIconLoaded(app('com.low4', const Duration(minutes: 4)));
      controller.ensureIconLoaded(app('com.mid', const Duration(minutes: 5)));
      controller.ensureIconLoaded(app('com.high', const Duration(minutes: 6)));

      expect(service.iconFetchRequests, [
        'com.low1',
        'com.low2',
        'com.low3',
        'com.low4',
      ]);

      service.iconGate!.complete();
      async.elapse(Duration.zero);

      expect(service.iconFetchRequests, [
        'com.low1',
        'com.low2',
        'com.low3',
        'com.low4',
        'com.high',
        'com.mid',
      ]);
    });
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
    expect(tab.filter.conditions.single.value, 'com.example.a');
  });
}
