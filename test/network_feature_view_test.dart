import 'package:eagly/data/device.dart';
import 'package:eagly/features/network/data/network_transaction.dart';
import 'package:eagly/features/network/network_controller.dart';
import 'package:eagly/features/network/network_feature_view.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/network_test_support.dart';
import 'support/session_test_support.dart';

void main() {
  late DeviceSessionController session;
  late NetworkController controller;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() {
    NetworkController.notifyInterval = Duration.zero;
    final device = Device(
      'emulator-5554',
      'device',
      platform: DevicePlatform.android,
      model: 'Pixel 8',
    );
    session = DeviceSessionController(
      device: device,
      service: FakeSessionService(device),
    );
    controller = session.networkController;
  });

  tearDown(() {
    NetworkController.notifyInterval = const Duration(milliseconds: 100);
  });

  Future<void> pumpView(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NetworkFeatureView(controller: controller, onClose: () {}),
        ),
      ),
    );
  }

  testWidgets('explains the empty pane and offers a HAR file', (tester) async {
    await pumpView(tester);

    expect(find.text('No network traffic yet'), findsOneWidget);
    expect(find.text('Open HAR file'), findsOneWidget);

    session.dispose();
  });

  testWidgets('lists exchanges and opens one in detail', (tester) async {
    await pumpView(tester);
    final source = FakeNetworkSource();
    controller.attach(source);
    source
      ..upsert(networkTransaction('1'))
      ..upsert(networkTransaction('2', code: 404))
      ..upsert(networkTransaction('3', state: NetworkTransactionState.pending));
    await tester.pump();
    await tester.pump();

    expect(find.text('/items/1'), findsOneWidget);
    expect(find.text('404'), findsOneWidget);
    expect(find.text('…'), findsOneWidget);
    expect(find.text('3 requests'), findsOneWidget);

    await tester.tap(find.text('/items/1'));
    await tester.pump();
    // The body fetch completes on the next microtask turn.
    await tester.pump();

    expect(find.text('https://api.example.com/items/1'), findsOneWidget);
    expect(find.text('Response body'), findsOneWidget);
    expect(find.text('body of 1'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Back to list'));
    await tester.pump();
    expect(find.text('/items/2'), findsOneWidget);

    // Unmount before disposing, so no pending fetch outlives the test body.
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
