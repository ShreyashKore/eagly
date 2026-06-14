import 'dart:async';
import 'dart:typed_data';

import '../../data/device.dart';
import '../../services/device_session_repository.dart';
import '../../session/feature_controller.dart';
import '../../utils/utils.dart';
import '../flutter_scrcpy/flutter_scrcpy.dart';

enum ScreenMirrorState { stopped, starting, running, unsupported, error }

/// Encoder quality presets for the screen mirror. Higher quality streams more
/// pixels/bits, which increases latency.
enum MirrorQuality {
  fastest('Fastest', 'Lowest quality, lowest latency'),
  fast('Fast', 'Lower quality, lower latency'),
  normal('Normal', 'Balanced quality and latency'),
  high('High', 'Best quality, higher latency');

  const MirrorQuality(this.label, this.description);

  final String label;
  final String description;

  ScrcpyVideoOptions toOptions() => switch (this) {
    MirrorQuality.fastest => const ScrcpyVideoOptions(
      maxSize: 480,
      maxFps: 30,
      videoBitRate: 800000,
      control: true,
    ),
    MirrorQuality.fast => const ScrcpyVideoOptions(
      maxSize: 720,
      maxFps: 60,
      videoBitRate: 3000000,
      control: true,
    ),
    MirrorQuality.normal => const ScrcpyVideoOptions(
      maxSize: 1280,
      maxFps: 60,
      videoBitRate: 8000000,
      control: true,
    ),
    MirrorQuality.high => const ScrcpyVideoOptions(
      maxSize: 1920,
      maxFps: 60,
      videoBitRate: 16000000,
      control: true,
    ),
  };
}

/// Per-device screen-mirroring feature. Owns the live scrcpy session, encoder
/// quality, on-device recording, and pane width. Pane *visibility* lives on the
/// owning [DeviceSessionController]; this controller only manages the session.
class MirrorController extends FeatureController {
  MirrorController(super.session);

  var screenMirrorState = ScreenMirrorState.stopped;
  String? screenMirrorError;
  MirrorQuality mirrorQuality = MirrorQuality.normal;
  double paneWidth = 340;

  ScrcpyMirrorSession? _session;
  ScreenRecordingSession? _recordingSession;
  bool _disposed = false;

  /// Number of consecutive automatic restarts (e.g. from rotation desyncs).
  /// Reset once a stream has survived longer than [_restartCooldown]; caps a
  /// restart storm from an app that bounces orientation before settling.
  int _autoRestarts = 0;
  DateTime? _sessionStartedAt;
  static const int _maxAutoRestarts = 6;
  static const Duration _restartCooldown = Duration(seconds: 4);

  ScrcpyMirrorSession? get screenMirrorSession => _session;

  /// Native texture id of the live mirror, or null when not running.
  int? get textureId => _session?.textureId;

  bool get isScreenMirrorRunning =>
      screenMirrorState == ScreenMirrorState.running ||
      screenMirrorState == ScreenMirrorState.starting;

  bool get canStart => session.canMirror;

  bool get isRecording => _recordingSession != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Ensures the mirror is running (used when the pane is opened).
  Future<void> show() async {
    if (isScreenMirrorRunning) return;
    await start();
  }

  Future<void> start() async {
    if (device is! AndroidDevice) {
      screenMirrorError =
          'Screen mirroring is currently available for Android devices.';
      screenMirrorState = ScreenMirrorState.unsupported;
      _notify();
      return;
    }
    if (!isConnected) {
      screenMirrorError = 'The selected device is disconnected.';
      screenMirrorState = ScreenMirrorState.error;
      _notify();
      return;
    }

    await stop(notify: false);
    if (_disposed) return;

    screenMirrorState = ScreenMirrorState.starting;
    screenMirrorError = null;
    _notify();

    try {
      final mirror = await service.startScreenMirror(
        options: mirrorQuality.toOptions(),
      );
      if (_disposed) {
        await mirror.stop();
        return;
      }

      _session = mirror;
      _sessionStartedAt = DateTime.now();
      screenMirrorState = ScreenMirrorState.running;
      _notify();
      unawaited(_watchExit(mirror));
      unawaited(_watchStream(mirror));
    } on ScrcpyMirrorException catch (error) {
      screenMirrorState = ScreenMirrorState.error;
      screenMirrorError = error.message;
      _notify();
    } on UnsupportedError catch (error) {
      screenMirrorState = ScreenMirrorState.unsupported;
      screenMirrorError = error.message;
      _notify();
    } catch (error) {
      screenMirrorState = ScreenMirrorState.error;
      screenMirrorError = describeError(error);
      _notify();
    }
  }

