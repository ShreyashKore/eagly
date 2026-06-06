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
  ScrcpyEmbeddedTool({super.executablePath})
      : super(executableName: 'scrcpy');

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

    Future<void> stop() {
      if (stopRequested) {
        return stopFuture;
      }
      stopRequested = true;
      stopFuture = _cleanup(process, player, device.id);
      return stopFuture;
    }

    try {
      // Create named pipe for streaming
      final tempDir = Directory.systemTemp;
      final pipePath = '${tempDir.path}/scrcpy_${device.id}.fifo';
      final pipeFile = File(pipePath);

      // Clean up old pipe if exists
      if (pipeFile.existsSync()) {
        pipeFile.deleteSync();
      }

      // Start scrcpy with H.264 output
      // Using --record to output video stream that media-kit can play
      process = await startProcess([
        '--serial',
        device.id,
        '--no-window',
        '--video-codec=h264',
        '--video-bit-rate=8m',
        '--max-fps=60',
        '--record=$pipePath',
      ]);

      logInfo('Started embedded scrcpy for ${device.displayName}');
      unawaited(_logProcessOutput(process, device));

      // Initialize media-kit player
      player = Player();

      // Wait for scrcpy to start writing to the pipe
      await Future.delayed(const Duration(milliseconds: 1000));

      // Open pipe stream with media-kit
      await player.open(Media(pipePath), play: true);

      logInfo('Streaming from pipe: $pipePath');

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
      throw ScreenMirrorException('Failed to start scrcpy: ${describeError(error)}');
    }
  }

  Future<void> _logProcessOutput(Process process, Device device) async {
    final stderr = stderrText(process);
    stderr.then((output) {
      if (output.isNotEmpty) {
        logInfo('scrcpy stderr for ${device.displayName}: $output');
      }
    });
  }

  Future<void> _cleanup(Process? process, Player player, String deviceId) async {
    try {
      await player.dispose();

      // Kill scrcpy process
      if (process != null) {
        process.kill();
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } catch (_) {
          // Force kill if timeout
          process.kill(ProcessSignal.sigkill);
        }
      }

      // Clean up pipe file
      final tempDir = Directory.systemTemp;
      final pipePath = '${tempDir.path}/scrcpy_$deviceId.fifo';
      final pipeFile = File(pipePath);
      if (pipeFile.existsSync()) {
        pipeFile.deleteSync();
      }
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
