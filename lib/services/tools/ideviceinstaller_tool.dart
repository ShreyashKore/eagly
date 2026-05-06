import 'dart:io';

import '../../data/wireless_debug_models.dart';
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
}

