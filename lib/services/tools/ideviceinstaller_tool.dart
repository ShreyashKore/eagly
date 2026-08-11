import 'dart:io';

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

