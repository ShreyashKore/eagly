import '../data/wireless_debug_models.dart';
import 'tools/adb_tool.dart';

class WirelessConnectionService {
  WirelessConnectionService({String? adbPath, AdbTool? adbTool})
    : _adbTool = adbTool ?? AdbTool(executablePath: adbPath);

  final AdbTool _adbTool;

  Future<DeviceCommandResult> pairDevice({
    required String address,
    required String pairingCode,
  }) {
    return _adbTool.pairDevice(address: address, pairingCode: pairingCode);
  }

  Future<DeviceCommandResult> connectDevice(String address) {
    return _adbTool.connectDevice(address);
  }
}
