import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import '../../data/device.dart';
import '../../utils/utils.dart';
import 'tool_process_runner.dart';

class EmbeddedScreenMirrorSession {
  EmbeddedScreenMirrorSession({
    required this.device,
    required this.player,
    required this.process,
    required Future<void> Function() onStop,
  }) : _onStop = onStop;

  final Device device;
  final Player player;
  final Process process;
  final Future<void> Function() _onStop;

  Future<void> stop() => _onStop();
}

class ScrcpyEmbeddedTool extends ToolProcessRunner {
  ScrcpyEmbeddedTool({super.executablePath}) : super(executableName: 'scrcpy');

  Future<EmbeddedScreenMirrorSession> startEmbedded(Device device) async {
    if (device is! AndroidDevice) {
      throw UnsupportedError(
        'Screen mirroring is currently supported for Android devices only.',
      );
    }

    Process? process;
    var stopRequested = false;
    var stopFuture = Future<void>.value();
    late Player player;
    late String pipePath;

    Future<void> stop() {
      if (stopRequested) {
        return stopFuture;
      }
      stopRequested = true;
      stopFuture = _cleanup(process, player, pipePath);
      return stopFuture;
    }

    try {
      // Use temporary file instead of FIFO for better media-kit compatibility
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/scrcpy_${device.id}_${DateTime.now().millisecondsSinceEpoch}.mkv',
      );
      pipePath = tempFile.path;

      logInfo('Using scrcpy executable: $executable');
      logInfo('Target device: ${device.displayName} (${device.id})');
      logInfo('Recording to: $pipePath');

      // Start scrcpy with H.264 output to file
      // --no-playback: Don't display on computer, just capture to file
      process = await startProcess([
        '--serial',
        device.id,
        '--no-playback',
        '--video-codec=h264',
        '--video-bit-rate=5m',
        '--max-fps=30',
        '--record=$pipePath',
      ]);

      logInfo('Started scrcpy process for ${device.displayName}');

      // Capture stderr immediately to diagnose issues
      final stderrFuture = stderrText(process);
      final stdoutFuture = stdoutLines(process).join('\n');

      // Initialize media-kit player
      player = Player();

      // Wait for scrcpy to write initial data to file (increase timeout)
      for (var i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 500));

        final recordFile = File(pipePath);
        if (recordFile.existsSync()) {
          final fileSize = recordFile.lengthSync();
          logInfo('Video file created, size: $fileSize bytes');
          break;
        }

        // Check if process already died
        try {
          final exitCode = await process.exitCode.timeout(
            const Duration(milliseconds: 100),
          );
          // Process exited - get error message
          final stderr = await stderrFuture;
          final stdout = await stdoutFuture;
          throw ScreenMirrorException(
            'scrcpy exited with code $exitCode.\nStderr: $stderr\nStdout: $stdout',
          );
        } catch (e) {
          if (e is ScreenMirrorException) rethrow;
          // Continue waiting
        }
      }

      // Final check
      final recordFile = File(pipePath);
      if (!recordFile.existsSync()) {
        // Get diagnostic info
        final stderr = await stderrFuture
            .timeout(const Duration(seconds: 1))
            .catchError((_) => 'No stderr captured');
        final stdout = await stdoutFuture
            .timeout(const Duration(seconds: 1))
            .catchError((_) => 'No stdout captured');
        throw ScreenMirrorException(
          'Scrcpy failed to create output file.\nStderr: $stderr\nStdout: $stdout',
        );
      }

      // Monitor remaining process output
      unawaited(_monitorProcessOutput(process, device));

      logInfo('Opening video stream: $pipePath');
      await player.open(Media(pipePath), play: true);

      logInfo('Video streaming started for ${device.displayName}');

      return EmbeddedScreenMirrorSession(
        device: device,
        player: player,
        process: process,
        onStop: stop,
      );
    } catch (error) {
      logError(
        'Failed to start embedded scrcpy for ${device.displayName}',
        error,
      );
      await _cleanup(process, player, pipePath);
      throw ScreenMirrorException(
        'Failed to start scrcpy: ${describeError(error)}',
      );
    }
  }

  Future<void> _monitorProcessOutput(Process process, Device device) async {
    try {
      final stderrFuture = stderrText(process);
      final stdoutFuture = stdoutLines(process).join('\n');

      final result = await Future.wait([stdoutFuture, stderrFuture]);
      final stdout = result[0];
      final stderr = result[1];

      if (stderr.isNotEmpty) {
        logInfo('scrcpy stderr for ${device.displayName}:\n$stderr');
      }
      if (stdout.isNotEmpty) {
        logInfo('scrcpy stdout for ${device.displayName}:\n$stdout');
      }
    } catch (e) {
      logError('Error monitoring scrcpy output', e);
    }
  }

  Future<void> _cleanup(
    Process? process,
    Player player,
    String pipePath,
  ) async {
    try {
      // Dispose player first
      try {
        await player.dispose();
      } catch (_) {}

      // Kill scrcpy process
      if (process != null) {
        try {
          if (!process.kill()) {
            logInfo('Process already terminated');
          }
          await process.exitCode.timeout(const Duration(seconds: 2));
        } catch (e) {
          logInfo('Timeout waiting for process exit, forcing kill');
          process.kill(ProcessSignal.sigkill);
        }
      }

      // Clean up recording file
      try {
        final recordFile = File(pipePath);
        if (recordFile.existsSync()) {
          recordFile.deleteSync();
          logInfo('Cleaned up recording file: $pipePath');
        }
      } catch (_) {}
    } catch (error) {
      logError('Error during cleanup', error);
    }
  }
}

class ScreenMirrorException implements Exception {
  const ScreenMirrorException(this.message);

  final String message;

  @override
  String toString() => message;
}
