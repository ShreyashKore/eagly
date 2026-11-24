import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/ios.dart' as rust;
import 'ios_backend.dart';

/// Why removing an iPhone's connection to this computer failed, in a sentence
/// the UI can show as is.
class IosDeviceTrustException implements Exception {
  const IosDeviceTrustException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What [IosDeviceTrustService.stopWifiConnections] achieved.
enum IosWifiStopOutcome {
  /// The iPhone reports its Wi-Fi connections off.
  off,

  /// The change was sent, but the iPhone went away before it could be asked
  /// whether it took. The change itself can cause that.
  unconfirmed,

  /// Only an Eagly wireless pairing was dropped; the iPhone was out of reach,
  /// so its own Wi-Fi settings are as they were.
  pairingOnly,
}

/// Undoes the trust that lets an iPhone reconnect to this computer on its own.
///
/// An iPhone someone plugged in once and tapped "Trust" on keeps a pairing
/// with this computer, and with Wi-Fi connections switched on (Xcode's
/// "Connect via network", Finder's "Show this iPhone when on Wi-Fi") usbmuxd
/// connects to it whenever it is on the same network. An Eagly wireless
/// pairing reconnects the same way. Rust-only: the bundled CLIs could unpair,
/// but not drop an Eagly tunnel.
abstract interface class IosDeviceTrustService {
  /// Stops [udid] connecting over Wi-Fi while keeping its USB trust. Switches
  /// the device's Wi-Fi connections off — for every computer, since the
  /// switch lives on the device — and drops an Eagly wireless pairing.
  Future<IosWifiStopOutcome> stopWifiConnections(String udid);

  /// Removes [udid]'s pairing with this computer. It connects again only
  /// after someone plugs it in and taps "Trust". Xcode and Finder share the
  /// pairing, so they lose the device too.
  Future<void> forget(String udid);
}

IosDeviceTrustService createIosDeviceTrustService() =>
    RustIosDeviceTrustService();

/// Whether [IosDeviceTrustService] can be offered: only the Rust backend
/// implements it.
bool get iosDeviceTrustAvailable => useRustIosBackend;

class RustIosDeviceTrustService implements IosDeviceTrustService {
  RustIosDeviceTrustService({Future<String> Function()? resolveStorageDir})
    : _resolveStorageDir = resolveStorageDir ?? _applicationSupportDir;

  /// Where Eagly's wireless pairing records live; see
  /// `IosWirelessPairingController`.
  final Future<String> Function() _resolveStorageDir;

  static Future<String> _applicationSupportDir() async =>
      (await getApplicationSupportDirectory()).path;

  @override
  Future<IosWifiStopOutcome> stopWifiConnections(String udid) => _guard(
    () async => switch (await rust.stopIosWifiConnections(
      udid: udid,
      storageDir: await _resolveStorageDir(),
    )) {
      rust.IosWifiStop.off => IosWifiStopOutcome.off,
      rust.IosWifiStop.unconfirmed => IosWifiStopOutcome.unconfirmed,
      rust.IosWifiStop.pairingOnly => IosWifiStopOutcome.pairingOnly,
    },
  );

  @override
  Future<void> forget(String udid) => _guard(
    () async => rust.forgetIosDevice(
      udid: udid,
      storageDir: await _resolveStorageDir(),
    ),
  );

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on IosDeviceTrustException {
      rethrow;
    } catch (error) {
      throw IosDeviceTrustException(_describe(error));
    }
  }
}

/// A sentence for an error crossing the bridge.
String _describe(Object error) => switch (error) {
  rust.IosError_UsbmuxdUnavailable() => 'usbmuxd is not reachable.',
  rust.IosError_DeviceNotFound() =>
    'The iPhone is out of reach. Unlock it on the same Wi-Fi, or plug it in, '
        'and try again.',
  rust.IosError_Locked() => 'Unlock the iPhone and try again.',
  rust.IosError_NotPaired(:final field0) ||
  rust.IosError_PairingDialogPending(:final field0) ||
  rust.IosError_Other(:final field0) => field0,
  AnyhowException(:final message) => message,
  _ => error.toString(),
};
