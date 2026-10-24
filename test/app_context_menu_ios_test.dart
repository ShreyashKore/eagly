import 'dart:typed_data';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/apps/apps_feature_view.dart';
import 'package:eagly/features/apps/data/app_info.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

/// An iPhone app's right-click menu: what it offers, and Clear Data only for
/// a debug build.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSessionService service;
  DeviceSessionController? session;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  tearDown(() {
    session?.dispose();
    session = null;
  });

  Future<void> openMenu(
    WidgetTester tester, {
    required bool appControl,
    required String appName,
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final device = Device.ios('00008110-001234567890801E', 'device');
    service = FakeSessionService(device)
      ..appControl = appControl
      // Succeed at icons, so no retry timer outlives the test.
      ..iconToReturn = Uint8List.fromList([1, 2, 3])
      ..appsToReturn = const [
        AppInfo(
          packageName: 'com.example.dev',
          appName: 'Dev',
          isDebuggable: true,
        ),
        AppInfo(packageName: 'com.example.store', appName: 'Store'),
      ];
    session = DeviceSessionController(device: device, service: service);
    final controller = session!.appsController;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: AppsFeatureView(controller: controller, onClose: () {}),
        ),
      ),
    );
    await controller.refresh();
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(find.text(appName)),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String label) => tester
      .widget<PopupMenuItem<Object?>>(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
        ),
      )
      .enabled;

  testWidgets('a debug build can have its data cleared', (tester) async {
    await openMenu(tester, appControl: true, appName: 'Dev');

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Force Stop'), findsOneWidget);
    expect(enabled(tester, 'Clear Data…'), isTrue);
    expect(find.text('App Info'), findsNothing);
  });

  testWidgets("a release build's data is sealed", (tester) async {
    await openMenu(tester, appControl: true, appName: 'Store');

    expect(enabled(tester, 'Clear Data…'), isFalse);
    expect(enabled(tester, 'Uninstall…'), isTrue);
  });

  testWidgets('without the app service, no Open or Force Stop', (tester) async {
    await openMenu(tester, appControl: false, appName: 'Dev');

    expect(find.text('Open'), findsNothing);
    expect(find.text('Force Stop'), findsNothing);
    expect(enabled(tester, 'Clear Data…'), isTrue);
  });
}
