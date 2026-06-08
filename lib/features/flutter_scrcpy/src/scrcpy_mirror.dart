import 'dart:async';

import 'scrcpy_client.dart';
import 'scrcpy_video_channel.dart';

export 'scrcpy_client.dart' show ScrcpyControl, ScrcpyTouchAction;

class ScrcpyMirrorException implements Exception {
  const ScrcpyMirrorException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// An active embedded mirror: a native texture being fed decoded frames from
/// scrcpy-server. Render it with `Texture(textureId: session.textureId)`.
class ScrcpyMirrorSession {
  ScrcpyMirrorSession({
    required this.serial,
    required this.textureId,
    required this.deviceName,
    required this.width,
    required this.height,
    required this.control,
    required this.exitCode,
    required this.streamEnded,
    required Future<void> Function() onStop,
  }) : _onStop = onStop;

  /// adb serial of the mirrored device.
  final String serial;
  final int textureId;
  final String deviceName;
  final int width;
  final int height;

  /// Control channel for injecting input, or null if unavailable.
  final ScrcpyControl? control;

  /// Completes when scrcpy-server exits (0 = clean stop).
  final Future<int> exitCode;

  /// Completes when the video stream ends unexpectedly (e.g. a framing desync
  /// from a device rotation) while the session is still meant to be running.
  /// Never completes on an intentional [stop]. Consumers can await this to
  /// restart the mirror for a clean handshake.
  final Future<void> streamEnded;

  final Future<void> Function() _onStop;

  Future<void> stop() => _onStop();
}

/// Orchestrates an embedded screen mirror: allocate a native texture, connect
/// the [ScrcpyClient], and pump decoded access units into the texture.
class ScrcpyMirror {
  ScrcpyMirror({
    required String serverJarPath,
    String adbExecutablePath = 'adb',
    ScrcpyVideoChannel? channel,
    ScrcpyClient? client,
    void Function(String message)? onLog,
  }) : _channel = channel ?? const ScrcpyVideoChannel(),
       _client =
           client ??
           ScrcpyClient(
             adbExecutablePath: adbExecutablePath,
             serverJarPath: serverJarPath,
             onLog: onLog,
           );

  final ScrcpyVideoChannel _channel;
  final ScrcpyClient _client;

  /// Starts mirroring the device identified by adb [serial]. The caller is
  /// responsible for ensuring the device is an Android device.
  Future<ScrcpyMirrorSession> start(
    String serial, {
    ScrcpyVideoOptions options = const ScrcpyVideoOptions(
      maxSize: 1280,
      maxFps: 60,
      videoBitRate: 8000000,
      control: true,
    ),
  }) async {
    final textureId = await _channel.createTexture();
    ScrcpyStream? stream;
    StreamSubscription<ScrcpyPacket>? subscription;
    var stopped = false;
    final streamEnded = Completer<void>();

    // The packet stream dying while we still want to be running (a desync, not
    // an intentional stop) is the signal to restart for a clean handshake.
    void onStreamGone() {
      if (!stopped && !streamEnded.isCompleted) streamEnded.complete();
    }

    Future<void> stop() async {
      if (stopped) return;
      stopped = true;
      await subscription?.cancel();
      await stream?.stop();
      await _channel.disposeTexture(textureId);
    }

    try {
      stream = await _client.connect(serial, options: options);
      subscription = stream.packets.listen(
        (packet) => _channel.feed(textureId, packet.data),
        onError: (_) => onStreamGone(),
        onDone: onStreamGone,
        cancelOnError: false,
      );

      return ScrcpyMirrorSession(
        serial: serial,
        textureId: textureId,
        deviceName: stream.deviceName,
        width: stream.width,
        height: stream.height,
        control: stream.control,
        exitCode: stream.serverExitCode,
        streamEnded: streamEnded.future,
        onStop: stop,
      );
    } catch (error) {
      await stop();
      if (error is ScrcpyClientException) {
        throw ScrcpyMirrorException(error.message);
      }
      rethrow;
    }
  }
}
