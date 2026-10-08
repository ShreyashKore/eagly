import 'dart:async';

import '../../src/rust/api/ios.dart' as rust;
import 'ios_wireless_service.dart';

/// [IosWirelessService] backed by the `idevice` crate's remote-pairing responder.
///
/// The Rust side binds a TCP listener, advertises `_remotepairing-pairable-host`
/// over mDNS, and runs the rppairing conversation when a device connects. Dart
/// sees it as a plain event stream, with a session id for cancellation — the
/// same shape as the syslog relay.
class RustIosWirelessService implements IosWirelessService {
  static int _nextSessionId = 0;

  @override
  IosWirelessPairSession startPairing({
    required String hostName,
    required String hostModel,
    required String storageDir,
  }) {
    final sessionId = 'ios-pair-${_nextSessionId++}';
    var stopped = false;

    Future<void> stop() async {
      if (stopped) return;
      stopped = true;
      // Cancelling a Dart subscription does not reach the Rust task, so the
      // advertised host and its listener would linger without this.
      await rust.stopIosWirelessPairing(sessionId: sessionId);
    }

    final events = rust
        .startIosWirelessPairing(
          hostName: hostName,
          hostModel: hostModel,
          port: 0,
          storageDir: storageDir,
          sessionId: sessionId,
        )
        .map(_toEvent);

    return IosWirelessPairSession(events: events, stop: stop);
  }

  IosWirelessPairEvent _toEvent(rust.IosWirelessPairEvent event) {
    return IosWirelessPairEvent(
      kind: event.kind,
      pin: event.pin,
      deviceName: event.deviceName,
      deviceModel: event.deviceModel,
      deviceUdid: event.deviceUdid,
      message: event.message,
    );
  }
}
