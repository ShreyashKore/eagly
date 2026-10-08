import 'rust_ios_wireless_service.dart';

/// One progress event from an in-flight iOS wireless (remote) pairing.
class IosWirelessPairEvent {
  const IosWirelessPairEvent({
    required this.kind,
    this.pin,
    this.deviceName,
    this.deviceModel,
    this.deviceUdid,
    this.message,
  });

  /// `'listening'`, `'pin'`, `'paired'` or `'error'`.
  final String kind;

  /// The 6-digit setup code to show the user, present on `'pin'`.
  final String? pin;
  final String? deviceName;
  final String? deviceModel;
  final String? deviceUdid;
  final String? message;

  bool get isListening => kind == 'listening';
  bool get isPin => kind == 'pin';
  bool get isPaired => kind == 'paired';
  bool get isError => kind == 'error';
}

/// A live wireless pairing: the event stream plus its teardown.
class IosWirelessPairSession {
  const IosWirelessPairSession({required this.events, required this.stop});

  final Stream<IosWirelessPairEvent> events;
  final Future<void> Function() stop;
}

/// iOS remote pairing over Wi-Fi, backed solely by the `idevice` Rust crate.
///
/// Unlike the other iOS surfaces there is no libimobiledevice equivalent to fall
/// back to — the bundled CLIs do not speak rppairing — so this surface is
/// Rust-only from the start.
abstract interface class IosWirelessService {
  /// Starts the "pairable host" flow and returns its event stream.
  ///
  /// `hostName`/`hostModel` are what the device shows while pairing. Each call
  /// is an independent advertising session.
  IosWirelessPairSession startPairing({
    required String hostName,
    required String hostModel,
    required String storageDir,
  });
}

IosWirelessService createIosWirelessService() => RustIosWirelessService();
