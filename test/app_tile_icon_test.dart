import 'dart:typed_data';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/apps/apps_controller.dart';
import 'package:eagly/features/apps/components/app_tile.dart';
import 'package:eagly/features/apps/data/app_info.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_app_icon_cache.dart';
import 'support/session_test_support.dart';

/// A tile asks for its own icon when it's built, on every platform: iPhone
/// tiles once didn't, which left the whole pane on initials.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  for (final (platform, device) in [
    ('Android', Device.android('emulator-5554', 'device')),
    ('iOS', Device.ios('00008110-001234567890801E', 'device')),
  ]) {
    testWidgets('an $platform tile asks for its icon', (tester) async {
      final service = FakeSessionService(device)
        ..iconToReturn = Uint8List.fromList([1, 2, 3]);
      final session = DeviceSessionController(device: device, service: service);
      final controller = AppsController(session, iconCache: FakeAppIconCache());
      addTearDown(() {
        controller.dispose();
        session.dispose();
      });
      const app = AppInfo(packageName: 'com.example.notes', appName: 'Notes');

      await tester.pumpWidget(
        MaterialApp(
          home: AppIconView(controller: controller, app: app, size: 48),
        ),
      );
      await tester.pump();

      expect(service.iconFetchRequests, ['com.example.notes']);
      expect(controller.iconFor('com.example.notes'), isNotNull);
    });
  }
}
