import 'dart:typed_data';

import 'package:eagly/features/apps/data/app_info.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/services/ios/ios_app_service.dart';

/// A phone's apps as [IosAppService] sees them: answers from the fields,
/// recording every request.
class FakeIosAppService implements IosAppService {
  List<AppInfo> apps = const [];
  final List<bool> listRequests = [];
  @override
  bool listsSystemApps = true;

  /// SpringBoard's answer to every icon request; [iconFails] throws instead.
  Uint8List? icon;
  bool iconFails = false;
  final List<({String deviceId, String bundleId})> iconRequests = [];

  @override
  Future<List<AppInfo>> listApps(
    String deviceId, {
    bool includeSystemApps = false,
  }) async {
    listRequests.add(includeSystemApps);
    return [
      for (final app in apps)
        if (includeSystemApps || !app.isSystemApp) app,
    ];
  }

  /// What [canControlApps] answers, and what [launchApp] / [forceStopApp]
  /// were asked to do, as `open <bundle>` / `stop <bundle>`.
  bool appControl = true;
  final List<String> controlRequests = [];

  @override
  Future<bool> canControlApps(String deviceId) async => appControl;

  @override
  Future<DeviceCommandResult> launchApp({
    required String deviceId,
    required String bundleId,
  }) async {
    controlRequests.add('open $bundleId');
    return DeviceCommandResult.success(message: 'Opened $bundleId.');
  }

  @override
  Future<DeviceCommandResult> forceStopApp({
    required String deviceId,
    required String bundleId,
  }) async {
    controlRequests.add('stop $bundleId');
    return DeviceCommandResult.success(message: 'Force-stopped $bundleId.');
  }

  @override
  bool clearsAppData = true;

  @override
  Future<DeviceCommandResult> clearAppData({
    required String deviceId,
    required String bundleId,
  }) async {
    controlRequests.add('clear $bundleId');
    return DeviceCommandResult.success(message: 'Cleared data for $bundleId.');
  }

  @override
  Future<Uint8List?> fetchAppIcon({
    required String deviceId,
    required String bundleId,
  }) async {
    iconRequests.add((deviceId: deviceId, bundleId: bundleId));
    if (iconFails) throw StateError('SpringBoard went away');
    return icon;
  }

  @override
  Future<DeviceCommandResult> installApp({
    required String deviceId,
    required String appPath,
  }) => throw UnimplementedError();

  @override
  Future<DeviceCommandResult> uninstallApp({
    required String deviceId,
    required String bundleId,
  }) => throw UnimplementedError();
}
