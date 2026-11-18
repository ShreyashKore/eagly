import 'package:eagly/data/device.dart';
import 'package:eagly/presentation/components/ios_device_trust_actions.dart';
import 'package:eagly/services/ios/ios_device_trust_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeTrustService service;
  late int refreshes;
  final device = Device.ios(
    '00008101-0000000000000000',
    'device',
    name: 'QA iPhone',
    isWireless: true,
  );

  setUp(() {
    service = _FakeTrustService();
    refreshes = 0;
  });

  Future<void> run(WidgetTester tester, IosTrustAction action) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmIosTrustAction(
                context,
                device: device,
                action: action,
                service: service,
                refreshDevices: () async => refreshes++,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('cancelling leaves the iPhone alone', (tester) async {
    await run(tester, IosTrustAction.forget);
    expect(find.text('Forget QA iPhone?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(service.calls, isEmpty);
    expect(refreshes, 0);
  });

  testWidgets('forget runs once confirmed and refreshes devices', (
    tester,
  ) async {
    await run(tester, IosTrustAction.forget);
    await tester.tap(find.widgetWithText(FilledButton, 'Forget'));
    await tester.pumpAndSettle();

    expect(service.calls, ['forget ${device.id}']);
    expect(refreshes, 1);
    expect(
      find.text('Forgot QA iPhone. It needs Trust over USB to connect again.'),
      findsOneWidget,
    );
  });

  testWidgets('stop Wi-Fi reports a failure in the snackbar', (tester) async {
    service.error = const IosDeviceTrustException('Unlock the iPhone.');
    await run(tester, IosTrustAction.stopWifi);
    await tester.tap(find.widgetWithText(FilledButton, 'Stop Wi-Fi'));
    await tester.pumpAndSettle();

    expect(service.calls, ['stopWifi ${device.id}']);
    expect(
      find.text('Could not stop Wi-Fi connections: Unlock the iPhone.'),
      findsOneWidget,
    );
    expect(refreshes, 1);
  });
}

class _FakeTrustService implements IosDeviceTrustService {
  final calls = <String>[];
  IosDeviceTrustException? error;

  @override
  Future<void> stopWifiConnections(String udid) async {
    calls.add('stopWifi $udid');
    if (error case final error?) throw error;
  }

  @override
  Future<void> forget(String udid) async {
    calls.add('forget $udid');
    if (error case final error?) throw error;
  }
}
