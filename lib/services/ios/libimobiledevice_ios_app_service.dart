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

  @override
  Future<List<AppInfo>> listApps(String deviceId) => _tool.listApps(deviceId);

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

  /// No bundled CLI reads SpringBoard icons, and this backend is going away,
  /// so it doesn't get one: tiles keep their initials.
  @override
  Future<Uint8List?> fetchAppIcon({
    required String deviceId,
    required String bundleId,
  }) async => null;
}
