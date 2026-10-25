import 'dart:async';

import 'package:eagly/features/wireless_connection/components/ios_wireless_pair_panel.dart';
import 'package:eagly/features/wireless_connection/ios_wireless_pairing_controller.dart';
import 'package:eagly/features/wireless_connection/wireless_connection_controller.dart';
import 'package:eagly/features/wireless_connection/wireless_connection_dialog.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/services/ios/ios_wireless_service.dart';
import 'package:eagly/session/device_session_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdbTool adbTool;
  late DevicesRepository repository;
  late _FakeIosWirelessService service;
  late IosWirelessPairingController controller;

  setUp(() {
    // Keep the Android background mDNS scan idle; these tests are about iOS.
    WirelessConnectionController.scanInterval = const Duration(seconds: 30);
    adbTool = FakeAdbTool();
    repository = DevicesRepository.forTesting(
      adbTool: adbTool,
      iosDeviceService: FakeIosDeviceService(),
    );
    service = _FakeIosWirelessService();
    controller = IosWirelessPairingController(
      service: service,
      resolveStorageDir: () async => '/tmp/eagly-test',
      hostName: 'Test Mac',
    );
  });

  tearDown(() async {
    await adbTool.disposeTool();
    WirelessConnectionController.scanInterval = const Duration(
      milliseconds: 1200,
    );
  });

  Future<DeviceSessionManager> pumpDialog(WidgetTester tester) async {
    final manager = DeviceSessionManager(
      repository: repository,
      serviceFactory: (device) => FakeSessionService(device),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: WirelessConnectionDialog(
            manager: manager,
            onShowSnackBar: (_) {},
            iosPairingController: controller,
          ),
        ),
      ),
    );
    return manager;
  }

  Future<void> closeDialog(
    WidgetTester tester,
    DeviceSessionManager manager,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    repository.dispose();
    manager.dispose();
    await tester.pump(WirelessConnectionController.scanInterval);
    await tester.pump(const Duration(seconds: 10));
  }

  testWidgets('selecting iPhone advertises the host and shows the panel', (
    tester,
  ) async {
    final manager = await pumpDialog(tester);

    // The Android pane is the default.
    expect(find.byType(IosWirelessPairPanel), findsNothing);

    await tester.tap(find.text('iPhone'));
    await tester.pump();

    expect(find.byType(IosWirelessPairPanel), findsOneWidget);
    expect(find.text('Pair an iPhone over Wi-Fi'), findsOneWidget);
    expect(service.starts, hasLength(1));
    expect(service.starts.single.$1, 'Test Mac');

    await closeDialog(tester, manager);
  });

  testWidgets('the setup code renders once a device connects', (tester) async {
    final manager = await pumpDialog(tester);

    await tester.tap(find.text('iPhone'));
    await tester.pump();

    service.emit(const IosWirelessPairEvent(kind: 'listening'));
    await tester.pump();
    service.emit(const IosWirelessPairEvent(kind: 'pin', pin: '654321'));
    await tester.pump();

    expect(find.text('654321'), findsOneWidget);
    expect(find.text('Enter this code on the iPhone'), findsOneWidget);

    await closeDialog(tester, manager);
  });
}

class _FakeIosWirelessService implements IosWirelessService {
  final List<(String, String, String)> starts = [];
  var stopCalls = 0;
  StreamController<IosWirelessPairEvent>? _controller;

  @override
  IosWirelessPairSession startPairing({
    required String hostName,
    required String hostModel,
    required String storageDir,
  }) {
    starts.add((hostName, hostModel, storageDir));
    _controller = StreamController<IosWirelessPairEvent>();
    return IosWirelessPairSession(
      events: _controller!.stream,
      stop: () async {
        stopCalls++;
      },
    );
  }

  void emit(IosWirelessPairEvent event) => _controller!.add(event);
}
