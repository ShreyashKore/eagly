import 'package:eagly/data/device.dart';
import 'package:eagly/features/wireless_connection/components/wireless_discovery_card.dart';
import 'package:eagly/features/wireless_connection/components/wireless_qr_panel.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/features/wireless_connection/wireless_connection_controller.dart';
import 'package:eagly/features/wireless_connection/wireless_connection_dialog.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdbTool adbTool;
  late FakeIdeviceIdTool ideviceIdTool;
  late FakeIdeviceInfoTool ideviceInfoTool;
  late DevicesRepository repository;
  DeviceSessionManager? manager;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() {
    // Keep the background mDNS scan idle: these tests are about the UI.
    WirelessConnectionController.scanInterval = const Duration(seconds: 30);
    adbTool = FakeAdbTool();
    ideviceIdTool = FakeIdeviceIdTool();
    ideviceInfoTool = FakeIdeviceInfoTool();
    repository = DevicesRepository.forTesting(
      adbTool: adbTool,
      ideviceIdTool: ideviceIdTool,
      ideviceInfoTool: ideviceInfoTool,
    );
  });

  tearDown(() async {
    manager?.dispose();
    manager = null;
    await adbTool.disposeTool();
    WirelessConnectionController.scanInterval = const Duration(
      milliseconds: 1200,
    );
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    Size windowSize = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = windowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    manager = DeviceSessionManager(
      repository: repository,
      serviceFactory: (device) => FakeSessionService(device),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: WirelessConnectionDialog(
            manager: manager!,
            onShowSnackBar: (_) {},
          ),
        ),
      ),
    );
  }

  /// Tears the dialog down inside the test body so the background scan's
  /// parked timer is drained before the pending-timer check runs.
  Future<void> closeDialog(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    repository.dispose();
    manager?.dispose();
    manager = null;
    await tester.pump(WirelessConnectionController.scanInterval);
    await tester.pump(const Duration(seconds: 10));
  }

  testWidgets('shows the QR code on the first frame', (tester) async {
    await pumpDialog(tester);

    // No pumpAndSettle: the code must be there before any discovery finishes.
    expect(find.byType(WirelessQrPanel), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Nearby devices'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('the QR code and the nearby list share one pane', (tester) async {
    adbTool.androidDevices = [
      Device('emulator-5554', 'device', platform: DevicePlatform.android),
    ];
    await pumpDialog(tester);
    await tester.pump();

    // One switch away from the pair pane, and it is not the QR code.
    expect(find.text('Pair a device'), findsOneWidget);
    expect(find.text('Manual entry'), findsWidgets);
    expect(find.text('QR code'), findsNothing);

    await tester.tap(find.text('Pair a device'));
    await tester.pump();
    expect(find.byType(QrImageView), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('discovered devices render under the QR code', (tester) async {
    adbTool.discoveryResult = WirelessServiceDiscoveryResult.success(
      services: const [
        WirelessDebugService(
          name: 'Pixel 9 pairing',
          type: WirelessDebugServiceType.pairing,
          host: '192.168.0.10',
          port: 37111,
        ),
        WirelessDebugService(
          name: 'Pixel 9 connect',
          type: WirelessDebugServiceType.connect,
          host: '192.168.0.10',
          port: 37112,
        ),
        WirelessDebugService(
          name: 'Tablet pairing',
          type: WirelessDebugServiceType.pairing,
          host: '192.168.0.24',
          port: 41000,
        ),
      ],
    );

    await pumpDialog(tester);
    await tester.pump();
    await tester.pump();

    expect(find.byType(WirelessDiscoveryCard), findsNWidgets(2));
    // The QR code keeps its place at the top of the same pane.
    expect(find.byType(QrImageView), findsOneWidget);

    await tester.tap(find.text('192.168.0.24'));
    await tester.pump();
    expect(find.text('Selected device'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('the pair pane scrolls as a whole in a tiny window', (
    tester,
  ) async {
    // The smallest window Eagly allows (see main.dart).
    await pumpDialog(tester, windowSize: const Size(560, 240));
    await tester.pump();

    expect(find.byType(QrImageView), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('hints stay hidden until waiting has gone on a while', (
    tester,
  ) async {
    await pumpDialog(tester);
    await tester.pump();

    expect(find.text('Nothing found yet'), findsNothing);
    expect(find.text('Still waiting?'), findsNothing);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Nothing found yet'), findsOneWidget);
    expect(find.text('Still waiting?'), findsOneWidget);

    await closeDialog(tester);
  });
}
