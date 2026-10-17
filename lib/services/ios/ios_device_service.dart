import '../../data/ios_device_info.dart';
import 'ios_backend.dart';
import 'ios_device_domains.dart';
import 'libimobiledevice_ios_device_service.dart';
import 'rust_ios_device_service.dart';

/// iOS device discovery, abstracted over the two backends that can provide it.
///
/// Eagly is migrating from the bundled libimobiledevice CLIs to the `idevice`
/// Rust crate (see `docs/IOS_RUST_MIGRATION.md`). Both implementations are kept
/// side by side during the migration so a surface can be moved one at a time
/// and compared against the known-good path on real hardware.
///
/// The two methods mirror the tools they replace — `idevice_id -l` and
/// `ideviceinfo -u <udid>` — because that split is load-bearing: listing is
/// cheap and runs on every poll, while describing opens a lockdown session and
/// is cached per device by [DevicesRepository].
abstract interface class IosDeviceService {
  /// UDIDs of every attached device. Empty when none are attached *or* when
  /// iOS support is unavailable — check [usbmuxdUnavailable] to tell them apart.
  Future<List<String>> listDeviceIds();

  /// Everything lockdownd will say about one device.
  ///
  /// Never throws for device-level conditions: a locked or unpaired device
  /// comes back with a [IosDeviceInfo.status] explaining why and no other
  /// fields, so one bad device cannot empty the list.
  Future<IosDeviceInfo> describeDevice(String deviceId);

  /// The lockdownd domains behind the device-home screen.
  ///
  /// Returns empty domains rather than throwing: the screen renders whatever it
  /// gets, and a device that locks mid-session should blank fields, not error.
  Future<IosDeviceDomains> readDeviceDomains(String deviceId);

  /// Whether the last [listDeviceIds] failed because usbmuxd was unreachable.
  ///
  /// On Windows usbmuxd ships with Apple Mobile Device Support rather than with
  /// eagly, so this drives the "install Apple Devices" hint. Latched: it stays
  /// true until a later call succeeds.
  bool get usbmuxdUnavailable;
}

IosDeviceService createIosDeviceService() {
  return useRustIosBackend
      ? RustIosDeviceService()
      : LibimobiledeviceIosDeviceService();
}
