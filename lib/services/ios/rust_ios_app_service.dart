import 'dart:typed_data';

import '../../features/app_log/app_logger.dart';
import '../../features/apps/data/app_info.dart';
import '../../features/wireless_connection/data/wireless_debug_models.dart';
import '../../src/rust/api/ios.dart' as rust;
import 'ios_app_service.dart';

/// [IosAppService] backed by the `idevice` crate's installation_proxy client.
///
/// Replaces both the dual-CLI-dialect probing `ideviceinstaller` needs and the
/// hand-rolled XML plist scanning its output required.
class RustIosAppService implements IosAppService {
  final AppLogger _logger = AppLogger(source: 'RustIosAppService');

  @override
  Future<List<AppInfo>> listApps(String deviceId) async {
    try {
      final apps = await rust.listIosApps(udid: deviceId);
      return [
        for (final app in apps)
          AppInfo(
            packageName: app.bundleId,
            appName: app.name,
            versionName: app.version,
          ),
      ];
    } catch (error) {
      _logger.error('Failed to list iOS apps', detail: error.toString());
      return const [];
    }
  }

  @override
  Future<DeviceCommandResult> installApp({
    required String deviceId,
    required String appPath,
  }) async {
    try {
      await rust.installIosApp(udid: deviceId, packagePath: appPath);
      return DeviceCommandResult.success(
        message: 'Installed app on $deviceId.',
      );
    } catch (error) {
      _logger.error('Failed to install $appPath', detail: error.toString());
      return DeviceCommandResult.failure(
        error: 'Failed to install $appPath: $error',
      );
    }
  }

  @override
  Future<DeviceCommandResult> uninstallApp({
    required String deviceId,
    required String bundleId,
  }) async {
    try {
      await rust.uninstallIosApp(udid: deviceId, bundleId: bundleId);
      return DeviceCommandResult.success(message: 'Uninstalled $bundleId.');
    } catch (error) {
      _logger.error('Failed to uninstall $bundleId', detail: error.toString());
      return DeviceCommandResult.failure(
        error: 'Failed to uninstall $bundleId: $error',
      );
    }
  }

  /// Asks SpringBoard. Failures propagate: the caller logs them and retries.
  @override
  Future<Uint8List?> fetchAppIcon({
    required String deviceId,
    required String bundleId,
  }) => rust.fetchIosAppIcon(udid: deviceId, bundleId: bundleId);
}
