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

class const DeviceIdentityInfo({
  final String? deviceName,
  final String? manufacturer,
  final String? model,
  final String? osName,
  final String? osVersion,
  final String? buildVersion,
  final String? serialNumber,
  final String? cpuArchitecture,
}) {
  bool get isEmpty =>
      deviceName == null &&
      manufacturer == null &&
      model == null &&
      osName == null &&
      osVersion == null &&
      buildVersion == null &&
      serialNumber == null &&
      cpuArchitecture == null;
}

class const DeviceBatteryInfo({
  /// 0–100.
  final int? percentage,
  final BatteryChargingState? chargingState,
  final BatteryHealth? health,
  final double? temperatureCelsius,
}) {
  bool get isEmpty =>
      percentage == null &&
      chargingState == null &&
      health == null &&
      temperatureCelsius == null;
}

class const DeviceStorageInfo({
  final int? totalBytes,
  final int? usedBytes,
  final int? availableBytes,
}) {
  double? get usagePercent {
    final total = totalBytes;
    final used = usedBytes;
    if (total == null || total <= 0 || used == null) return null;
    return (used / total * 100).clamp(0, 100);
  }

  bool get isEmpty =>
      totalBytes == null && usedBytes == null && availableBytes == null;
}

class const DeviceDisplayInfo({
  final int? widthPx,
  final int? heightPx,
  final int? densityDpi,
  final double? refreshRateHz,
  final DisplayOrientation? orientation,
}) {
  bool get isEmpty =>
      widthPx == null &&
      heightPx == null &&
      densityDpi == null &&
      refreshRateHz == null &&
      orientation == null;
}

class const DeviceConnectivityInfo({
  final bool? usbConnected,
  final bool? wifiEnabled,
  final bool? bluetoothEnabled,
  final String? ipAddress,
}) {
  bool get isEmpty =>
      usbConnected == null &&
      wifiEnabled == null &&
      bluetoothEnabled == null &&
      ipAddress == null;
}

class const DeviceCellularInfo({
  final String? carrierName,
  final String? simOperatorName,
  final String? networkType,
  final String? simState,
  final String? mcc,
  final String? mnc,
}) {
  bool get isEmpty =>
      carrierName == null &&
      simOperatorName == null &&
      networkType == null &&
      simState == null &&
      mcc == null &&
      mnc == null;
}

class const DeviceDeveloperStateInfo({
  /// Android only — `Settings > Developer options` master toggle.
  final bool? developerModeEnabled,

  /// Android only — the `adb_enabled` system setting.
  final bool? adbEnabled,

  /// Both platforms — whether this device is currently reachable for
  /// debugging (adb `device` status / idevice pairing+trust).
  final bool? debuggingReady,

  /// iOS only — human-readable pairing/trust state (e.g. "Paired", "Locked").
  final String? pairingState,
}) {
  bool get isEmpty =>
      developerModeEnabled == null &&
      adbEnabled == null &&
      debuggingReady == null &&
      pairingState == null;
}

class const DeviceSoftwareInfo({
  /// Android only.
  final int? sdkLevel,

  /// Android only.
  final String? securityPatch,
  final String? locale,
  final String? timeZone,
}) {
  bool get isEmpty =>
      sdkLevel == null &&
      securityPatch == null &&
      locale == null &&
      timeZone == null;
}

class const DeviceInfo({
  final DeviceIdentityInfo identity = const DeviceIdentityInfo(),
  final DeviceBatteryInfo battery = const DeviceBatteryInfo(),
  final DeviceStorageInfo storage = const DeviceStorageInfo(),
  final DeviceDisplayInfo display = const DeviceDisplayInfo(),
  final DeviceConnectivityInfo connectivity = const DeviceConnectivityInfo(),
  final DeviceCellularInfo cellular = const DeviceCellularInfo(),
  final DeviceDeveloperStateInfo developerState =
      const DeviceDeveloperStateInfo(),
  final DeviceSoftwareInfo software = const DeviceSoftwareInfo(),
}) {
  bool get isEmpty =>
      identity.isEmpty &&
      battery.isEmpty &&
      storage.isEmpty &&
      display.isEmpty &&
      connectivity.isEmpty &&
      cellular.isEmpty &&
      developerState.isEmpty &&
      software.isEmpty;
}
