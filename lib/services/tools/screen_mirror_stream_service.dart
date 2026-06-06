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
  ScreenMirrorStreamService({
    required this.adbTool,
  }) : logger = AppLogger(source: 'ScreenMirrorStreamService');

  final AdbTool adbTool;
  final AppLogger logger;
  static const String _scrcpyServerPath = '/data/local/tmp/scrcpy-server.jar';

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

      serverSocket = await ServerSocket.bind('127.0.0.1', port);
      logger.info('Server listening on port $port for ${device.displayName}');

      final streamController = StreamController<ScreenMirrorFrame>.broadcast();

      _startScrcpyServer(device.id, port).then((_) {
        if (stopRequested) return;
      });

      unawaited(
        _acceptConnection(
          serverSocket,
          device,
          streamController,
          stop,
        ),
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

  Future<void> _startScrcpyServer(String deviceId, int port) async {
    try {
      await adbTool.runText([
        '-s',
        deviceId,
        'shell',
        'nohup',
        'app_process',
        '-cp',
        _scrcpyServerPath,
        '/',
        'com.genymobile.scrcpy.Server',
        '2.6.0',
        'tunnel',
        '0',
        port.toString(),
        '-',
        '8000',
        '0',
        '60',
        '-1',
        '-1',
        '-1',
        '0',
        'true',
        '0',
        '',
      ]);
    } catch (error) {
      logger.error('Failed to start scrcpy-server on $deviceId', detail: error.toString());
      rethrow;
    }
  }

  Future<void> _acceptConnection(
    ServerSocket serverSocket,
    Device device,
    StreamController<ScreenMirrorFrame> streamController,
    Future<void> Function() onStop,
  ) async {
    try {
      final clientSocket = await serverSocket.first;
      logger.info('Client connected for ${device.displayName}');

      await _readVideoStream(clientSocket, device, streamController);
    } catch (error) {
      logger.error('Error accepting connection for ${device.displayName}', detail: error.toString());
      await streamController.close();
    } finally {
      await serverSocket.close();
      await onStop();
    }
  }

  Future<void> _readVideoStream(
    Socket socket,
    Device device,
    StreamController<ScreenMirrorFrame> streamController,
  ) async {
    try {
      final buffer = BytesBuilder();
      const maxFrameSize = 10 * 1024 * 1024;
      var frameCount = 0;

      await for (final chunk in socket) {
        buffer.add(chunk);

        if (buffer.length > maxFrameSize) {
          // Emit frame and reset buffer
          final frameData = Uint8List.fromList(buffer.toBytes());
          frameCount++;
          streamController.add(
            ScreenMirrorFrame(
              width: 1920, // Default resolution
              height: 1080,
              data: frameData,
              timestamp: DateTime.now(),
            ),
          );
          buffer.clear();
          logger.info(
            'Emitted frame $frameCount for ${device.displayName}',
          );
        }
      }

      // Emit final buffer if not empty
      if (buffer.isNotEmpty) {
        final frameData = Uint8List.fromList(buffer.toBytes());
        streamController.add(
          ScreenMirrorFrame(
            width: 1920,
            height: 1080,
            data: frameData,
            timestamp: DateTime.now(),
          ),
        );
      }

      await streamController.close();
    } catch (error) {
      logger.error('Error reading video stream for ${device.displayName}', detail: error.toString());
      await streamController.close();
    }
  }

  Future<void> _cleanup(
    ServerSocket? serverSocket,
    Socket? clientSocket,
    String deviceId,
  ) async {
    try {
      await clientSocket?.close();
      await serverSocket?.close();

      await adbTool.runText(['-s', deviceId, 'shell', 'pkill', 'scrcpy']);
    } catch (error) {
      logger.warning('Error during cleanup for $deviceId');
    }
  }
}
