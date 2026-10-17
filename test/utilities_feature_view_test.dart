import 'package:eagly/data/device.dart';
import 'package:eagly/features/utilities/components/utility_output_panel.dart';
import 'package:eagly/features/utilities/data/utility_command.dart';
import 'package:eagly/features/utilities/utilities_controller.dart';
import 'package:eagly/features/utilities/utilities_feature_view.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/services/tools/tool_process_runner.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSessionService service;
  DeviceSessionController? session;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  UtilitiesController createController({
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
    return session!.utilitiesController;
  }

  tearDown(() {
    session?.dispose();
    session = null;
  });

  Widget host(UtilitiesController controller) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: UtilitiesFeatureView(controller: controller, onClose: () {}),
      ),
    );
  }

  useTallWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('renders grouped commands for the device platform', (
    tester,
  ) async {
    useTallWindow(tester);
    await tester.pumpWidget(host(createController()));

    expect(find.text('Utilities'), findsOneWidget);
    expect(find.text('POWER & CONNECTION'), findsOneWidget);
    expect(find.text('Reboot device'), findsOneWidget);
    // iOS-only commands stay hidden on an Android device.
    expect(find.text('Unpair device'), findsNothing);
  });

  testWidgets('tapping a command runs it and shows its output', (tester) async {
    useTallWindow(tester);
    final controller = createController();
    service.utilityResult = const ToolCommandResult(
      exitCode: 0,
      stdout: '  Physical size: 1080x2400',
      stderr: '',
    );
    await tester.pumpWidget(host(controller));

    await tester.tap(find.text('Screen size & density'));
    await tester.pumpAndSettle();

    expect(service.utilityRequests.single.arguments, [
      'shell',
      'wm size; wm density',
    ]);
    expect(find.byType(UtilityOutputPanel), findsOneWidget);
    expect(find.textContaining('Physical size: 1080x2400'), findsOneWidget);
  });

  testWidgets('a parameterised command collects input before running', (
    tester,
  ) async {
    useTallWindow(tester);
    final controller = createController();
    await tester.pumpWidget(host(controller));

    await tester.ensureVisible(find.text('Open URL or deep link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open URL or deep link'));
    await tester.pumpAndSettle();

    // Nothing runs until the dialog is filled in and submitted.
    expect(service.utilityRequests, isEmpty);
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      'myapp://home',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Run'));
    await tester.pumpAndSettle();

    expect(service.utilityRequests.single.arguments, [
      'shell',
      "am start -a android.intent.action.VIEW -d 'myapp://home'",
    ]);
  });

  testWidgets('a destructive command asks for confirmation first', (
    tester,
  ) async {
    useTallWindow(tester);
    final controller = createController();
    await tester.pumpWidget(host(controller));

    await tester.tap(find.text('Reboot device'));
    await tester.pumpAndSettle();

    expect(find.text('Reboot device?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(service.utilityRequests, isEmpty);

    await tester.tap(find.text('Reboot device'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reboot device'));
    await tester.pumpAndSettle();

    expect(service.utilityRequests.single.arguments, ['reboot']);
  });

  testWidgets('an iOS device runs the libimobiledevice equivalent', (
    tester,
  ) async {
    useTallWindow(tester);
    final controller = createController(platform: DevicePlatform.ios);
    service.utilityResult = const ToolCommandResult(
      exitCode: 0,
      stdout: 'CurrentCapacity: 87',
      stderr: '',
    );
    await tester.pumpWidget(host(controller));

    // Android-only commands are gone; the shared ones stay.
    expect(find.text('Type text'), findsNothing);
    await tester.tap(find.text('Battery status'));
    await tester.pumpAndSettle();

    expect(service.utilityRequests.single.tool, UtilityTool.idevicediagnostics);
    expect(service.utilityRequests.single.arguments, [
      'diagnostics',
      'GasGauge',
    ]);
    expect(find.textContaining('CurrentCapacity: 87'), findsOneWidget);
  });

  testWidgets('search filters the list', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(host(createController()));

    await tester.enterText(find.byType(TextField).first, 'monkey');
    await tester.pumpAndSettle();

    expect(find.text('Monkey stress test'), findsOneWidget);
    expect(find.text('Reboot device'), findsNothing);
  });
}
