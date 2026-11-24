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

  for (final (outcome, message) in [
    (IosWifiStopOutcome.off, 'QA iPhone no longer connects over Wi-Fi.'),
    (
      IosWifiStopOutcome.unconfirmed,
      'Told QA iPhone to stop connecting over Wi-Fi, but lost it before it '
          'could confirm. If it comes back over Wi-Fi, try again.',
    ),
    (
      IosWifiStopOutcome.pairingOnly,
      'Removed Eagly’s Wi-Fi pairing with QA iPhone. Its own Wi-Fi settings '
          'are unchanged; plug it in and try again to switch them off.',
    ),
  ]) {
    testWidgets('stop Wi-Fi says what happened: ${outcome.name}', (
      tester,
    ) async {
      service.outcome = outcome;
      await run(tester, IosTrustAction.stopWifi);
      await tester.tap(find.widgetWithText(FilledButton, 'Stop Wi-Fi'));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(refreshes, 1);
    });
  }

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
  var outcome = IosWifiStopOutcome.off;

  @override
  Future<IosWifiStopOutcome> stopWifiConnections(String udid) async {
    calls.add('stopWifi $udid');
    if (error case final error?) throw error;
    return outcome;
  }

  @override
  Future<void> forget(String udid) async {
    calls.add('forget $udid');
    if (error case final error?) throw error;
  }
}
