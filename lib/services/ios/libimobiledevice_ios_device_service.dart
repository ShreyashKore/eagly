import '../../data/ios_device_info.dart';
import '../tools/idevice_id_tool.dart';
import '../tools/idevice_info_tool.dart';
import 'ios_device_domains.dart';
import 'ios_device_service.dart';

/// [IosDeviceService] backed by the bundled libimobiledevice CLIs. The default,
/// and the reference the Rust backend is compared against.
class LibimobiledeviceIosDeviceService({
  IdeviceIdTool? ideviceIdTool,
  IdeviceInfoTool? ideviceInfoTool,
}) implements IosDeviceService {
  this
    : _ideviceIdTool = ideviceIdTool ?? IdeviceIdTool(),
      _ideviceInfoTool = ideviceInfoTool ?? IdeviceInfoTool();

  final IdeviceIdTool _ideviceIdTool;
  final IdeviceInfoTool _ideviceInfoTool;

  @override
  Future<List<String>> listDeviceIds() => _ideviceIdTool.getDeviceIds();

  @override
  Future<IosDeviceInfo> describeDevice(String deviceId) =>
      _ideviceInfoTool.readDeviceInfo(deviceId);

  @override
  Future<IosDeviceDomains> readDeviceDomains(String deviceId) =>
      _ideviceInfoTool.readDeviceDomains(deviceId);

  @override
  bool get usbmuxdUnavailable => _ideviceIdTool.usbmuxdUnavailable;

  /// `idevice_id -l` lists USB devices only.
  @override
  Set<String> get networkDeviceIds => const {};
}
