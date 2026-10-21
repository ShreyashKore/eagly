import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../services/app_breadcrumbs.dart';
import '../../../services/device_session_repository.dart';
import '../../../services/ios/ios_backend.dart';
import '../../../services/ios/ios_mirror_service.dart';
import '../../../utils/utils.dart';
import '../../flutter_scrcpy/flutter_scrcpy.dart';
import '../services/ios_screen_capture.dart';
import 'ios_keyboard.dart';

/// Where an iPhone mirror's picture comes from.
enum IosMirrorVideo {
  /// QuickTime's capture route on macOS: about 50 fps at full resolution.
  liveCapture,

  /// CoreDevice screenshots back to back: under two a second.
  screenshots,
}

/// The phone's hardware buttons, as the control strip offers them.
enum IosButton { home, appSwitcher, lock, volumeUp, volumeDown }

/// A running iPhone mirror: the picture, and touch, keyboard and buttons on
/// top of it. See docs/IOS_SCREEN_MIRROR.md.
///
/// The picture comes from QuickTime's capture route where the host has it
/// (macOS), otherwise from CoreDevice screenshots. Input goes through the
/// CoreDevice HID services, which need Developer Mode and Xcode's developer
/// disk image; without them the mirror is view-only and [inputNotice] says
/// why.
class IosMirrorSession._(
  final DeviceSessionRepository _service,

  /// What the phone offered when the mirror started.
  final IosMirrorSupport support,
  final IosKeyboardTranslator _keyboard,
) extends ChangeNotifier {
  /// Whether this host can show an iPhone's screen at all: QuickTime's route
  /// on macOS, CoreDevice screenshots through the Rust backend elsewhere.
  static bool get isAvailableOnHost =>
      IosScreenCapture.isAvailable || useRustIosBackend;

  /// How long the first frame may take. QuickTime's route took 5.5 s on an
  /// iPhone 16e.
  @visibleForTesting
  static Duration firstFrameTimeout = const Duration(seconds: 25);

  /// How long a button stays down for a press.
  @visibleForTesting
  static Duration buttonHold = const Duration(milliseconds: 100);

  IosScreenCaptureHandle? _capture;
  StreamSubscription<Size>? _sizeSubscription;
  StreamSubscription<Uint8List>? _screenshotSubscription;
  Uint8List? _frame;
  Size? _size;
  String? _videoNotice;
  IosInputSession? _input;
  String? _inputNotice;
  IosInterfaceOrientation _orientation = IosInterfaceOrientation.portrait;
  final Completer<void> _firstFrame = Completer();
  final Completer<String?> _ended = Completer();
  bool _stopped = false;

  /// Starts the picture, waits for its first frame, then connects input. In
  /// that order because starting QuickTime's route re-enumerates the phone on
  /// USB, which would cut an input connection opened before it.
  ///
  /// [onCreated] gets the session as soon as it exists, so a caller can
  /// [stop] it before it has finished starting.
  ///
  /// Throws [IosMirrorException] when there is no picture to be had, or the
  /// session was stopped while starting.
  static Future<IosMirrorSession> start(
    DeviceSessionRepository service, {
    required bool liveCapture,
    required bool controlIsCommand,
    ValueChanged<IosMirrorSession>? onCreated,
  }) async {
    final session = IosMirrorSession._(
      service,
      await service.probeIosMirror(),
      IosKeyboardTranslator(controlIsCommand: controlIsCommand),
    );
    onCreated?.call(session);
    try {
      session._checkRunning();
      await session._startVideo(liveCapture: liveCapture);
      // A capture that ends, or a stop, gives up on the first frame at once
      // rather than at the timeout.
      await Future.any<void>([
        session._firstFrame.future,
        session._ended.future.then<void>(
          (reason) => throw IosMirrorException(reason ?? _stoppedReason),
        ),
      ]).timeout(
        firstFrameTimeout,
        onTimeout: () => throw const IosMirrorException(
          'The iPhone sent no picture. Unlock it and try again.',
        ),
      );
      session._checkRunning();
      await session._startInput();
      session._checkRunning();
      return session;
    } catch (_) {
      await session.stop();
      rethrow;
    }
  }

  IosMirrorVideo get video => _capture != null
      ? IosMirrorVideo.liveCapture
      : IosMirrorVideo.screenshots;

  /// The live capture's texture, when [video] is [IosMirrorVideo.liveCapture].
  int? get textureId => _capture?.textureId;

  /// The latest screenshot, when [video] is [IosMirrorVideo.screenshots].
  Uint8List? get frame => _frame;

  /// The picture's size in pixels. Set once the first frame is in.
  Size? get size => _size;

  /// Why the picture is screenshots rather than live video, when it is.
  String? get videoNotice => _videoNotice;

  bool get hasInput => _input != null;

  /// Why the phone cannot be controlled, when it cannot.
  String? get inputNotice => _inputNotice;

  bool get canPaste => hasInput && support.pasteboard;
  bool get canRotate => hasInput && support.rotation;

  /// Completes when the mirror stops by itself, with the reason; with null
  /// after [stop].
  Future<String?> get ended => _ended.future;

  Future<void> _startVideo({required bool liveCapture}) async {
    String? captureFailure;
    if (liveCapture) {
      try {
        final capture = await _service.startIosScreenCapture();
        if (_stopped) {
          await capture.stop();
          _checkRunning();
        }
        _capture = capture;
        _sizeSubscription = capture.sizes.listen(_onSize);
        if (capture.size case final size?) _onSize(size);
        unawaited(capture.ended.then(_end));
        return;
      } on IosScreenCaptureException catch (error) {
        captureFailure = error.message;
      }
    }
    if (!support.screenshots) {
      throw IosMirrorException(captureFailure ?? _noServicesReason);
    }
    _checkRunning();
    _videoNotice = [
      ?captureFailure,
      'Showing screenshots instead of live video, under two a second.',
    ].join(' ');
    _screenshotSubscription = _service.iosScreenshots().listen(
      _onScreenshot,
      onError: (Object error) => _end('$error'),
      onDone: () => _end('The iPhone stopped sending screenshots.'),
    );
  }

  Future<void> _startInput() async {
    if (!support.input) {
      _inputNotice = useRustIosBackend
          ? 'View only. Controls need Developer Mode on the iPhone and Xcode '
                "27's developer disk image mounted: open Xcode with the iPhone "
                'connected, then restart the mirror.'
          : 'View only. Controls need the Rust iOS backend.';
      return;
    }
    try {
      final input = await _service.startIosInput();
      if (_stopped) {
        await input.close();
        return;
      }
      _input = input;
    } on IosMirrorException catch (error) {
      _inputNotice = 'Controls are off: ${error.message}';
    }
  }

  static const String _noServicesReason =
      "This iPhone's screen can't be shown here. On a Mac it comes through "
      'QuickTime\'s capture route; elsewhere it needs Developer Mode and '
      "Xcode's developer disk image mounted.";

  static const String _stoppedReason = 'The mirror was stopped.';

  void _checkRunning() {
    if (_stopped) throw const IosMirrorException(_stoppedReason);
  }

  void _onScreenshot(Uint8List png) {
    _frame = png;
    final size = pngSize(png);
    if (size != null) _onSize(size);
    _notify();
  }

  void _onSize(Size size) {
    final changed = size != _size;
    _size = size;
    if (!_firstFrame.isCompleted) _firstFrame.complete();
    if (!changed) return;
    unawaited(_readOrientation(size));
    _notify();
  }

  /// The digitizer always takes the panel's portrait frame, so a landscape
  /// picture needs to know which way it was turned.
  Future<void> _readOrientation(Size size) async {
    if (size.height >= size.width) {
      _orientation = IosInterfaceOrientation.portrait;
      return;
    }
    final orientation = await _service.iosInterfaceOrientation();
    if (_stopped || _size != size) return;
    _orientation = switch (orientation) {
      IosInterfaceOrientation.landscapeLeft ||
      IosInterfaceOrientation.landscapeRight => orientation,
      // A landscape picture with a portrait answer is a race with a turn
      // still in flight; home-indicator-right is the more common way.
      _ => IosInterfaceOrientation.landscapeRight,
    };
  }

  // ── Input ─────────────────────────────────────────────────────────────

  /// A pointer on the picture, at fractions [nx]/[ny] of its width and
  /// height.
  void touch(ScrcpyTouchAction action, double nx, double ny) {
    final input = _input;
    if (input == null) return;
    final (x, y) = toPanel(nx, ny, _orientation);
    final phase = switch (action) {
      ScrcpyTouchAction.down => IosTouchPhase.down,
      ScrcpyTouchAction.move => IosTouchPhase.move,
      ScrcpyTouchAction.up => IosTouchPhase.up,
    };
    if (!input.touch(phase, x, y)) _loseInput();
  }

  /// Forwards a desktop key event; see [IosKeyboardTranslator].
  KeyEventResult handleKeyEvent(KeyEvent event) {
    final input = _input;
    if (input == null) return KeyEventResult.ignored;
    switch (_keyboard.translate(
      event,
      ScrcpyModifiers.fromHardwareKeyboard(),
    )) {
      case null:
        return KeyEventResult.ignored;
      case IosIgnoreKey():
        break;
      case IosPressKey(:final page, :final usage, :final down):
        _sendKey(input, page, usage, down: down);
      case IosPasteClipboard():
        unawaited(
          pasteFromClipboard().catchError((Object error) {
            AppBreadcrumbs.action(
              'Paste to the iPhone failed',
              category: 'mirror',
              level: SentryLevel.warning,
              data: {'error': describeError(error)},
            );
            return false;
          }),
        );
    }
    return KeyEventResult.handled;
  }

  /// Lets go of every key still held, for when the mirror loses focus.
  void releaseKeys() {
    final input = _input;
    for (final up in _keyboard.releaseAll()) {
      if (input != null) _sendKey(input, up.page, up.usage, down: false);
    }
  }

  void _sendKey(
    IosInputSession input,
    int page,
    int usage, {
    required bool down,
  }) {
    final sent = page == IosHid.keyboardPage
        ? input.key(usage, down: down)
        : input.button(page, usage, down: down);
    if (!sent) _loseInput();
  }

  Future<void> pressButton(IosButton button) async {
    final input = _input;
    if (input == null) return;
    Future<void> press(int usage, {Duration? hold}) async {
      if (!input.button(IosHid.consumerPage, usage, down: true)) {
        _loseInput();
        return;
      }
      await Future<void>.delayed(hold ?? buttonHold);
      input.button(IosHid.consumerPage, usage, down: false);
    }

    switch (button) {
      case IosButton.home:
        await press(IosHid.home);
      // A double press of Home, as on phones that have the button.
      case IosButton.appSwitcher:
        await press(IosHid.home);
        await Future<void>.delayed(buttonHold);
        await press(IosHid.home);
      case IosButton.lock:
        await press(IosHid.power, hold: buttonHold * 2);
      case IosButton.volumeUp:
        await press(IosHid.volumeUp);
      case IosButton.volumeDown:
        await press(IosHid.volumeDown);
    }
  }

  /// Puts the desktop clipboard's text on the phone's pasteboard and presses
  /// ⌘V. False when there is no text, or nowhere to put it.
  Future<bool> pasteFromClipboard() async {
    final input = _input;
    if (input == null || !support.pasteboard) return false;
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty) return false;
    await input.setPasteboardText(text);
    if (!identical(_input, input)) return false;
    // ⌘ is already down when this came from the user's own ⌘V.
    final command = !_keyboard.isCommandHeld;
    const page = IosHid.keyboardPage;
    if (command) _sendKey(input, page, IosHid.leftGui, down: true);
    _sendKey(input, page, IosHid.keyV, down: true);
    _sendKey(input, page, IosHid.keyV, down: false);
    if (command) _sendKey(input, page, IosHid.leftGui, down: false);
    return true;
  }

  /// Turns the phone a quarter left, as Device Hub's rotate button does.
  Future<void> rotate() async {
    final input = _input;
    if (input == null || !support.rotation) return;
    await input.rotate(IosRotation.left);
  }

  /// A PNG of the screen: CoreDevice's full-resolution one with the real
  /// status bar where the phone offers it, else the latest frame.
  Future<Uint8List?> captureScreenshot() async {
    if (support.screenshots) return _service.captureScreenshot();
    return await _capture?.snapshot() ?? _frame;
  }

  void _loseInput() {
    if (_input == null) return;
    _input = null;
    _inputNotice =
        'The iPhone stopped taking input. Restart the mirror to reconnect.';
    _notify();
  }

  void _end(String reason) {
    if (_stopped || _ended.isCompleted) return;
    _ended.complete(reason);
  }

  void _notify() {
    if (!_stopped) notifyListeners();
  }

  Future<void> stop() async {
    if (_stopped) return;
    releaseKeys();
    _stopped = true;
    // Before the awaits below, so a start still waiting on its first frame
    // gives up at once.
    if (!_ended.isCompleted) _ended.complete(null);
    final input = _input;
    _input = null;
    await _sizeSubscription?.cancel();
    await _screenshotSubscription?.cancel();
    await _capture?.stop();
    await input?.close();
  }
}

/// Maps a point on the picture, at fractions of its width and height, onto
/// the panel's own portrait frame, which the phone's digitizer takes
/// whichever way the interface faces.
@visibleForTesting
(double, double) toPanel(
  double x,
  double y,
  IosInterfaceOrientation orientation,
) => switch (orientation) {
  IosInterfaceOrientation.portraitUpsideDown => (1 - x, 1 - y),
  // Home indicator on the right: the panel's top edge is on the left.
  IosInterfaceOrientation.landscapeRight => (1 - y, x),
  IosInterfaceOrientation.landscapeLeft => (y, 1 - x),
  IosInterfaceOrientation.portrait || IosInterfaceOrientation.unknown => (x, y),
};

/// A PNG's width and height, from its IHDR chunk, which always comes first.
@visibleForTesting
Size? pngSize(Uint8List png) {
  if (png.length < 24) return null;
  final header = ByteData.sublistView(png);
  return Size(header.getUint32(16).toDouble(), header.getUint32(20).toDouble());
}
