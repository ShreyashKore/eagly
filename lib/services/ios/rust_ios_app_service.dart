import 'dart:typed_data';

import '../../features/app_log/app_logger.dart';
import '../../features/apps/data/app_info.dart';
import '../../features/wireless_connection/data/wireless_debug_models.dart';
import '../../src/rust/api/ios.dart' as rust;
import '../../src/rust/api/ios_app_control.dart' as rust;
import 'ios_app_service.dart';

/// [IosAppService] backed by the `idevice` crate's installation_proxy client.
///
/// Replaces both the dual-CLI-dialect probing `ideviceinstaller` needs and the
/// hand-rolled XML plist scanning its output required.
class RustIosAppService implements IosAppService {
  final AppLogger _logger = AppLogger(source: 'RustIosAppService');

  @override
  Future<List<AppInfo>> listApps(
    String deviceId, {
    bool includeSystemApps = false,
  }) async {
    try {
      final apps = await rust.listIosApps(
        udid: deviceId,
        includeSystem: includeSystemApps,
      );
      return [
        for (final app in apps)
          AppInfo(
            packageName: app.bundleId,
            appName: app.name,
            versionName: app.version,
            versionCode: app.build,
            processName: app.executable,
            isSystemApp: app.isSystem,
            isDebuggable: app.isDebuggable,
          ),
      ];
    } catch (error) {
      _logger.error('Failed to list iOS apps', detail: error.toString());
      return const [];
    }
  }

  @override
  bool get listsSystemApps => true;

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

  @override
  Future<bool> canControlApps(String deviceId) async {
    try {
      return await rust.probeIosAppControl(udid: deviceId);
    } catch (error) {
      _logger.error(
        'Failed to probe iOS app control',
        detail: error.toString(),
      );
      return false;
    }
  }

  @override
  Future<DeviceCommandResult> launchApp({
    required String deviceId,
    required String bundleId,
  }) async {
    try {
      await rust.launchIosApp(udid: deviceId, bundleId: bundleId);
      return DeviceCommandResult.success(message: 'Opened $bundleId.');
    } catch (error) {
      _logger.error('Failed to open $bundleId', detail: error.toString());
      return DeviceCommandResult.failure(
        error: 'Failed to open $bundleId: $error',
      );
    }
  }

  @override
  Future<DeviceCommandResult> forceStopApp({
    required String deviceId,
    required String bundleId,
  }) async {
    try {
      final killed = await rust.stopIosApp(udid: deviceId, bundleId: bundleId);
      return DeviceCommandResult.success(
        message: killed == 0
            ? "$bundleId wasn't running."
            : 'Force-stopped $bundleId.',
      );
    } catch (error) {
      _logger.error('Failed to stop $bundleId', detail: error.toString());
      return DeviceCommandResult.failure(
        error: 'Failed to stop $bundleId: $error',
      );
    }
  }

  @override
  Future<DeviceCommandResult> clearAppData({
    required String deviceId,
    required String bundleId,
  }) async {
    try {
      await rust.clearIosAppData(udid: deviceId, bundleId: bundleId);
      return DeviceCommandResult.success(
        message: 'Cleared data for $bundleId.',
      );
    } catch (error) {
      _logger.error(
        'Failed to clear data for $bundleId',
        detail: error.toString(),
      );
      return DeviceCommandResult.failure(
        error: 'Failed to clear data for $bundleId: $error',
      );
    }
  }

  @override
  bool get clearsAppData => true;

  /// Asks SpringBoard. Failures propagate: the caller logs them and retries.
  @override
  Future<Uint8List?> fetchAppIcon({
    required String deviceId,
    required String bundleId,
  }) => rust.fetchIosAppIcon(udid: deviceId, bundleId: bundleId);
}
