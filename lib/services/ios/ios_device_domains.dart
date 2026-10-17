import '../../data/device.dart';
import '../../features/device_home/data/device_info.dart';

/// The lockdownd domains the device-home screen reads, flattened to the text
/// form `ideviceinfo` prints (integers as decimals, booleans as `true`/`false`).
///
/// Both [IosDeviceService] backends produce this shape so the mapping below is
/// written once: the libimobiledevice backend parses `key: value` stdout into
/// it, and the Rust backend flattens the plist dictionaries into it.
class const IosDeviceDomains({
  this.root = const {},
  this.battery = const {},
  this.diskUsage = const {},
  this.international = const {},
}) {
  /// DeviceName, ProductVersion, BuildVersion, SerialNumber, CPUArchitecture,
  /// SIMStatus, TimeZone.
  final Map<String, String> root;

  /// `com.apple.mobile.battery`.
  final Map<String, String> battery;

  /// `com.apple.disk_usage`.
  final Map<String, String> diskUsage;

  /// `com.apple.international`.
  final Map<String, String> international;
}

/// Builds the device-home model from lockdownd domains.
///
/// Display, Wi-Fi/Bluetooth state and cellular carrier details aren't exposed
/// by lockdownd at all, so those fields stay null on iOS rather than guessing.
DeviceInfo buildIosDeviceInfo(IosDevice device, IosDeviceDomains domains) {
  final root = domains.root;
  return DeviceInfo(
    identity: DeviceIdentityInfo(
      deviceName: device.name ?? root['DeviceName'],
      manufacturer: 'Apple',
      model: device.model,
      osName: 'iOS',
      osVersion: root['ProductVersion'],
      buildVersion: root['BuildVersion'],
      serialNumber: root['SerialNumber'],
      cpuArchitecture: root['CPUArchitecture'],
    ),
    battery: _battery(domains.battery),
    storage: _storage(domains.diskUsage),
    // iOS devices in this app are only ever seen over USB (no wireless
    // idevice support), so this is a known constant, not a guess.
    connectivity: const DeviceConnectivityInfo(usbConnected: true),
    cellular: DeviceCellularInfo(simState: root['SIMStatus']),
    developerState: DeviceDeveloperStateInfo(
      debuggingReady: device.status == 'device',
      pairingState: iosPairingState(device.status),
    ),
    software: DeviceSoftwareInfo(
      locale: domains.international['Locale'],
      timeZone: root['TimeZone'] ?? domains.international['TimeZone'],
    ),
  );
}

/// Maps the status values carried on `Device.status` for iOS devices into a
/// human-readable pairing/trust label.
String? iosPairingState(String status) {
  return switch (status) {
    'device' => 'Paired',
    'unpaired' => 'Not Paired',
    'locked' => 'Locked (enter passcode)',
    'offline' => 'Unavailable',
    _ => null,
  };
}

DeviceBatteryInfo _battery(Map<String, String> values) {
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

DeviceStorageInfo _storage(Map<String, String> values) {
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
