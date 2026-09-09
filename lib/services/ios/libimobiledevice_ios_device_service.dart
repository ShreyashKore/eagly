import '../../data/ios_device_info.dart';
import '../tools/idevice_id_tool.dart';
import '../tools/idevice_info_tool.dart';
import 'ios_device_service.dart';

/// [IosDeviceService] backed by the bundled libimobiledevice CLIs. The default,
/// and the reference the Rust backend is compared against.
class LibimobiledeviceIosDeviceService implements IosDeviceService {
  LibimobiledeviceIosDeviceService({
    IdeviceIdTool? ideviceIdTool,
    IdeviceInfoTool? ideviceInfoTool,
  }) : _ideviceIdTool = ideviceIdTool ?? IdeviceIdTool(),
       _ideviceInfoTool = ideviceInfoTool ?? IdeviceInfoTool();

  final IdeviceIdTool _ideviceIdTool;
  final IdeviceInfoTool _ideviceInfoTool;

  @override
  Future<List<String>> listDeviceIds() => _ideviceIdTool.getDeviceIds();

  @override
  Future<IosDeviceInfo> describeDevice(String deviceId) =>
      _ideviceInfoTool.readDeviceInfo(deviceId);

  @override
  bool get usbmuxdUnavailable => _ideviceIdTool.usbmuxdUnavailable;
}
