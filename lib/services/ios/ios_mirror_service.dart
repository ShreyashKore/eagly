import 'dart:typed_data';

import 'ios_backend.dart';
import 'rust_ios_mirror_service.dart';

/// What an iPhone offers the screen mirror through CoreDevice, the services
/// Xcode's Device Hub uses. Everything is false until the phone has Developer
/// Mode on and Xcode's developer disk image mounted. See
/// docs/IOS_SCREEN_MIRROR.md.
class const IosMirrorSupport({
  /// Full-resolution PNG screenshots, real status bar included.
  final bool screenshots = false,

  /// Touch, keyboard and hardware buttons.
  final bool input = false,

  /// Pasting the desktop's text.
  final bool pasteboard = false,

  /// Device Hub's simulated rotation.
  final bool rotation = false,

  /// Live video through CoreDevice, which takes iOS 27. The mirror does not
  /// show it yet; it is what keeps input working there.
  final bool displayStream = false,
}) {
  static const none = IosMirrorSupport();
}

/// Which way an iPhone's user interface faces.
enum IosInterfaceOrientation {
  portrait,
  portraitUpsideDown,

  /// Home indicator on the left.
  landscapeLeft,

  /// Home indicator on the right.
  landscapeRight,
  unknown,
}

enum IosTouchPhase { down, move, up }

/// One finger of a multi-finger touch; see [IosInputSession.multiTouch].
class const IosTouchContact(
  /// Tells the fingers apart from frame to frame: 0 to 4.
  final int id,
  final double x,
  final double y, {

  /// False in the one frame that lifts this finger.
  final bool touching = true,
});

/// Which way to turn the phone, by 90°.
enum IosRotation { left, right }

class const IosMirrorException(final String message) implements Exception {
  @override
  String toString() => message;
}

/// Touch, keyboard and hardware buttons on one iPhone, open until [close].
///
/// The send methods are synchronous and keep their order; each returns false
/// once the session has ended (the phone went away, say).
abstract interface class IosInputSession {
  /// [x] and [y] are fractions of the panel's width and height in its own
  /// portrait frame, whichever way the picture faces.
  bool touch(IosTouchPhase phase, double x, double y);

  /// One frame of a multi-finger touch, such as a pinch: every finger on the
  /// glass, and once more with `touching: false` for each one that lifts.
  /// Positions are taken as in [touch].
  bool multiTouch(List<IosTouchContact> contacts);

  /// [usage] is on the HID Keyboard/Keypad page (0x07), modifiers included.
  bool key(int usage, {required bool down});

  /// A hardware button: a Consumer page (0x0C) usage, such as Home (0x40).
  bool button(int usagePage, int usage, {required bool down});

  /// Replaces the phone's general pasteboard.
  Future<void> setPasteboardText(String text);

  Future<void> rotate(IosRotation rotation);

  /// Lifts any finger still down and closes the connection.
  Future<void> close();
}

/// The iPhone half of the screen mirror. The picture on macOS comes from
/// QuickTime's capture route instead (`IosScreenCapture`), which needs none of
/// this.
abstract interface class IosMirrorService {
  /// Never throws: a phone without the services answers
  /// [IosMirrorSupport.none].
  Future<IosMirrorSupport> probe(String deviceId);

  Future<IosInterfaceOrientation> interfaceOrientation(String deviceId);

  Future<Uint8List> captureScreenshot(String deviceId);

  /// PNG screenshots, two or three a second, until the
  /// subscription is cancelled.
  Stream<Uint8List> screenshots(String deviceId);

  Future<IosInputSession> startInput(String deviceId);
}

IosMirrorService createIosMirrorService() =>
    useRustIosBackend ? RustIosMirrorService() : const _NoIosMirrorService();

/// The CLI backend's answer: libimobiledevice has no CoreDevice tunnel, so
/// the phone offers nothing beyond what QuickTime's route shows.
class const _NoIosMirrorService() implements IosMirrorService {
  static const _reason = 'This needs the Rust iOS backend.';

  @override
  Future<IosMirrorSupport> probe(String deviceId) async =>
      IosMirrorSupport.none;

  @override
  Future<IosInterfaceOrientation> interfaceOrientation(String deviceId) async =>
      IosInterfaceOrientation.unknown;

  @override
  Future<Uint8List> captureScreenshot(String deviceId) =>
      throw const IosMirrorException(_reason);

  @override
  Stream<Uint8List> screenshots(String deviceId) =>
      Stream.error(const IosMirrorException(_reason));

  @override
  Future<IosInputSession> startInput(String deviceId) =>
      throw const IosMirrorException(_reason);
}
