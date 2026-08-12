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
      logError(
        'ProcessException while installing app on iOS device $deviceId',
        error,
      );
      return DeviceCommandResult.failure(
        error: 'Failed to install app on $deviceId: ${describeError(error)}',
      );
    } catch (error) {
      logError(
        'Unexpected error while installing app on iOS device $deviceId',
        error,
      );
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
  /// uninstallable. `-o xml` is required: the plain (default) `-l` output is
  /// a terse CSV table (`id, "version", "name"`), not the plist this parser
  /// expects — without it every app is silently dropped.
  Future<List<AppInfo>> listAllApps(String deviceId) async {
    try {
      final result = await runText(['-u', deviceId, '-l', '-o', 'xml']);
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

  /// Splits the plist array into each app's top-level `<dict>…</dict>` block,
  /// tracking nesting depth (real per-app plists commonly nest further dicts
  /// — entitlements, environment variables, group containers, …) so a block
  /// boundary is only drawn where depth returns to zero. Fields are then
  /// looked up independently within each block, so declaration order doesn't
  /// matter — real device dumps do *not* guarantee `CFBundleIdentifier`
  /// appears before `CFBundleDisplayName`/`CFBundleShortVersionString`, which
  /// an earlier identifier-anchored-slice approach got wrong (it attributed
  /// fields declared before the identifier to the *previous* app).
  List<AppInfo> _parseInstalledAppsDetailed(String xml) {
    final apps = <AppInfo>[];
    for (final block in _splitTopLevelDicts(xml)) {
      final bundleId = _extractKeyedString(block, 'CFBundleIdentifier');
      if (bundleId == null) continue;

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

  List<String> _splitTopLevelDicts(String xml) {
    final blocks = <String>[];
    var depth = 0;
    var blockStart = -1;

    for (final match in RegExp(r'<dict\s*/>|<dict>|</dict>').allMatches(xml)) {
      final tag = match.group(0)!;
      if (tag.startsWith('<dict') && tag.endsWith('/>')) {
        continue; // self-closing empty dict — no depth change
      }

      if (tag == '<dict>') {
        if (depth == 0) blockStart = match.end;
        depth++;
      } else {
        depth--;
        if (depth == 0 && blockStart >= 0) {
          blocks.add(xml.substring(blockStart, match.start));
          blockStart = -1;
        }
      }
    }
    return blocks;
  }

  /// Looks up [key]'s string value directly inside [block] (a top-level
  /// app dict from [_splitTopLevelDicts]) — but only at *that* dict's own
  /// depth, not inside any dict nested within it (entitlements, group
  /// containers, embedded extensions, …), which could otherwise declare a
  /// same-named key earlier in the text and win a naive first-match search.
  String? _extractKeyedString(String block, String key) {
    final tagPattern = RegExp(
      r'<dict\s*/>|<dict>|</dict>|<key>([^<]*)</key>\s*<string>([^<]*)</string>',
    );
    var depth = 0;
    for (final match in tagPattern.allMatches(block)) {
      final tag = match.group(0)!;
      if (tag.startsWith('<dict') && tag.endsWith('/>')) continue;
      if (tag == '<dict>') {
        depth++;
        continue;
      }
      if (tag == '</dict>') {
        depth--;
        continue;
      }
      if (depth == 0 && match.group(1) == key) {
        final value = match.group(2)?.trim();
        return (value == null || value.isEmpty) ? null : value;
      }
    }
    return null;
  }

  /// Backs the device-home "recently installed" card — same underlying data
  /// as [listAllApps], just capped and mapped to the lighter model that
  /// feature already uses.
  Future<List<InstalledAppInfo>> listInstalledApps(String deviceId) async {
    try {
      final result = await runText(['-u', deviceId, '-l', '-o', 'xml']);
      if (!result.isSuccess) return [];

      return _parseInstalledAppsDetailed(result.stdout)
          .take(5)
          .map(
            (app) => InstalledAppInfo(
              packageName: app.packageName,
              appName: app.appName,
            ),
          )
          .toList();
    } catch (error) {
      logError('Failed to list installed iOS apps', error);
      return [];
    }
  }
}
