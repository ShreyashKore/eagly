import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/device.dart';
import '../../utils/utils.dart';
import 'tool_process_runner.dart';

class EmbeddedScreenMirrorSession {
  EmbeddedScreenMirrorSession({
    required this.device,
    required this.player,
    required this.controller,
    required this.process,
    required Future<void> Function() onStop,
  }) : _onStop = onStop;

  final Device device;
  final Player player;
  final VideoController controller;
  final Process process;
  final Future<void> Function() _onStop;

  Future<void> stop() => _onStop();
}

/// Embeds the scrcpy stream by piping scrcpy's MKV recording through a named
/// pipe (FIFO) that media_kit (libmpv) reads directly.
///
/// scrcpy can only write its video to a file path, not to stdout. Writing to a
/// regular file is unusable for live playback: the Matroska muxer treats a
/// seekable file as offline output and buffers everything, so the file stays
/// empty until scrcpy exits (verified: 0 bytes for the whole session, then the
/// full recording flushed on close). A FIFO is *non-seekable*, which forces the
/// muxer into streaming mode and makes it flush the header + clusters as they
/// are produced. libmpv opens the FIFO like any live, unseekable stream and
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
    Player? player;
    File? fifoFile;
    var stopRequested = false;
    var stopFuture = Future<void>.value();

    Future<void> stop() {
      if (stopRequested) return stopFuture;
      stopRequested = true;
      stopFuture = _cleanup(process, player, fifoFile);
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

      player = Player();

      // Surface libmpv errors/logs so streaming problems are diagnosable.
      player.stream.error.listen((e) {
        logError('media_kit error for ${device.displayName}', e);
      });

      // Create the VideoController *before* opening media. This attaches the
      // libmpv render context (vo=libmpv) so video is drawn into the Flutter
      // texture instead of libmpv opening its own native window.
      final controller = VideoController(player);

      // libmpv opens the FIFO for reading, which unblocks scrcpy's write-side
      // open; data then flows scrcpy -> FIFO -> libmpv.
      await player.open(Media(fifoFile.path), play: true);
      logInfo('media_kit player opened for ${device.displayName}');

      return EmbeddedScreenMirrorSession(
        device: device,
        player: player,
        controller: controller,
        process: process,
        onStop: stop,
      );
    } catch (error) {
      logError(
        'Failed to start embedded scrcpy for ${device.displayName}',
        error,
      );
      await _cleanup(process, player, fifoFile);
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

  Future<void> _cleanup(Process? process, Player? player, File? fifoFile) async {
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
      await player?.dispose();
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
