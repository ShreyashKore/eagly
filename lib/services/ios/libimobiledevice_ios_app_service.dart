import 'dart:typed_data';

import '../../features/apps/data/app_info.dart';
import '../../features/wireless_connection/data/wireless_debug_models.dart';
import '../tools/ideviceinstaller_tool.dart';
import 'ios_app_service.dart';

/// [IosAppService] backed by the bundled `ideviceinstaller` CLI.
class LibimobiledeviceIosAppService({
  IdeviceInstallerTool? ideviceInstallerTool,
}) implements IosAppService {
  this : _tool = ideviceInstallerTool ?? IdeviceInstallerTool();

  final IdeviceInstallerTool _tool;

  /// User apps only: [includeSystemApps] is ignored ([listsSystemApps]).
  @override
  Future<List<AppInfo>> listApps(
    String deviceId, {
    bool includeSystemApps = false,
  }) => _tool.listApps(deviceId);

  @override
  bool get listsSystemApps => false;

  @override
  Future<DeviceCommandResult> installApp({
    required String deviceId,
    required String appPath,
  }) => _tool.installApp(deviceId: deviceId, appPath: appPath);

  @override
  Future<DeviceCommandResult> uninstallApp({
    required String deviceId,
    required String bundleId,
  }) => _tool.uninstallApp(deviceId: deviceId, bundleId: bundleId);

  /// No bundled CLI reaches CoreDevice, and this backend is going away.
  @override
  Future<bool> canControlApps(String deviceId) async => false;

  @override
  Future<DeviceCommandResult> launchApp({
    required String deviceId,
    required String bundleId,
  }) async => _needsRust;

  @override
  Future<DeviceCommandResult> forceStopApp({
    required String deviceId,
    required String bundleId,
  }) async => _needsRust;

  @override
  Future<DeviceCommandResult> clearAppData({
    required String deviceId,
    required String bundleId,
  }) async => _needsRust;

  @override
  bool get clearsAppData => false;

  static final _needsRust = DeviceCommandResult.failure(
    error: 'Opening, stopping and clearing iOS apps needs the Rust backend.',
  );

  /// No bundled CLI reads SpringBoard icons, and this backend is going away,
  /// so it doesn't get one: tiles keep their initials.
  @override
  Future<Uint8List?> fetchAppIcon({
    required String deviceId,
    required String bundleId,
  }) async => null;
}
