import 'dart:typed_data';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/apps/data/app_info.dart';
import 'package:eagly/services/device_session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_ios_app_service.dart';

/// [DeviceSessionRepository]'s Apps calls on an iPhone, over a fake
/// [FakeIosAppService].
void main() {
  late FakeIosAppService apps;
  late DeviceSessionRepository repository;

  setUp(() {
    apps = FakeIosAppService();
    repository = DeviceSessionRepository(
      device: const IosDevice('00008140-0001', 'device'),
      iosAppService: apps,
    );
  });

  group('icons', () {
    test('an iOS app icon comes from SpringBoard, with no label', () async {
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
      apps.icon = png;

      final details = await repository.fetchAppDetails('com.example.notes');

      expect(details, isNotNull);
      expect(details!.icon, png);
      expect(details.label, isNull);
      expect(apps.iconRequests, [
        (deviceId: '00008140-0001', bundleId: 'com.example.notes'),
      ]);
    });

    test('a backend that cannot read icons settles on no icon', () async {
      apps.icon = null;

      final details = await repository.fetchAppDetails('com.example.notes');

      // Not null: null would have the Apps pane retry an icon that never comes.
      expect(details, isNotNull);
      expect(details!.icon, isNull);
      expect(details.label, isNull);
    });

    test('a failed icon read is null, so the Apps pane retries it', () async {
      apps.iconFails = true;

      expect(await repository.fetchAppDetails('com.example.notes'), isNull);
    });
  });

  group('open and force stop', () {
    test('go to the phone', () async {
      await repository.launchApp('com.example.notes');
      await repository.forceStopApp('com.example.notes');

      expect(apps.controlRequests, [
        'open com.example.notes',
        'stop com.example.notes',
      ]);
    });

    test('work only while the phone offers the app service', () async {
      expect(await repository.canControlApps(), isTrue);

      apps.appControl = false;

      expect(await repository.canControlApps(), isFalse);
    });
  });

  group('clear data', () {
    test('goes to the phone', () async {
      await repository.clearAppData('com.example.notes');

      expect(apps.controlRequests, ['clear com.example.notes']);
    });

    test('is offered only where the backend has it', () {
      expect(repository.canClearAppData, isTrue);

      apps.clearsAppData = false;

      expect(repository.canClearAppData, isFalse);
    });
  });

  group('system apps', () {
    setUp(() {
      apps.apps = const [
        AppInfo(packageName: 'com.example.notes', appName: 'Notes'),
        AppInfo(
          packageName: 'com.apple.mobilemail',
          appName: 'Mail',
          isSystemApp: true,
        ),
      ];
    });

    test('are listed only when asked for, sorted in by name', () async {
      final user = await repository.listApps();
      final all = await repository.listApps(includeSystemApps: true);

      expect(apps.listRequests, [false, true]);
      expect(user.map((app) => app.displayName), ['Notes']);
      expect(all.map((app) => app.displayName), ['Mail', 'Notes']);
    });

    test('can be listed only where the backend reads them', () {
      expect(repository.canListSystemApps, isTrue);

      apps.listsSystemApps = false;

      expect(repository.canListSystemApps, isFalse);
    });
  });
}
