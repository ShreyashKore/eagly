import 'dart:async';
import 'dart:typed_data';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/apps/apps_controller.dart';
import 'package:eagly/features/apps/data/app_info.dart';
import 'package:eagly/features/apps/data/apps_view_options.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_app_icon_cache.dart';
import 'support/session_test_support.dart';

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

  test('on iOS, Open, Force Stop and System apps wait for a refresh', () {
    final controller = createController(
      withDevice: Device.ios('00008110-001234567890801E', 'device'),
    );
    service.appControl = true;

    // Not before the phone has been asked, at the first refresh.
    expect(controller.canLaunchApps, isFalse);
    expect(controller.canForceStopApps, isFalse);
    expect(controller.canOpenAppInfo, isFalse);
    // The Rust backend lists Apple's own apps too.
    expect(controller.canShowSystemApps, isTrue);
  });

  test('on iOS, Open and Force Stop follow the app service', () async {
    final controller = createController(
      withDevice: Device.ios('00008110-001234567890801E', 'device'),
    );
    service.appControl = true;

    await controller.refresh();
    await pumpEventQueue();

    expect(service.appControlProbes, 1);
    expect(controller.canLaunchApps, isTrue);
    expect(controller.canForceStopApps, isTrue);

    // The disk image goes with a restart of the phone.
    service.appControl = false;
    await controller.refresh();
    await pumpEventQueue();

    expect(service.appControlProbes, 2);
    expect(controller.canLaunchApps, isFalse);
  });

  test('on iOS, only a debug build can have its data cleared', () {
    final controller = createController(
      withDevice: Device.ios('00008110-001234567890801E', 'device'),
    );
    const debug = AppInfo(packageName: 'com.example.dev', isDebuggable: true);
    const release = AppInfo(packageName: 'com.example.store');

    expect(controller.canClearAppData, isTrue);
    expect(controller.canClearDataOf(debug), isTrue);
    expect(controller.canClearDataOf(release), isFalse);
  });

  test('Android never asks for the app service', () async {
    final controller = createController();

    await controller.refresh();

    expect(service.appControlProbes, 0);
    expect(controller.canLaunchApps, isTrue);
    expect(controller.canForceStopApps, isTrue);
    expect(controller.canClearAppData, isTrue);
    expect(
      controller.canClearDataOf(const AppInfo(packageName: 'a.b')),
      isTrue,
    );
    expect(controller.canOpenAppInfo, isTrue);
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
      service.appPullFails = true;

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
      service.appPullFails = true;
      const app = AppInfo(packageName: 'com.example.a', appName: 'Alpha');

      controller.ensureIconLoaded(app);
      async.elapse(const Duration(seconds: 1));

      expect(service.iconFetchRequests, List.filled(5, 'com.example.a'));
      expect(controller.iconFor('com.example.a'), isNull);

      // Given up until the app changes: a tile rebuilt for the same app
      // (scrolled back into view, or a refresh) doesn't start over.
      controller.ensureIconLoaded(
        const AppInfo(packageName: 'com.example.a', appName: 'Alpha'),
      );
      async.elapse(const Duration(seconds: 1));
      expect(service.iconFetchRequests, hasLength(5));

      // An update does earn a fresh attempt.
      service.appPullFails = false;
      service.iconToReturn = Uint8List.fromList([1]);
      controller.ensureIconLoaded(
        const AppInfo(
          packageName: 'com.example.a',
          appName: 'Alpha',
          versionName: '2.0',
        ),
      );
      async.elapse(Duration.zero);
      expect(service.iconFetchRequests, hasLength(6));
      expect(controller.iconFor('com.example.a'), [1]);
    });
  });

  test('does not retry an APK that has no icon to extract', () {
    fakeAsync((async) {
      AppsController.iconRetryBaseDelay = const Duration(milliseconds: 1);
      final controller = createController();
      service.iconToReturn = null;
      service.labelsToReturn = {'com.example.a': 'Alpha Game'};
      const app = AppInfo(packageName: 'com.example.a', appName: 'Alpha');

      controller.ensureIconLoaded(app);
      async.elapse(const Duration(seconds: 1));
      controller.ensureIconLoaded(app);
      async.elapse(const Duration(seconds: 1));

      expect(service.iconFetchRequests, ['com.example.a']);
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

  test('viewLogs filters an iOS app by its process, not its bundle', () {
    final controller = createController(
      withDevice: Device.ios('00008110-001234567890801E', 'device'),
    );
    // iOS log lines carry the executable's name; the bundle id is in none.
    const app = AppInfo(
      packageName: 'com.example.notes',
      appName: 'Notes',
      processName: 'NotesApp',
    );

    controller.viewLogs(app);

    final tab = session!.logSessionManager.tabs.last;
    expect(tab.filter.conditions.single.value, 'NotesApp');
  });

  test(
    'refresh names Android apps from the label cache and sorts by name',
    () async {
      final controller = createController();
      iconCache.labels['com.zeta.mail'] = 'Aardvark Mail';
      service.appsToReturn = const [
        AppInfo(packageName: 'com.alpha.notes'),
        AppInfo(packageName: 'com.zeta.mail'),
      ];

      await controller.refresh();

      expect(controller.apps.map((a) => a.displayName), [
        'Aardvark Mail',
        'com.alpha.notes',
      ]);
    },
  );

  test('a fetched label renames the app in place and is cached', () {
    fakeAsync((async) {
      final controller = createController();
      service.appsToReturn = const [
        AppInfo(packageName: 'com.alpha.notes'),
        AppInfo(packageName: 'com.zeta.mail'),
      ];
      unawaited(controller.refresh());
      async.flushMicrotasks();
      service.labelsToReturn = {'com.zeta.mail': 'Aardvark Mail'};

      controller.ensureIconLoaded(controller.apps.last);
      async.elapse(Duration.zero);

      // Renamed but not re-sorted, so the tile doesn't jump under the cursor.
      expect(controller.apps.map((a) => a.displayName), [
        'com.alpha.notes',
        'Aardvark Mail',
      ]);
      expect(iconCache.labels, {'com.zeta.mail': 'Aardvark Mail'});
      controller.setSearchText('aardvark');
      expect(controller.filteredApps.single.packageName, 'com.zeta.mail');
    });
  });

  test('recentApps lists user apps by latest install or update', () async {
    final controller = createController();
    service.appsToReturn = [
      AppInfo(packageName: 'old', installTime: DateTime(2026, 1, 1)),
      AppInfo(
        packageName: 'reinstalled',
        installTime: DateTime(2025, 1, 1),
        updateTime: DateTime(2026, 9, 1),
      ),
      AppInfo(packageName: 'new', installTime: DateTime(2026, 6, 1)),
      AppInfo(
        packageName: 'system',
        isSystemApp: true,
        installTime: DateTime(2026, 10, 1),
      ),
      const AppInfo(packageName: 'undated'),
    ];
    await controller.refresh();

    expect(controller.recentApps.map((a) => a.packageName), [
      'reinstalled',
      'new',
      'old',
    ]);
  });

  test('view mode and icon size persist across controllers', () {
    final first = createController();
    first.setViewMode(AppsViewMode.list);
    first.setIconSize(AppIconSize.large);

    final second = AppsController(session!, iconCache: iconCache);
    addTearDown(second.dispose);

    expect(second.viewMode, AppsViewMode.list);
    expect(second.iconSize, AppIconSize.large);
    first.setViewMode(AppsViewMode.grid);
    first.setIconSize(AppIconSize.medium);
  });
}
