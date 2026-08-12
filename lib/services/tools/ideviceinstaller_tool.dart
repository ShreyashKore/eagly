import 'dart:io';

import '../../features/apps/data/app_info.dart';
import '../../features/device_home/data/installed_app_info.dart';
import '../../features/wireless_connection/data/wireless_debug_models.dart';
import '../../utils/utils.dart';
import 'tool_process_runner.dart';

class IdeviceInstallerTool extends ToolProcessRunner {
  IdeviceInstallerTool({super.executablePath})
    : super(executableName: 'ideviceinstaller');

  Future<DeviceCommandResult> installApp({
    required String deviceId,
    required String appPath,
  }) async {
    try {
      final result = await runText(['-u', deviceId, '-i', appPath]);
      final output = result.combinedOutput;
      final failed = !result.isSuccess || _looksLikeFailure(output);

      if (failed) {
        final details = describeCommandFailure(
          'Failed to install app on iOS device $deviceId.',
          result,
        );
        logError('iOS install failed for $deviceId', details);
        return DeviceCommandResult.failure(error: details);
      }

      return DeviceCommandResult.success(
        message: output.isEmpty ? 'Installed app on $deviceId.' : output,
      );
    } on ProcessException catch (error) {
      logError('ProcessException while installing app on iOS device $deviceId', error);
      return DeviceCommandResult.failure(
        error: 'Failed to install app on $deviceId: ${describeError(error)}',
      );
    } catch (error) {
      logError('Unexpected error while installing app on iOS device $deviceId', error);
      return DeviceCommandResult.failure(
        error: 'Failed to install app on $deviceId: ${describeError(error)}',
      );
    }
  }

  bool _looksLikeFailure(String output) {
    final normalized = output.toLowerCase();
    return normalized.contains('error:') || normalized.contains('failed');
  }

  Future<DeviceCommandResult> uninstallApp({
    required String deviceId,
    required String bundleId,
  }) async {
    try {
      final result = await runText(['-u', deviceId, '-U', bundleId]);
      final output = result.combinedOutput;
      final failed = !result.isSuccess || _looksLikeFailure(output);

      if (failed) {
        final details = describeCommandFailure(
          'Failed to uninstall $bundleId on iOS device $deviceId.',
          result,
        );
        logError('iOS uninstall failed for $deviceId', details);
        return DeviceCommandResult.failure(error: details);
      }

      return DeviceCommandResult.success(
        message: output.isEmpty ? 'Uninstalled $bundleId.' : output,
      );
    } on ProcessException catch (error) {
      logError(
        'ProcessException while uninstalling app on iOS device $deviceId',
        error,
      );
      return DeviceCommandResult.failure(
        error: 'Failed to uninstall $bundleId: ${describeError(error)}',
      );
    } catch (error) {
      logError(
        'Unexpected error while uninstalling app on iOS device $deviceId',
        error,
      );
      return DeviceCommandResult.failure(
        error: 'Failed to uninstall $bundleId: ${describeError(error)}',
      );
    }
  }

  /// Full user-app inventory (uncapped, with version) for the Apps feature.
  /// `ideviceinstaller -l` only ever lists user-installed apps — there's no
  /// concept of "system apps" exposed here — so everything returned is
  /// uninstallable.
  Future<List<AppInfo>> listAllApps(String deviceId) async {
    try {
      final result = await runText(['-u', deviceId, '-l']);
      if (!result.isSuccess) return [];

      final apps = _parseInstalledAppsDetailed(result.stdout);
      apps.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      return apps;
    } catch (error) {
      logError('Failed to list all iOS apps', error);
      return [];
    }
  }

  /// Slices the plist-ish `-l` output on each `CFBundleIdentifier` key —
  /// which appears once per app — rather than trying to match balanced
  /// `<dict>` tags (plist dicts can nest, e.g. for entitlements, which a
  /// naive non-greedy `<dict>…</dict>` regex would mis-pair). Robust to key
  /// ordering within a block since each field is looked up independently.
  List<AppInfo> _parseInstalledAppsDetailed(String xml) {
    final apps = <AppInfo>[];
    final markers = RegExp(
      r'<key>CFBundleIdentifier</key>\s*<string>([^<]+)</string>',
    ).allMatches(xml).toList();

    for (var i = 0; i < markers.length; i++) {
      final bundleId = markers[i].group(1)!.trim();
      if (bundleId.isEmpty) continue;
      final blockEnd = i + 1 < markers.length
          ? markers[i + 1].start
          : xml.length;
      final block = xml.substring(markers[i].end, blockEnd);

      apps.add(
        AppInfo(
          packageName: bundleId,
          appName:
              _extractKeyedString(block, 'CFBundleDisplayName') ??
              _extractKeyedString(block, 'CFBundleName'),
          versionName: _extractKeyedString(block, 'CFBundleShortVersionString'),
        ),
      );
    }
    return apps;
  }

  String? _extractKeyedString(String block, String key) {
    final match = RegExp(
      '<key>$key</key>\\s*<string>([^<]*)</string>',
    ).firstMatch(block);
    final value = match?.group(1)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<List<InstalledAppInfo>> listInstalledApps(String deviceId) async {
    try {
      final result = await runText(['-u', deviceId, '-l']);
      if (!result.isSuccess) return [];

      final apps = <InstalledAppInfo>[];
      final xml = result.stdout;
      final dictPattern = RegExp(
        r'<dict>\s*'
        r'<key>CFBundleIdentifier</key>\s*<string>([^<]+)</string>'
        r'(?:\s*<key>(?:[^<]+)</key>\s*<string>[^<]*</string>)*?'
        r'\s*<key>CFBundleDisplayName</key>\s*<string>([^<]*)</string>',
        multiLine: true,
      );

      for (final match in dictPattern.allMatches(xml)) {
        final bundleId = match.group(1) ?? '';
        final displayName =
            (match.group(2)?.isNotEmpty ?? false) ? match.group(2)! : null;
        if (bundleId.isNotEmpty) {
          apps.add(InstalledAppInfo(
            packageName: bundleId,
            appName: displayName,
          ));
        }
      }

      if (apps.isEmpty) {
        final simplePattern = RegExp(
          r'<key>CFBundleIdentifier</key>\s*<string>([^<]+)</string>',
        );
        for (final match in simplePattern.allMatches(xml)) {
          final bundleId = match.group(1) ?? '';
          if (bundleId.isNotEmpty) {
            apps.add(InstalledAppInfo(packageName: bundleId));
          }
        }
      }

      return apps.take(5).toList();
    } catch (error) {
      logError('Failed to list installed iOS apps', error);
      return [];
    }
  }
}

