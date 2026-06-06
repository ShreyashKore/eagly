import 'dart:async';
import 'dart:io';

import '../../data/device.dart';
import '../../utils/utils.dart';
import 'tool_process_runner.dart';

class ScreenMirrorSession {
  ScreenMirrorSession({
    required this.device,
    required this.exitCode,
    required Future<void> Function() onStop,
  }) : _onStop = onStop;

  final Device device;
  final Future<int> exitCode;
  final Future<void> Function() _onStop;

  Future<void> stop() => _onStop();
}

class ScrcpyTool extends ToolProcessRunner {
  ScrcpyTool({super.executablePath}) : super(executableName: 'scrcpy');

  Future<ScreenMirrorSession> start(Device device) async {
    if (device is! AndroidDevice) {
      throw UnsupportedError(
        'Screen mirroring is currently supported for Android devices only.',
      );
    }

    Process? process;
    var stopRequested = false;
    var stopFuture = Future<void>.value();

    Future<void> stop() {
      if (stopRequested) {
        return stopFuture;
      }
      stopRequested = true;
      stopFuture = stopProcess(process);
      return stopFuture;
    }

    try {
      process = await startProcess([
        '--serial',
        device.id,
        '--window-title',
        'Eagly - ${device.displayName}',
        '--stay-awake',
      ]);
      unawaited(_logProcessOutput(process, device));
      return ScreenMirrorSession(
        device: device,
        exitCode: process.exitCode,
        onStop: stop,
      );
    } on ProcessException catch (error) {
      logError('Failed to start scrcpy for ${device.displayName}', error);
      throw ScreenMirrorException(
        'Failed to start scrcpy: ${describeError(error)}',
      );
    } catch (error) {
      logError(
        'Unexpected error while starting scrcpy for ${device.displayName}',
        error,
      );
      throw ScreenMirrorException('scrcpy error: ${describeError(error)}');
    }
  }

  Future<void> _logProcessOutput(Process process, Device device) async {
    final output = await Future.wait([
      stdoutLines(process).join('\n'),
      stderrText(process),
    ]);
    final combined = output
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join('\n');
    if (combined.isNotEmpty) {
      logInfo('scrcpy output for ${device.displayName}: $combined');
    }
  }
}

class ScreenMirrorException implements Exception {
  const ScreenMirrorException(this.message);

  final String message;

  @override
  String toString() => message;
}
