import 'dart:io';

import 'ios_backend.dart';
import 'rust_ios_wireless_service.dart';

/// Folder under the storage dir holding one record per iPhone paired over
/// Wi-Fi. Must match `DEVICE_RECORDS_DIR` in `rust/src/ios_wireless.rs`.
const iosWirelessDeviceRecordsDir = 'remote_pairing_devices';

/// Whether any iPhone has been paired over Wi-Fi with records kept under
/// `storageDir`. A cheap directory read, safe to call on every poll.
Future<bool> hasIosWirelessPairings(String storageDir) async {
  final dir = Directory(
    '$storageDir${Platform.pathSeparator}$iosWirelessDeviceRecordsDir',
  );
  try {
    if (!await dir.exists()) return false;
    return await dir.list().any(
      (entry) => entry is File && entry.path.endsWith('.plist'),
    );
  } on FileSystemException {
    return false;
  }
}

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

/// Whether iPhone wireless pairing can be offered. It needs the Rust
/// backend twice over: pairing runs in Rust, and only
/// `RustIosDeviceService` watches for paired iPhones afterwards. Under
/// `EAGLY_IOS_BACKEND=cli`, or when the Rust library failed to load, a
/// pairing would either throw or produce a phone that never appears.
bool get iosWirelessPairingAvailable => useRustIosBackend;
