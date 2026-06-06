import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import '../../data/device.dart';
import '../../utils/utils.dart';
import 'screen_mirror_stream_service.dart';
import 'tool_process_runner.dart';

class ScreenMirrorSession {
  ScreenMirrorSession({
    required this.device,
    required this.exitCode,
    required Future<void> Function() onStop,
    this.frameStream,
    this.player,
  }) : _onStop = onStop;

  final Device device;
  final Future<int> exitCode;
  final Stream<ScreenMirrorFrame>? frameStream;
  final Player? player;
  final Future<void> Function() _onStop;

  Future<void> stop() => _onStop();
}

class ScrcpyTool extends ToolProcessRunner {
  ScrcpyTool({
    super.executablePath,
    ScreenMirrorStreamService? screenMirrorStreamService,
  }) : _screenMirrorStreamService = screenMirrorStreamService,
       super(executableName: 'scrcpy');

  final ScreenMirrorStreamService? _screenMirrorStreamService;

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

  Future<ScreenMirrorSession> startEmbedded(Device device) async {
    final streamService = _screenMirrorStreamService;
    if (streamService == null) {
      throw StateError('ScreenMirrorStreamService not initialized');
    }

    try {
      final streamSession = await streamService.start(device);
      return ScreenMirrorSession(
        device: device,
        exitCode: Future.value(0),
        onStop: streamSession.stop,
        frameStream: streamSession.frameStream,
      );
    } on UnsupportedError {
      rethrow;
    } catch (error) {
      logError(
        'Unexpected error while starting embedded scrcpy for ${device.displayName}',
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
