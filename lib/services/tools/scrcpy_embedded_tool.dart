import 'dart:async';
import 'dart:io';

import 'package:fvp/fvp.dart';
import 'package:video_player/video_player.dart';

import '../../data/device.dart';
import '../../utils/utils.dart';
import 'tool_process_runner.dart';

class EmbeddedScreenMirrorSession {
  EmbeddedScreenMirrorSession({
    required this.device,
    required this.controller,
    required this.process,
    required Future<void> Function() onStop,
  }) : _onStop = onStop;

  final Device device;
  final VideoPlayerController controller;
  final Process process;
  final Future<void> Function() _onStop;

  Future<void> stop() => _onStop();
}

/// Embeds the scrcpy stream by piping scrcpy's MKV recording through a named
/// pipe (FIFO) that the video_player (fvp/libmdk) reads directly.
///
/// scrcpy can only write its video to a file path, not to stdout. Writing to a
/// regular file is unusable for live playback: the Matroska muxer treats a
/// seekable file as offline output and buffers everything, so the file stays
/// empty until scrcpy exits (verified: 0 bytes for the whole session, then the
/// full recording flushed on close). A FIFO is *non-seekable*, which forces the
/// muxer into streaming mode and makes it flush the header + clusters as they
/// are produced. libmdk opens the FIFO like any live, unseekable stream and
/// keeps playing until scrcpy closes the write end.
class ScrcpyEmbeddedTool extends ToolProcessRunner {
  ScrcpyEmbeddedTool({super.executablePath}) : super(executableName: 'scrcpy');

  Future<EmbeddedScreenMirrorSession> startEmbedded(Device device) async {
    if (device is! AndroidDevice) {
      throw UnsupportedError(
        'Screen mirroring is currently supported for Android devices only.',
      );
    }
    // The FIFO transport relies on POSIX named pipes (`mkfifo`). Windows has no
    // equivalent we can create from Dart, so embedded mirroring is unsupported
    // there for now.
    if (Platform.isWindows) {
      throw const ScreenMirrorException(
        'Embedded screen mirroring is not supported on Windows yet.',
      );
    }

    Process? process;
    VideoPlayerController? controller;
    File? fifoFile;
    var stopRequested = false;
    var stopFuture = Future<void>.value();

    Future<void> stop() {
      if (stopRequested) return stopFuture;
      stopRequested = true;
      stopFuture = _cleanup(process, controller, fifoFile);
      return stopFuture;
    }

    try {
      final tempDir = Directory.systemTemp;
      fifoFile = File(
        '${tempDir.path}/eagly_scrcpy_${device.id}_'
        '${DateTime.now().millisecondsSinceEpoch}.mkv',
      );
      if (fifoFile.existsSync()) {
        fifoFile.deleteSync();
      }
      await _makeFifo(fifoFile.path);

      logInfo('Using scrcpy executable: $executable');
      logInfo('Streaming ${device.displayName} via FIFO ${fifoFile.path}');

      // --no-window suppresses scrcpy's own window (implies --no-video-playback).
      // --no-audio keeps the live stream video-only (lower latency, no surprise
      // playback of device audio through the desktop). MKV is used because its
      // clusters are playable while still being written.
      process = await startProcess([
        '--serial',
        device.id,
        '--no-window',
        '--no-audio',
        '--video-codec=h264',
        '--video-bit-rate=5m',
        '--max-fps=30',
        '--record=${fifoFile.path}',
        '--record-format=mkv',
      ]);
      logInfo('Started scrcpy process for ${device.displayName}');

      final stderrFuture = stderrText(process);

      // If scrcpy dies during startup, surface its error instead of hanging.
      unawaited(
        process.exitCode.then((code) async {
          if (stopRequested) return;
          final err = await stderrFuture.catchError((_) => '');
          logError(
            'scrcpy exited early (code $code) for ${device.displayName}',
            err,
          );
          await stop();
        }),
      );

      // fvp (libmdk) opens the FIFO for reading, which unblocks scrcpy's
      // write-side open; data then flows scrcpy -> FIFO -> libmdk -> texture.
      controller = VideoPlayerController.file(fifoFile);

      // initialize() completes once libmdk has decoded the first frame and knows
      // the video size; bound it so a stalled stream surfaces as an error
      // instead of hanging the "starting" state forever.
      await controller.initialize().timeout(const Duration(seconds: 20));
      if (stopRequested) {
        throw const ScreenMirrorException('Screen mirror was stopped.');
      }
      // Live-stream buffering: start immediately (min 0), cap the buffer at 1s
      // and drop old non-key packets to stay at the live edge. This is the
      // low-latency behaviour without the global 'lowLatency' option's
      // +nobuffer flag, which would drop the first keyframe and render black.
      controller.setBufferRange(min: 0, max: 1000, drop: true);
      await controller.play();
      logInfo('fvp player opened for ${device.displayName}');

      return EmbeddedScreenMirrorSession(
        device: device,
        controller: controller,
        process: process,
        onStop: stop,
      );
    } catch (error) {
      logError(
        'Failed to start embedded scrcpy for ${device.displayName}',
        error,
      );
      await _cleanup(process, controller, fifoFile);
      throw ScreenMirrorException(
        'Failed to start scrcpy: ${describeError(error)}',
      );
    }
  }

  Future<void> _makeFifo(String path) async {
    final result = await Process.run('mkfifo', [path]);
    if (result.exitCode != 0) {
      final detail = (result.stderr is String ? result.stderr as String : '')
          .trim();
      throw ScreenMirrorException(
        'Failed to create video pipe'
        '${detail.isEmpty ? '' : ': $detail'}',
      );
    }
  }

  Future<void> _cleanup(
    Process? process,
    VideoPlayerController? controller,
    File? fifoFile,
  ) async {
    // Kill scrcpy first so it closes the FIFO write end; the reader then sees
    // EOF instead of blocking on a half-open pipe.
    if (process != null) {
      try {
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        process.kill(ProcessSignal.sigkill);
      }
    }

    try {
      await controller?.dispose();
    } catch (_) {}

    try {
      if (fifoFile != null && fifoFile.existsSync()) {
        fifoFile.deleteSync();
      }
    } catch (_) {}
  }
}

class ScreenMirrorException implements Exception {
  const ScreenMirrorException(this.message);

  final String message;

  @override
  String toString() => message;
}
