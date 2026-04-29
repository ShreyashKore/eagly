import 'dart:io';

import 'tool_process_runner.dart';

class IdeviceIdTool extends ToolProcessRunner {
  IdeviceIdTool({super.executablePath})
    : super(executableName: 'idevice_id');

  Future<List<String>> getDeviceIds() async {
    try {
      final result = await runText(['-l']);
      if (!result.isSuccess) {
        logError(
          'idevice_id -l returned non-zero exit code',
          result.combinedOutput,
        );
        return const [];
      }

      return result.stdout
          .trim()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
    } on ProcessException catch (error) {
      logError('ProcessException while listing iOS device ids', error);
      return const [];
    } catch (error) {
      logError('Unexpected error while listing iOS device ids', error);
      return const [];
    }
  }
}
