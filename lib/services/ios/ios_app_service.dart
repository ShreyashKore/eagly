import 'dart:typed_data';

import '../../features/apps/data/app_info.dart';
import '../../features/device_home/data/installed_app_info.dart';
import '../../features/wireless_connection/data/wireless_debug_models.dart';
import 'ios_backend.dart';
import 'libimobiledevice_ios_app_service.dart';
import 'rust_ios_app_service.dart';

/// App inventory and lifecycle for one iOS device.
abstract interface class IosAppService {
  /// Apps in the order the device reports them: the user's own, plus Apple's
  /// home-screen apps with [includeSystemApps] when [listsSystemApps].
  /// Ordering and capping are presentation concerns, applied by
  /// [sortIosApps] / [takeRecentIosApps] so both backends behave identically.
  Future<List<AppInfo>> listApps(
    String deviceId, {
    bool includeSystemApps = false,
  });

  /// Whether [listApps] can include system apps at all.
  bool get listsSystemApps;

  Future<DeviceCommandResult> installApp({
    required String deviceId,
    required String appPath,
  });

  Future<DeviceCommandResult> uninstallApp({
    required String deviceId,
    required String bundleId,
  });

  /// Whether [launchApp] and [forceStopApp] work on this phone: they go
  /// through CoreDevice's app service, which takes Developer Mode and Xcode's
  /// developer disk image. False when the phone can't be asked.
  Future<bool> canControlApps(String deviceId);

  Future<DeviceCommandResult> launchApp({
    required String deviceId,
    required String bundleId,
  });

  /// Kills the app and its extensions; succeeds when it wasn't running.
  Future<DeviceCommandResult> forceStopApp({
    required String deviceId,
    required String bundleId,
  });

  /// Deletes a debug build's data ([AppInfo.isDebuggable]), stopping it
  /// first where [canControlApps]. Any other app is refused.
  Future<DeviceCommandResult> clearAppData({
    required String deviceId,
    required String bundleId,
  });

  /// Whether [clearAppData] exists at all.
  bool get clearsAppData;

  /// [bundleId]'s home-screen icon as PNG bytes, or null when this backend
  /// can't read icons at all. Throws when the read fails, so the caller can
  /// tell a missing icon from one worth asking for again.
  Future<Uint8List?> fetchAppIcon({
    required String deviceId,
    required String bundleId,
  });
}

/// Alphabetical by display name, for the Apps feature's full inventory.
List<AppInfo> sortIosApps(List<AppInfo> apps) {
  final sorted = [...apps];
  sorted.sort(
    (a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
  );
  return sorted;
}

/// The device-home "recently installed" card: the first few apps in device
/// order, mapped to the lighter model that feature uses.
List<InstalledAppInfo> takeRecentIosApps(List<AppInfo> apps) {
  return apps
      .take(5)
      .map(
        (app) => InstalledAppInfo(
          packageName: app.packageName,
          appName: app.appName,
        ),
      )
      .toList();
}

IosAppService createIosAppService() {
  return useRustIosBackend
      ? RustIosAppService()
      : LibimobiledeviceIosAppService();
}
