import 'package:eagly/data/device.dart';
import 'package:eagly/features/apps/apps_controller.dart';
import 'package:eagly/features/apps/apps_feature_view.dart';
import 'package:eagly/features/apps/components/app_utility_menu.dart';
import 'package:eagly/features/apps/data/app_info.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

/// The Apps → Utilities bridge: right-clicking an app offers the catalog's
/// app-targeted commands pre-filled with that package, and refuses the
/// dangerous ones for preinstalled packages.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSessionService service;
  DeviceSessionController? session;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  AppsController createController({
    DevicePlatform platform = DevicePlatform.android,
  }) {
    final device = platform == DevicePlatform.android
        ? Device(
            'emulator-5554',
            'device',
            platform: DevicePlatform.android,
            brand: 'Google',
            model: 'Pixel 8',
          )
        : Device(
            '00008030-001',
            'device',
            platform: DevicePlatform.ios,
            model: 'iPhone 15',
          );
    service = FakeSessionService(device);
    session = DeviceSessionController(device: device, service: service);
    return session!.appsController;
  }

  tearDown(() {
    session?.dispose();
    session = null;
  });

  Widget host(AppsController controller) => MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: AppsFeatureView(controller: controller, onClose: () {}),
    ),
  );

  void useTallWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Right-clicks the first app tile and opens the Utilities submenu.
  Future<void> openUtilityMenu(WidgetTester tester, String appName) async {
    await tester.tapAt(
      tester.getCenter(find.text(appName)),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utilities'));
    await tester.pumpAndSettle();
  }

  group('catalog wiring', () {
    test('offers every app-targeted command an Android device supports', () {
      final controller = createController();
      final ids = appUtilityCommandsFor(
        controller.session,
      ).map((command) => command.id);

      expect(ids, contains('grant-permission'));
      expect(ids, contains('package-info'));
      // Commands that don't take a package stay out of the app menu.
      expect(ids, isNot(contains('reboot')));
    });

    test('offers nothing on iOS, whose catalog has no app commands', () {
      final controller = createController(platform: DevicePlatform.ios);
      expect(hasAppUtilities(controller.session), isFalse);
    });

    test('only read-only commands may target a system app', () {
      final controller = createController();
      for (final command in appUtilityCommandsFor(controller.session)) {
        final allowed = command.allowsApp(isSystemApp: true);
        expect(
          allowed,
          command.id == 'package-info',
          reason: '${command.id} system-app allowance',
        );
      }
    });
  });

  group('context menu', () {
    testWidgets('running one pre-fills the package of the clicked app', (
      tester,
    ) async {
      useTallWindow(tester);
      final controller = createController();
      service.appsToReturn = const [
        AppInfo(packageName: 'com.example.alpha', appName: 'Alpha'),
      ];
      await tester.pumpWidget(host(controller));
      await controller.refresh();
      await tester.pumpAndSettle();

      await openUtilityMenu(tester, 'Alpha');
      await tester.tap(find.text('Grant permission…'));
      await tester.pumpAndSettle();

      // The params dialog opens with the package already filled in, so only
      // the permission is left to choose.
      expect(
        find.widgetWithText(TextField, 'com.example.alpha'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'android.permission.CAMERA'),
        'android.permission.CAMERA',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Run'));
      await tester.pumpAndSettle();

      expect(service.utilityRequests.single.arguments, [
        'shell',
        "pm grant 'com.example.alpha' 'android.permission.CAMERA'",
      ]);
    });

    testWidgets('a permission field suggests the common runtime permissions', (
      tester,
    ) async {
      useTallWindow(tester);
      final controller = createController();
      service.appsToReturn = const [
        AppInfo(packageName: 'com.example.alpha', appName: 'Alpha'),
      ];
      await tester.pumpWidget(host(controller));
      await controller.refresh();
      await tester.pumpAndSettle();

      await openUtilityMenu(tester, 'Alpha');
      await tester.tap(find.text('Grant permission…'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Suggestions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Microphone'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Run'));
      await tester.pumpAndSettle();

      expect(service.utilityRequests.single.arguments, [
        'shell',
        "pm grant 'com.example.alpha' 'android.permission.RECORD_AUDIO'",
      ]);
    });

    testWidgets('dangerous utilities are disabled for a system app', (
      tester,
    ) async {
      useTallWindow(tester);
      final controller = createController();
      service.appsToReturn = const [
        AppInfo(
          packageName: 'com.android.settings',
          appName: 'Settings',
          isSystemApp: true,
        ),
      ];
      controller.setShowSystemApps(true);
      await tester.pumpWidget(host(controller));
      await controller.refresh();
      await tester.pumpAndSettle();

      await openUtilityMenu(tester, 'Settings');

      // The read-only command stays available; the mutating ones are listed
      // but cannot be picked.
      expect(_menuItemEnabled(tester, 'Package details…'), isTrue);
      expect(_menuItemEnabled(tester, 'Grant permission…'), isFalse);
      expect(_menuItemEnabled(tester, 'Reset permissions…'), isFalse);
      expect(_menuItemEnabled(tester, 'Monkey stress test…'), isFalse);

      // Tapping a blocked entry does nothing at all.
      await tester.tap(find.text('Reset permissions…'));
      await tester.pumpAndSettle();
      expect(service.utilityRequests, isEmpty);
    });

    testWidgets('clear data and uninstall are disabled for a system app', (
      tester,
    ) async {
      useTallWindow(tester);
      final controller = createController();
      service.appsToReturn = const [
        AppInfo(
          packageName: 'com.android.settings',
          appName: 'Settings',
          isSystemApp: true,
        ),
      ];
      controller.setShowSystemApps(true);
      await tester.pumpWidget(host(controller));
      await controller.refresh();
      await tester.pumpAndSettle();

      await tester.tapAt(
        tester.getCenter(find.text('Settings')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(_menuItemEnabled(tester, 'Clear Data…'), isFalse);
      expect(_menuItemEnabled(tester, 'Uninstall…'), isFalse);
      // Reversible actions stay available.
      expect(_menuItemEnabled(tester, 'Force Stop'), isTrue);

      await tester.tap(find.text('Uninstall…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('permanently removes'), findsNothing);
    });

    testWidgets('a user app keeps every entry enabled', (tester) async {
      useTallWindow(tester);
      final controller = createController();
      service.appsToReturn = const [
        AppInfo(packageName: 'com.example.alpha', appName: 'Alpha'),
      ];
      await tester.pumpWidget(host(controller));
      await controller.refresh();
      await tester.pumpAndSettle();

      await tester.tapAt(
        tester.getCenter(find.text('Alpha')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(_menuItemEnabled(tester, 'Clear Data…'), isTrue);
      expect(_menuItemEnabled(tester, 'Uninstall…'), isTrue);
    });
  });
}

/// Whether the open popup menu's entry labelled [label] can be clicked.
///
/// Matched by predicate rather than [find.byType]: the two menus use
/// different value types, and `byType` compares the concrete generic type.
bool _menuItemEnabled(WidgetTester tester, String label) {
  final item =
      tester.widget(
            find.ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
            ),
          )
          as PopupMenuItem;
  return item.enabled;
}
