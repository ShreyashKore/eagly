import 'package:path_provider/path_provider.dart';

import '../../data/ios_device_info.dart';
import '../../features/app_log/app_logger.dart';
import '../../src/rust/api/ios.dart' as rust;
import 'ios_device_domains.dart';
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
  Set<String> _networkDeviceIds = const {};
  Future<void>? _wirelessDiscovery;

  @override
  bool get usbmuxdUnavailable => _usbmuxdUnavailable;

  @override
  Set<String> get networkDeviceIds => _networkDeviceIds;

  @override
  Future<List<String>> listDeviceIds() async {
    _wirelessDiscovery ??= _startWirelessDiscovery();
    try {
      final handles = await rust.listIosDevices();
      _usbmuxdUnavailable = false;
      _networkDeviceIds = {
        for (final handle in handles)
          if (handle.isNetwork) handle.udid,
      };
      return [for (final handle in handles) handle.udid];
    } on rust.IosError_UsbmuxdUnavailable {
      // usbmuxd being unreachable is a steady-state environment condition, not
      // a transient error, so latch it and log only on the way in — the poll
      // would otherwise repeat an identical warning every few seconds.
      _networkDeviceIds = const {};
      if (!_usbmuxdUnavailable) {
        _usbmuxdUnavailable = true;
        _logger.warning(
          'iOS device detection is unavailable: usbmuxd is not reachable.',
        );
      }
      return const [];
    } catch (error) {
      _networkDeviceIds = const {};
      _logger.error('Failed to list iOS devices', detail: error.toString());
      return const [];
    }
  }

  /// Has the Rust side watch the network for iPhones paired over Wi-Fi
  /// (`IosWirelessPairingController`), whose records live in the same
  /// application-support directory. Each one it reaches is listed from then
  /// on, flagged in [networkDeviceIds]. Started once, on the first poll.
  Future<void> _startWirelessDiscovery() async {
    try {
      final storageDir = (await getApplicationSupportDirectory()).path;
      await rust.startIosWirelessDiscovery(storageDir: storageDir);
    } catch (error) {
      _logger.warning(
        'Wireless iOS discovery is unavailable',
        detail: error.toString(),
      );
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

  @override
  Future<IosDeviceDomains> readDeviceDomains(String deviceId) async {
    try {
      final domains = await rust.readIosDeviceDomains(udid: deviceId);
      return IosDeviceDomains(
        root: domains.root,
        battery: domains.battery,
        diskUsage: domains.diskUsage,
        international: domains.international,
      );
    } catch (error) {
      _logger.error(
        'Failed to read iOS device domains for $deviceId',
        detail: error.toString(),
      );
      return const IosDeviceDomains();
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
