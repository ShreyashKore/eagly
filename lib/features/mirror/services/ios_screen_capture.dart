import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'screen_recording.dart';

class const IosScreenCaptureException(final String code, final String message)
    implements Exception {
  @override
  String toString() => message;
}

/// A USB iPhone's screen through QuickTime's capture route: macOS offers the
/// phone as a camera once screen-capture devices are allowed. macOS only; the
/// native side is `macos/Runner/IosScreenCapturePlugin.swift`.
class const IosScreenCapture() {
  static const MethodChannel _method = MethodChannel(
    'eagly/ios_screen_capture',
  );
  static const EventChannel _eventChannel = EventChannel(
    'eagly/ios_screen_capture/events',
  );
  static Stream<Map<Object?, Object?>>? _events;

  /// Overrides [isAvailable] in tests, which run on Linux in CI.
  @visibleForTesting
  static bool? debugIsAvailable;

  static bool get isAvailable => debugIsAvailable ?? Platform.isMacOS;

  /// Starts capturing the phone macOS lists as [deviceName] — its own name,
  /// which is all that tells two phones apart. Asks for camera access the
  /// first time. The first frame takes a few seconds; [IosScreenCaptureHandle.sizes]
  /// reports it.
  Future<IosScreenCaptureHandle> start(String deviceName) async {
    final events = _events ??= _eventChannel
        .receiveBroadcastStream()
        .cast<Map<Object?, Object?>>();
    // Listening before the start call, so an event cannot slip past while
    // the texture id is still on its way back.
    final early = <Map<Object?, Object?>>[];
    _ChannelCaptureHandle? handle;
    final subscription = events.listen((event) {
      final current = handle;
      if (current == null) {
        early.add(event);
      } else if (event['textureId'] == current.textureId) {
        current._onEvent(event);
      }
    });
    try {
      final textureId = await _method.invokeMethod<int>('start', {
        'deviceName': deviceName,
      });
      if (textureId == null) {
        throw const IosScreenCaptureException(
          'failed',
          'macOS returned no texture for the iPhone.',
        );
      }
      final started = _ChannelCaptureHandle(textureId, subscription);
      handle = started;
      for (final event in early) {
        if (event['textureId'] == textureId) started._onEvent(event);
      }
      return started;
    } on PlatformException catch (error) {
      await subscription.cancel();
      throw IosScreenCaptureException(
        error.code,
        error.message ?? 'Capturing the iPhone failed.',
      );
    } catch (_) {
      await subscription.cancel();
      rethrow;
    }
  }
}

/// One running capture, shown with `Texture(textureId: handle.textureId)`.
abstract interface class IosScreenCaptureHandle {
  int get textureId;

  /// The picture's size in pixels: the first frame's, then each change (a
  /// rotation).
  Stream<Size> get sizes;
  Size? get size;

  /// Completes with the reason when the capture stops by itself (the phone
  /// unplugged, say). Never completes after [stop].
  Future<String> get ended;

  /// The latest frame as a PNG, with the "9:41" status bar iOS draws while
  /// its screen is captured. Null before the first frame.
  Future<Uint8List?> snapshot();

  /// Starts writing the picture to an mp4 on the Mac, from the frames as they
  /// arrive. Stopping the capture finishes it; it can still be saved then.
  Future<ScreenRecording> record();

  Future<void> stop();
}

class _ChannelCaptureHandle(
  final int _textureId,
  final StreamSubscription<Map<Object?, Object?>> _subscription,
) implements IosScreenCaptureHandle {
  final StreamController<Size> _sizes = StreamController.broadcast();
  final Completer<String> _ended = Completer();
  Size? _size;
  bool _stopped = false;

  @override
  int get textureId => _textureId;

  @override
  Stream<Size> get sizes => _sizes.stream;

  @override
  Size? get size => _size;

  @override
  Future<String> get ended => _ended.future;

  void _onEvent(Map<Object?, Object?> event) {
    switch (event['event']) {
      case 'size':
        final size = Size(
          (event['width']! as int).toDouble(),
          (event['height']! as int).toDouble(),
        );
        _size = size;
        _sizes.add(size);
      case 'ended':
        if (!_ended.isCompleted && !_stopped) {
          _ended.complete(
            event['message'] as String? ?? 'The capture stopped.',
          );
        }
    }
  }

  @override
  Future<Uint8List?> snapshot() => IosScreenCapture._method
      .invokeMethod<Uint8List>('snapshot', {'textureId': textureId});

  @override
  Future<ScreenRecording> record() async {
    try {
      final path = await IosScreenCapture._method.invokeMethod<String>(
        'startRecording',
        {'textureId': textureId},
      );
      return _HostRecording(
        File(path!),
        () => IosScreenCapture._method.invokeMethod<void>('stopRecording', {
          'textureId': textureId,
        }),
      );
    } on PlatformException catch (error) {
      throw IosScreenCaptureException(
        error.code,
        error.message ?? 'Recording the iPhone failed.',
      );
    }
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _subscription.cancel();
    await _sizes.close();
    await IosScreenCapture._method.invokeMethod<void>('stop', {
      'textureId': textureId,
    });
  }
}

/// A recording the Mac writes to a temporary file, moved into place on save.
class _HostRecording(final File _file, final Future<void> Function() _stop)
    implements ScreenRecording {
  @override
  final DateTime startedAt = DateTime.now();

  Future<void>? _stopped;

  @override
  Duration? get timeLimit => null;

  Future<void> _finish() async {
    try {
      await (_stopped ??= _stop());
    } on PlatformException catch (error) {
      throw IosScreenCaptureException(
        error.code,
        error.message ?? 'Finishing the recording failed.',
      );
    }
  }

  @override
  Future<void> save(String localPath) async {
    await _finish();
    try {
      await _file.rename(localPath);
    } on FileSystemException {
      // Another volume: rename cannot cross it.
      await _file.copy(localPath);
      await _file.delete();
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _finish();
    } finally {
      if (await _file.exists()) await _file.delete();
    }
  }
}
