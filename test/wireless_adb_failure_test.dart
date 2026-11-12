import 'package:eagly/features/wireless_connection/data/wireless_adb_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const address = '192.168.1.37:41909';
  const noRoute = "failed to connect to '192.168.1.37:41909': No route to host";

  WirelessAdbFailure? diagnose(
    String error, {
    WirelessAdbAction action = WirelessAdbAction.connect,
    WirelessReachability reachability = WirelessReachability.unknown,
    bool isMacOS = true,
  }) => diagnoseWirelessAdbFailure(
    error: error,
    address: address,
    action: action,
    reachability: reachability,
    isMacOS: isMacOS,
  );

  test('adb blocked but Eagly gets through: blame the adb server', () {
    final failure = diagnose(
      noRoute,
      reachability: WirelessReachability.reachable,
    )!;

    expect(failure.kind, WirelessAdbFailureKind.adbServerBlocked);
    expect(failure.suggestsAdbRestart, isTrue);
    expect(failure.suggestsLocalNetworkSettings, isFalse);
    expect(failure.explanation, contains('Restart adb'));
    expect(failure.rawError, noRoute);
  });

  test('neither can reach it on macOS: same Wi-Fi or Local Network', () {
    final failure = diagnose(
      noRoute,
      reachability: WirelessReachability.unreachable,
    )!;

    expect(failure.kind, WirelessAdbFailureKind.networkUnreachable);
    expect(failure.explanation, contains('Local Network'));
    expect(failure.suggestsLocalNetworkSettings, isTrue);
    expect(failure.suggestsAdbRestart, isTrue);
  });

  test('off macOS the Local Network permission is never suggested', () {
    final failure = diagnose(
      noRoute,
      reachability: WirelessReachability.unreachable,
      isMacOS: false,
    )!;

    expect(failure.suggestsLocalNetworkSettings, isFalse);
    expect(failure.explanation, isNot(contains('Local Network')));
  });

  test('a refused port explains that the port changes', () {
    final failure = diagnose(
      "failed to connect to '192.168.1.37:41909': Connection refused",
    )!;

    expect(failure.kind, WirelessAdbFailureKind.portClosed);
    expect(failure.title, contains('41909'));
    expect(failure.explanation, contains('port changed'));
    expect(failure.suggestsAdbRestart, isFalse);
  });

  test('no route from adb but the port refuses Eagly: port closed', () {
    final failure = diagnose(
      noRoute,
      reachability: WirelessReachability.refused,
    )!;

    expect(failure.kind, WirelessAdbFailureKind.portClosed);
    expect(failure.rawError, noRoute);
  });

  test('a wrong pairing code', () {
    final failure = diagnose(
      'Failed: Wrong password or connection was dropped.',
      action: WirelessAdbAction.pair,
    )!;

    expect(failure.kind, WirelessAdbFailureKind.pairingRejected);
    expect(failure.explanation, contains('Pair device with pairing code'));
  });

  test('a time-out asks to wake the device and check the network', () {
    final failure = diagnose(
      "failed to connect to '192.168.1.37:41909': Operation timed out",
    )!;

    expect(failure.kind, WirelessAdbFailureKind.noAnswer);
  });

  test('output we do not recognise stays unexplained', () {
    expect(diagnose('error: something unexpected'), isNull);
  });

  test('only ambiguous errors ask for a reachability probe', () {
    expect(wirelessAdbErrorNeedsProbe(noRoute), isTrue);
    expect(
      wirelessAdbErrorNeedsProbe('Failed: Unable to start pairing client.'),
      isTrue,
    );
    expect(wirelessAdbErrorNeedsProbe('Connection refused'), isFalse);
    expect(wirelessAdbErrorNeedsProbe('Failed: Wrong password'), isFalse);
  });
}
