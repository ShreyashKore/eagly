import 'dart:async';

import '../../data/device.dart';
import '../scrcpy_video_channel.dart';
import 'scrcpy_client.dart';

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
    required this.device,
    required this.textureId,
    required this.deviceName,
    required this.width,
    required this.height,
    required this.control,
    required this.exitCode,
    required Future<void> Function() onStop,
  }) : _onStop = onStop;

  final Device device;
  final int textureId;
  final String deviceName;
  final int width;
  final int height;

  /// Control channel for injecting input, or null if unavailable.
  final ScrcpyControl? control;

  /// Completes when scrcpy-server exits (0 = clean stop).
  final Future<int> exitCode;
  final Future<void> Function() _onStop;

  Future<void> stop() => _onStop();
}

/// Orchestrates an embedded screen mirror: allocate a native texture, connect
/// the [ScrcpyClient], and pump decoded access units into the texture.
class ScrcpyMirror {
  ScrcpyMirror({ScrcpyVideoChannel? channel, ScrcpyClient? client})
    : _channel = channel ?? const ScrcpyVideoChannel(),
      _client = client ?? ScrcpyClient();

  final ScrcpyVideoChannel _channel;
  final ScrcpyClient _client;

  Future<ScrcpyMirrorSession> start(
    Device device, {
    ScrcpyVideoOptions options = const ScrcpyVideoOptions(
      maxSize: 1280,
      maxFps: 60,
      videoBitRate: 8000000,
      control: true,
    ),
  }) async {
    if (device is! AndroidDevice) {
      throw UnsupportedError(
        'Screen mirroring is currently supported for Android devices only.',
      );
    }

    final textureId = await _channel.createTexture();
    ScrcpyStream? stream;
    StreamSubscription<ScrcpyPacket>? subscription;
    var stopped = false;

    Future<void> stop() async {
      if (stopped) return;
      stopped = true;
      await subscription?.cancel();
      await stream?.stop();
      await _channel.disposeTexture(textureId);
    }

    try {
      stream = await _client.connect(device.id, options: options);
      subscription = stream.packets.listen(
        (packet) => _channel.feed(textureId, packet.data),
        onError: (_) {}, // termination is surfaced through [exitCode]/[stop]
        cancelOnError: false,
      );

      return ScrcpyMirrorSession(
        device: device,
        textureId: textureId,
        deviceName: stream.deviceName,
        width: stream.width,
        height: stream.height,
        control: stream.control,
        exitCode: stream.serverExitCode,
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