  Future<void> stop({bool notify = true}) async {
    final mirror = _session;
    _session = null;

    if (mirror != null) {
      await mirror.stop();
    }

    if (_disposed) return;
    screenMirrorState = ScreenMirrorState.stopped;
    screenMirrorError = null;
    if (notify) _notify();
  }

  /// Restarts the mirror when its video stream dies unexpectedly. On this
  /// scrcpy build a device rotation perturbs the stream framing and there's no
  /// way to recover in place without visible corruption, so we reconnect for a
  /// clean handshake + keyframe. A cooldown-reset counter caps a restart storm
  /// (e.g. an app that bounces orientation a few times before settling).
  Future<void> _watchStream(ScrcpyMirrorSession mirror) async {
    await mirror.streamEnded;
    if (_disposed || !identical(_session, mirror)) return;
    if (screenMirrorState != ScreenMirrorState.running) return;

    // A stream that ran longer than the cooldown is a one-off, not a storm.
    final startedAt = _sessionStartedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) > _restartCooldown) {
      _autoRestarts = 0;
    }

    if (_autoRestarts >= _maxAutoRestarts) {
      _session = null;
      await mirror.stop();
      if (_disposed) return;
      screenMirrorState = ScreenMirrorState.error;
      screenMirrorError = 'Mirror stream kept resetting; stopped.';
      _notify();
      return;
    }

    _autoRestarts++;
    // Brief settle so a multi-step rotation finishes before we reconnect.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_disposed || !identical(_session, mirror)) return;
    await start();
  }

  Future<void> _watchExit(ScrcpyMirrorSession mirror) async {
    final exitCode = await mirror.exitCode;
    if (_disposed || !identical(_session, mirror)) return;
    _session = null;
    screenMirrorState = exitCode == 0
        ? ScreenMirrorState.stopped
        : ScreenMirrorState.error;
    screenMirrorError = exitCode == 0
        ? null
        : 'scrcpy exited with code $exitCode.';
    _notify();
  }

  /// Forwards a pointer interaction on the mirror surface to the device.
  /// [nx]/[ny] are normalized (0..1) positions within the video rect.
  void handleTouch(ScrcpyTouchAction action, double nx, double ny) {
    final mirror = _session;
    final control = mirror?.control;
    if (mirror == null || control == null) return;
    final x = (nx.clamp(0.0, 1.0) * mirror.width).round();
    final y = (ny.clamp(0.0, 1.0) * mirror.height).round();
    control.touch(
      action,
      x: x,
      y: y,
      videoWidth: mirror.width,
      videoHeight: mirror.height,
    );
  }

  /// Injects a hardware / navigation key into the mirrored device. No-op when
  /// the control channel is unavailable.
  void handleKey(ScrcpyKey key) {
    _session?.control?.key(key);
  }

  /// Switches the encoder quality preset. Restarts the live stream so the new
  /// resolution/bitrate take effect.
  Future<void> setQuality(MirrorQuality quality) async {
    if (quality == mirrorQuality) return;
    mirrorQuality = quality;
    _notify();
    if (isScreenMirrorRunning) {
      await start();
    }
  }

  /// Captures a PNG screenshot of the mirrored device, or null if unavailable.
  Future<Uint8List?> captureScreenshot() async {
    if (_session == null) return null;
    return service.captureScreenshot();
  }

  /// Cycles the mirrored device's display orientation.
  Future<void> rotate() async {
    if (_session == null) return;
    await service.rotateDevice();
  }

  /// Begins recording the mirrored device's screen on-device.
  Future<void> startRecording() async {
    if (_session == null || _recordingSession != null) return;
    _recordingSession = await service.startScreenRecording();
    _notify();
  }

  /// Stops recording and saves the finalized mp4 to [localPath].
  Future<void> stopRecording(String localPath) async {
    final recording = _recordingSession;
    _recordingSession = null;
    _notify();
    await recording?.stopAndPull(localPath);
  }

  /// Stops recording and discards it without saving.
  Future<void> cancelRecording() async {
    final recording = _recordingSession;
    _recordingSession = null;
    _notify();
    await recording?.cancel();
  }

  /// Adjusts the mirror pane width (clamped) when the user drags its edge.
  void setPaneWidth(double width) {
    final clamped = width.clamp(260.0, 720.0);
    if (clamped == paneWidth) return;
    paneWidth = clamped;
    _notify();
  }

  @override
  void onDeviceDisconnected() {
    unawaited(stop());
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop(notify: false));
    super.dispose();
  }
}
