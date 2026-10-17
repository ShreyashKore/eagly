import '../../features/apps/data/app_info.dart';
import '../../features/device_home/data/installed_app_info.dart';
import '../../features/wireless_connection/data/wireless_debug_models.dart';
import 'ios_backend.dart';
import 'libimobiledevice_ios_app_service.dart';
import 'rust_ios_app_service.dart';

/// App inventory and lifecycle for one iOS device.
///
/// Only user-installed apps exist here — iOS exposes no notion of system apps
/// through installation_proxy — so everything listed is uninstallable.
abstract interface class IosAppService {
  /// Apps in the order the device reports them. Ordering and capping are
  /// presentation concerns, applied by [sortIosApps] / [takeRecentIosApps] so
  /// both backends behave identically.
  Future<List<AppInfo>> listApps(String deviceId);

  Future<DeviceCommandResult> installApp({
    required String deviceId,
    required String appPath,
  });

  Future<DeviceCommandResult> uninstallApp({
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
