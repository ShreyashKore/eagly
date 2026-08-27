import 'package:eagly/data/device.dart';
import 'package:eagly/features/logs/presentation/components/toolbar.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

/// The logs toolbar carries the most buttons of any pane, so it is the one
/// that has to survive a narrow pane without overflowing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  Future<DeviceSessionController> pumpToolbar(
    WidgetTester tester,
    double width,
  ) async {
    final device = Device(
      'emulator-5554',
      'device',
      platform: DevicePlatform.android,
    );
    final session = DeviceSessionController(
      device: device,
      service: FakeSessionService(device),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: Toolbar(
                controller: session.logSessionManager.selectedTab!,
                logManager: session.logSessionManager,
                onImportLog: () {},
                onExport: () {},
                onCopyAll: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    return session;
  }

  testWidgets('keeps every action visible in a wide pane', (tester) async {
    await pumpToolbar(tester, 1200);

    expect(find.byIcon(Icons.more_horiz).hitTestable(), findsNothing);
    expect(find.byIcon(Icons.download_outlined).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapses into the overflow menu in a narrow pane', (
    tester,
  ) async {
    await pumpToolbar(tester, 360);
    expect(tester.takeException(), isNull);

    // Capture controls, the tab strip and close stay put.
    expect(find.byIcon(Icons.close).hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow).hitTestable(), findsOneWidget);
    // Import — the last action — moved into the menu.
    expect(find.byIcon(Icons.download_outlined).hitTestable(), findsNothing);

    await tester.tap(find.byIcon(Icons.more_horiz).hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Import log file'), findsOneWidget);
  });
}
