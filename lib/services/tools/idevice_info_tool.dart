import 'dart:io';

import '../../data/ios_device_info.dart';
import 'tool_process_runner.dart';

class IdeviceInfoTool extends ToolProcessRunner {
  IdeviceInfoTool({super.executablePath})
    : super(executableName: 'ideviceinfo');

  Future<IosDeviceInfo> readDeviceInfo(String deviceId) async {
    try {
      final result = await runText(['-u', deviceId]);
      if (!result.isSuccess) {
        logError(
          'ideviceinfo returned non-zero exit for $deviceId',
          result.combinedOutput,
        );
        return IosDeviceInfo(
          deviceId: deviceId,
          status: _describeDeviceStatus(result),
        );
      }

      final info = _parseInfoOutput(result.stdout);
      return IosDeviceInfo(
        deviceId: deviceId,
        status: 'device',
        deviceName: info['DeviceName'],
        productName: info['ProductName'],
        hardwareModel: info['HardwareModel'],
        productType: info['ProductType'],
      );
    } on ProcessException catch (error) {
      logError('ProcessException describing iOS device $deviceId', error);
      return IosDeviceInfo(deviceId: deviceId, status: 'unavailable');
    } catch (error) {
      logError('Unexpected error describing iOS device $deviceId', error);
      return IosDeviceInfo(deviceId: deviceId, status: 'unavailable');
    }
  }

  Map<String, String> _parseInfoOutput(String stdout) {
    final info = <String, String>{};
    for (final line in stdout.split('\n')) {
      final separatorIndex = line.indexOf(':');
      if (separatorIndex <= 0) continue;
      final key = line.substring(0, separatorIndex).trim();
      final value = line.substring(separatorIndex + 1).trim();
      if (key.isEmpty || value.isEmpty) continue;
      info[key] = value;
    }
    return info;
  }

  String _describeDeviceStatus(ToolCommandResult result) {
    final output = result.combinedOutput.toLowerCase();
    if (output.contains('not paired') || output.contains('pair')) {
      return 'unpaired';
    }
    if (output.contains('locked') || output.contains('passcode')) {
      return 'locked';
    }
    if (output.contains('no device') || output.contains('not found')) {
      return 'offline';
    }
    return 'unavailable';
  }
}
