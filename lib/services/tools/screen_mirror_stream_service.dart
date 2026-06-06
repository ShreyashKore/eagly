import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../data/device.dart';
import '../../features/app_log/app_logger.dart';
import 'adb_tool.dart';

class ScreenMirrorFrame {
  const ScreenMirrorFrame({
    required this.width,
    required this.height,
    required this.data,
    required this.timestamp,
  });

  final int width;
  final int height;
  final Uint8List data;
  final DateTime timestamp;
}

class ScreenMirrorStreamSession {
  ScreenMirrorStreamSession({
    required this.device,
    required this.frameStream,
    required Future<void> Function() onStop,
  }) : _onStop = onStop;

  final Device device;
  final Stream<ScreenMirrorFrame> frameStream;
  final Future<void> Function() _onStop;

  Future<void> stop() => _onStop();
}

class ScreenMirrorStreamService {
  ScreenMirrorStreamService({required this.adbTool})
    : logger = AppLogger(source: 'ScreenMirrorStreamService');

  final AdbTool adbTool;
  final AppLogger logger;

  Future<ScreenMirrorStreamSession> start(Device device) async {
    if (device is! AndroidDevice) {
      throw UnsupportedError(
        'Screen mirroring is currently supported for Android devices only.',
      );
    }

    var stopRequested = false;
    var stopFuture = Future<void>.value();
    ServerSocket? serverSocket;
    Socket? clientSocket;

    Future<void> stop() {
      if (stopRequested) {
        return stopFuture;
      }
      stopRequested = true;
      stopFuture = _cleanup(serverSocket, clientSocket, device.id);
      return stopFuture;
    }

    try {
      const port = 27183;

      serverSocket = await ServerSocket.bind('127.0.0.1', port, shared: true);
      logger.info('Server listening on port $port for ${device.displayName}');

      final streamController = StreamController<ScreenMirrorFrame>.broadcast();

      // Note: Server jar deployment requires downloading/bundling scrcpy-server.jar
      // For now, return a placeholder session with frame stream
      logger.warning(
        'Screen mirror streaming configured but server jar deployment not yet implemented',
      );

      unawaited(
        _simulateFrameStream(device, streamController, Duration(seconds: 5)),
      );

      return ScreenMirrorStreamSession(
        device: device,
        frameStream: streamController.stream,
        onStop: stop,
      );
    } on SocketException catch (error) {
      logger.error(
        'Failed to create socket for ${device.displayName}',
        detail: error.toString(),
      );
      rethrow;
    } catch (error) {
      logger.error(
        'Unexpected error while starting screen mirror for ${device.displayName}',
        detail: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> _simulateFrameStream(
    Device device,
    StreamController<ScreenMirrorFrame> streamController,
    Duration timeout,
  ) async {
    try {
      // Simulate waiting for device to connect
      await Future.delayed(timeout);

      if (!streamController.isClosed) {
        streamController.add(
          ScreenMirrorFrame(
            width: 1920,
            height: 1080,
            data: Uint8List(0),
            timestamp: DateTime.now(),
          ),
        );
      }
    } finally {
      await streamController.close();
    }
  }

  Future<void> _cleanup(
    ServerSocket? serverSocket,
    Socket? clientSocket,
    String deviceId,
  ) async {
    try {
      // Close sockets with error handling
      try {
        await clientSocket?.close();
      } catch (_) {
        // Ignore errors when closing client socket
      }

      try {
        await serverSocket?.close();
      } catch (_) {
        // Ignore errors when closing server socket
      }

      // Kill scrcpy-server on device
      await adbTool.runText(['-s', deviceId, 'shell', 'pkill', 'scrcpy']);
    } catch (error) {
      logger.warning('Error during cleanup for $deviceId');
    }
  }
}
