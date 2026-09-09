import '../../data/ios_device_info.dart';
import '../../features/app_log/app_logger.dart';
import '../../src/rust/api/ios.dart' as rust;
import 'ios_device_service.dart';

/// [IosDeviceService] backed by the `idevice` Rust crate, which talks to
/// usbmuxd and lockdownd directly instead of spawning CLI processes.
///
/// This is the only place in the app that touches `lib/src/rust`. Everything
/// above it sees [IosDeviceInfo], so the generated bindings stay an
/// implementation detail of this one backend.
class RustIosDeviceService implements IosDeviceService {
  final AppLogger _logger = AppLogger(source: 'RustIosDeviceService');

  bool _usbmuxdUnavailable = false;

  @override
  bool get usbmuxdUnavailable => _usbmuxdUnavailable;

  @override
  Future<List<String>> listDeviceIds() async {
    try {
      final handles = await rust.listIosDevices();
      _usbmuxdUnavailable = false;
      return [for (final handle in handles) handle.udid];
    } on rust.IosError_UsbmuxdUnavailable {
      // usbmuxd being unreachable is a steady-state environment condition, not
      // a transient error, so latch it and log only on the way in — the poll
      // would otherwise repeat an identical warning every few seconds.
      if (!_usbmuxdUnavailable) {
        _usbmuxdUnavailable = true;
        _logger.warning(
          'iOS device detection is unavailable: usbmuxd is not reachable.',
        );
      }
      return const [];
    } catch (error) {
      _logger.error('Failed to list iOS devices', detail: error.toString());
      return const [];
    }
  }

  @override
  Future<IosDeviceInfo> describeDevice(String deviceId) async {
    try {
      return _toDeviceInfo(await rust.describeIosDevice(udid: deviceId));
    } catch (error) {
      _logger.error(
        'Failed to describe iOS device $deviceId',
        detail: error.toString(),
      );
      return IosDeviceInfo(deviceId: deviceId, status: 'unavailable');
    }
  }

  /// `productVersion` is deliberately dropped: discovery does not render it,
  /// and the extended device-info screen has its own model.
  IosDeviceInfo _toDeviceInfo(rust.IosDeviceSummary summary) {
    return IosDeviceInfo(
      deviceId: summary.udid,
      status: summary.status,
      deviceName: summary.name,
      productName: summary.productName,
      hardwareModel: summary.hardwareModel,
      productType: summary.productType,
    );
  }
}
