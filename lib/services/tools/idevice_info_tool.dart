import 'dart:io';

import '../../data/device.dart';
import '../../data/ios_device_info.dart';
import '../../features/device_home/data/device_info.dart';
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

  /// Broader device info for the device home screen, sourced entirely from
  /// `ideviceinfo` domain queries — the only libimobiledevice CLI bundled on
  /// every platform (macOS ships a curated subset that excludes
  /// `idevicediagnostics`/`idevicepair`). Display, Wi-Fi/Bluetooth state and
  /// cellular carrier details aren't exposed by lockdownd, so those fields
  /// stay null on iOS rather than guessing.
  Future<DeviceInfo> fetchExtendedInfo(IosDevice device) async {
    final deviceId = device.id;
    try {
      final results = await Future.wait([
        runText(['-u', deviceId]),
        runText(['-u', deviceId, '-q', 'com.apple.mobile.battery']),
        runText(['-u', deviceId, '-q', 'com.apple.disk_usage']),
        runText(['-u', deviceId, '-q', 'com.apple.international']),
      ]);

      final defaultInfo = _parseInfoOutput(results[0].stdout);
      final batteryInfo = _parseInfoOutput(results[1].stdout);
      final diskInfo = _parseInfoOutput(results[2].stdout);
      final intlInfo = _parseInfoOutput(results[3].stdout);

      return DeviceInfo(
        identity: DeviceIdentityInfo(
          deviceName: device.name ?? defaultInfo['DeviceName'],
          manufacturer: 'Apple',
          model: device.model,
          osName: 'iOS',
          osVersion: defaultInfo['ProductVersion'],
          buildVersion: defaultInfo['BuildVersion'],
          serialNumber: defaultInfo['SerialNumber'],
          cpuArchitecture: defaultInfo['CPUArchitecture'],
        ),
        battery: _parseIosBattery(batteryInfo),
        storage: _parseIosStorage(diskInfo),
        // iOS devices in this app are only ever seen over USB (no wireless
        // idevice support), so this is a known constant, not a guess.
        connectivity: const DeviceConnectivityInfo(usbConnected: true),
        cellular: DeviceCellularInfo(simState: defaultInfo['SIMStatus']),
        developerState: DeviceDeveloperStateInfo(
          debuggingReady: device.status == 'device',
          pairingState: _pairingState(device.status),
        ),
        software: DeviceSoftwareInfo(
          locale: intlInfo['Locale'],
          timeZone: defaultInfo['TimeZone'] ?? intlInfo['TimeZone'],
        ),
      );
    } on ProcessException catch (error) {
      logError(
        'ProcessException fetching iOS device info for $deviceId',
        error,
      );
      return const DeviceInfo();
    } catch (error) {
      logError(
        'Unexpected error fetching iOS device info for $deviceId',
        error,
      );
      return const DeviceInfo();
    }
  }

  DeviceBatteryInfo _parseIosBattery(Map<String, String> values) {
    final percentage = int.tryParse(values['BatteryCurrentCapacity'] ?? '');
    BatteryChargingState? state;
    if (values.containsKey('BatteryIsCharging')) {
      state = values['BatteryIsFullyCharged'] == 'true'
          ? BatteryChargingState.full
          : (values['BatteryIsCharging'] == 'true'
                ? BatteryChargingState.charging
                : BatteryChargingState.discharging);
    }
    return DeviceBatteryInfo(percentage: percentage, chargingState: state);
  }

  DeviceStorageInfo _parseIosStorage(Map<String, String> values) {
    final total = int.tryParse(
      values['TotalDiskCapacity'] ?? values['TotalDataCapacity'] ?? '',
    );
    if (total == null) return const DeviceStorageInfo();
    final available = int.tryParse(
      values['TotalDataAvailable'] ?? values['TotalSystemAvailable'] ?? '',
    );
    return DeviceStorageInfo(
      totalBytes: total,
      availableBytes: available,
      usedBytes: available != null ? total - available : null,
    );
  }

  /// Maps the same status values produced by [readDeviceInfo] (and mirrored
  /// onto `Device.status` for connected iOS devices) into a human-readable
  /// pairing/trust label.
  String? _pairingState(String status) {
    return switch (status) {
      'device' => 'Paired',
      'unpaired' => 'Not Paired',
      'locked' => 'Locked (enter passcode)',
      'offline' => 'Unavailable',
      _ => null,
    };
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
