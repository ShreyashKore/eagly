import 'dart:io';

import '../../data/ios_device_info.dart';
import '../ios/ios_device_domains.dart';
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

  /// The lockdownd domains behind the device home screen, sourced entirely
  /// from `ideviceinfo` — the only libimobiledevice CLI bundled on every
  /// platform (macOS ships a curated subset that excludes
  /// `idevicediagnostics`/`idevicepair`).
  ///
  /// One process per domain: `ideviceinfo` takes a single `-q`, so this is four
  /// process starts, four connects and four TLS handshakes. The Rust backend
  /// reads all four over one lockdown session.
  Future<IosDeviceDomains> readDeviceDomains(String deviceId) async {
    try {
      final results = await Future.wait([
        runText(['-u', deviceId]),
        runText(['-u', deviceId, '-q', 'com.apple.mobile.battery']),
        runText(['-u', deviceId, '-q', 'com.apple.disk_usage']),
        runText(['-u', deviceId, '-q', 'com.apple.international']),
      ]);

      return IosDeviceDomains(
        root: _parseInfoOutput(results[0].stdout),
        battery: _parseInfoOutput(results[1].stdout),
        diskUsage: _parseInfoOutput(results[2].stdout),
        international: _parseInfoOutput(results[3].stdout),
      );
    } on ProcessException catch (error) {
      logError('ProcessException reading iOS domains for $deviceId', error);
      return const IosDeviceDomains();
    } catch (error) {
      logError('Unexpected error reading iOS domains for $deviceId', error);
      return const IosDeviceDomains();
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
