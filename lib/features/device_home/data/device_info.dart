/// Platform-neutral device information surfaced on the device home screen.
///
/// Android and iOS populate different subsets of these fields depending on
/// what `adb`/`libimobiledevice` can reliably report — every field is
/// nullable and the UI hides whatever a given platform can't provide, rather
/// than showing a fake/default value.
library;

enum BatteryChargingState { charging, discharging, full, notCharging }

enum BatteryHealth { good, overheat, dead, overVoltage, cold }

enum DisplayOrientation { portrait, landscape }

class DeviceIdentityInfo {
  const DeviceIdentityInfo({
    this.deviceName,
    this.manufacturer,
    this.model,
    this.osName,
    this.osVersion,
    this.buildVersion,
    this.serialNumber,
    this.cpuArchitecture,
  });

  final String? deviceName;
  final String? manufacturer;
  final String? model;
  final String? osName;
  final String? osVersion;
  final String? buildVersion;
  final String? serialNumber;
  final String? cpuArchitecture;
}

class DeviceBatteryInfo {
  const DeviceBatteryInfo({
    this.percentage,
    this.chargingState,
    this.health,
    this.temperatureCelsius,
  });

  /// 0–100.
  final int? percentage;
  final BatteryChargingState? chargingState;
  final BatteryHealth? health;
  final double? temperatureCelsius;

  bool get isEmpty =>
      percentage == null &&
      chargingState == null &&
      health == null &&
      temperatureCelsius == null;
}

class DeviceStorageInfo {
  const DeviceStorageInfo({
    this.totalBytes,
    this.usedBytes,
    this.availableBytes,
  });

  final int? totalBytes;
  final int? usedBytes;
  final int? availableBytes;

  double? get usagePercent {
    final total = totalBytes;
    final used = usedBytes;
    if (total == null || total <= 0 || used == null) return null;
    return (used / total * 100).clamp(0, 100);
  }

  bool get isEmpty =>
      totalBytes == null && usedBytes == null && availableBytes == null;
}

class DeviceDisplayInfo {
  const DeviceDisplayInfo({
    this.widthPx,
    this.heightPx,
    this.densityDpi,
    this.refreshRateHz,
    this.orientation,
  });

  final int? widthPx;
  final int? heightPx;
  final int? densityDpi;
  final double? refreshRateHz;
  final DisplayOrientation? orientation;

  bool get isEmpty =>
      widthPx == null &&
      heightPx == null &&
      densityDpi == null &&
      refreshRateHz == null &&
      orientation == null;
}

class DeviceConnectivityInfo {
  const DeviceConnectivityInfo({
    this.usbConnected,
    this.wifiEnabled,
    this.bluetoothEnabled,
    this.ipAddress,
  });

  final bool? usbConnected;
  final bool? wifiEnabled;
  final bool? bluetoothEnabled;
  final String? ipAddress;

  bool get isEmpty =>
      usbConnected == null &&
      wifiEnabled == null &&
      bluetoothEnabled == null &&
      ipAddress == null;
}

class DeviceCellularInfo {
  const DeviceCellularInfo({
    this.carrierName,
    this.simOperatorName,
    this.networkType,
    this.simState,
    this.mcc,
    this.mnc,
  });

  final String? carrierName;
  final String? simOperatorName;
  final String? networkType;
  final String? simState;
  final String? mcc;
  final String? mnc;

  bool get isEmpty =>
      carrierName == null &&
      simOperatorName == null &&
      networkType == null &&
      simState == null &&
      mcc == null &&
      mnc == null;
}

class DeviceDeveloperStateInfo {
  const DeviceDeveloperStateInfo({
    this.developerModeEnabled,
    this.adbEnabled,
    this.debuggingReady,
    this.pairingState,
  });

  /// Android only — `Settings > Developer options` master toggle.
  final bool? developerModeEnabled;

  /// Android only — the `adb_enabled` system setting.
  final bool? adbEnabled;

  /// Both platforms — whether this device is currently reachable for
  /// debugging (adb `device` status / idevice pairing+trust).
  final bool? debuggingReady;

  /// iOS only — human-readable pairing/trust state (e.g. "Paired", "Locked").
  final String? pairingState;

  bool get isEmpty =>
      developerModeEnabled == null &&
      adbEnabled == null &&
      debuggingReady == null &&
      pairingState == null;
}

class DeviceSoftwareInfo {
  const DeviceSoftwareInfo({
    this.sdkLevel,
    this.securityPatch,
    this.locale,
    this.timeZone,
  });

  /// Android only.
  final int? sdkLevel;

  /// Android only.
  final String? securityPatch;
  final String? locale;
  final String? timeZone;

  bool get isEmpty =>
      sdkLevel == null &&
      securityPatch == null &&
      locale == null &&
      timeZone == null;
}

class DeviceInfo {
  const DeviceInfo({
    this.identity = const DeviceIdentityInfo(),
    this.battery = const DeviceBatteryInfo(),
    this.storage = const DeviceStorageInfo(),
    this.display = const DeviceDisplayInfo(),
    this.connectivity = const DeviceConnectivityInfo(),
    this.cellular = const DeviceCellularInfo(),
    this.developerState = const DeviceDeveloperStateInfo(),
    this.software = const DeviceSoftwareInfo(),
  });

  final DeviceIdentityInfo identity;
  final DeviceBatteryInfo battery;
  final DeviceStorageInfo storage;
  final DeviceDisplayInfo display;
  final DeviceConnectivityInfo connectivity;
  final DeviceCellularInfo cellular;
  final DeviceDeveloperStateInfo developerState;
  final DeviceSoftwareInfo software;
}
