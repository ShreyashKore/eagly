import '../data/wireless_debug_models.dart';
import 'tools/adb_tool.dart';

class WirelessConnectionService {
  final AdbTool _adbTool;
  static final WirelessConnectionService instance = WirelessConnectionService();

  WirelessConnectionService({
    String? adbPath,
    AdbTool? adbTool,
  }) : _adbTool = adbTool ?? AdbTool(executablePath: adbPath);

  Future<DeviceCommandResult> pairDevice({
    required String address,
    required String pairingCode,
  }) => _adbTool.pairDevice(address: address, pairingCode: pairingCode);

  Future<DeviceCommandResult> connectDevice(String address) =>
      _adbTool.connectDevice(address);
}