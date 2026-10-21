import 'dart:async';
import 'dart:typed_data';

import '../../features/app_log/app_logger.dart';
import '../../src/rust/api/ios.dart';
import '../../src/rust/api/ios_mirror.dart' as rust;
import 'ios_mirror_service.dart';

/// [IosMirrorService] over the CoreDevice services in `api/ios_mirror.rs`.
class RustIosMirrorService implements IosMirrorService {
  static int _nextSessionId = 0;

  final AppLogger _logger = AppLogger(source: 'RustIosMirrorService');

  /// Rust keys its registries by these, and a worker removes its own entry
  /// when it ends, so an id is never reused.
  static String _sessionId(String deviceId, String kind) =>
      '$deviceId-$kind-${_nextSessionId++}';

  @override
  Future<IosMirrorSupport> probe(String deviceId) async {
    try {
      final support = await rust.probeIosMirror(udid: deviceId);
      return IosMirrorSupport(
        screenshots: support.screenshots,
        input: support.input,
        pasteboard: support.pasteboard,
        rotation: support.rotation,
        displayStream: support.displayStream,
      );
    } catch (error) {
      // Developer Mode off, or an iOS too old for the CoreDevice tunnel.
      _logger.info(
        'No CoreDevice mirror services on $deviceId',
        detail: _describe(error),
      );
      return IosMirrorSupport.none;
    }
  }

  @override
  Future<IosInterfaceOrientation> interfaceOrientation(String deviceId) async {
    try {
      return switch (await rust.readIosInterfaceOrientation(udid: deviceId)) {
        rust.IosInterfaceOrientation.portrait =>
          IosInterfaceOrientation.portrait,
        rust.IosInterfaceOrientation.portraitUpsideDown =>
          IosInterfaceOrientation.portraitUpsideDown,
        rust.IosInterfaceOrientation.landscapeLeft =>
          IosInterfaceOrientation.landscapeLeft,
        rust.IosInterfaceOrientation.landscapeRight =>
          IosInterfaceOrientation.landscapeRight,
        rust.IosInterfaceOrientation.unknown => IosInterfaceOrientation.unknown,
      };
    } catch (error) {
      _logger.warning(
        'Could not read the interface orientation of $deviceId',
        detail: _describe(error),
      );
      return IosInterfaceOrientation.unknown;
    }
  }

  @override
  Future<Uint8List> captureScreenshot(String deviceId) =>
      _guard(() => rust.captureIosScreenshot(udid: deviceId));

  @override
  Stream<Uint8List> screenshots(String deviceId) {
    final sessionId = _sessionId(deviceId, 'screenshots');
    late final StreamController<Uint8List> controller;
    StreamSubscription<Uint8List>? subscription;
    var ended = false;

    controller = StreamController<Uint8List>(
      onListen: () {
        subscription = rust
            .startIosScreenshotStream(udid: deviceId, sessionId: sessionId)
            .listen(
              controller.add,
              onError: (Object error) =>
                  controller.addError(IosMirrorException(_describe(error))),
              onDone: () {
                // The Rust task has already dropped its registry entry.
                ended = true;
                unawaited(controller.close());
              },
            );
      },
      onCancel: () async {
        await subscription?.cancel();
        // Cancelling the Dart side alone leaves the Rust task polling. Only
        // for a stream still live: Rust keeps a stop with no start to claim it.
        if (!ended) await rust.stopIosScreenshotStream(sessionId: sessionId);
      },
    );
    return controller.stream;
  }

  @override
  Future<IosInputSession> startInput(String deviceId) async {
    final sessionId = _sessionId(deviceId, 'input');
    await _guard(
      () => rust.startIosInput(udid: deviceId, sessionId: sessionId),
    );
    return _RustIosInputSession(sessionId);
  }

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (error) {
      throw IosMirrorException(_describe(error));
    }
  }
}

/// A sentence for an error crossing the bridge.
String _describe(Object error) => switch (error) {
  IosError_UsbmuxdUnavailable() => 'usbmuxd is not reachable.',
  IosError_DeviceNotFound(:final field0) ||
  IosError_NotPaired(:final field0) ||
  IosError_PairingDialogPending(:final field0) ||
  IosError_Locked(:final field0) ||
  IosError_Other(:final field0) => field0,
  _ => error.toString(),
};

class _RustIosInputSession(final String _sessionId) implements IosInputSession {
  @override
  bool touch(IosTouchPhase phase, double x, double y) => rust.sendIosTouch(
    sessionId: _sessionId,
    phase: switch (phase) {
      IosTouchPhase.down => rust.IosTouchPhase.down,
      IosTouchPhase.move => rust.IosTouchPhase.move,
      IosTouchPhase.up => rust.IosTouchPhase.up,
    },
    x: x,
    y: y,
  );

  @override
  bool key(int usage, {required bool down}) =>
      rust.sendIosKey(sessionId: _sessionId, usage: usage, down: down);

  @override
  bool button(int usagePage, int usage, {required bool down}) =>
      rust.sendIosButton(
        sessionId: _sessionId,
        usagePage: usagePage,
        usage: usage,
        down: down,
      );

  @override
  Future<void> setPasteboardText(String text) => RustIosMirrorService._guard(
    () => rust.setIosPasteboardText(sessionId: _sessionId, text: text),
  );

  @override
  Future<void> rotate(IosRotation rotation) => RustIosMirrorService._guard(
    () => rust.rotateIosDevice(
      sessionId: _sessionId,
      rotation: switch (rotation) {
        IosRotation.left => rust.IosRotation.left,
        IosRotation.right => rust.IosRotation.right,
      },
    ),
  );

  @override
  Future<void> close() => rust.stopIosInput(sessionId: _sessionId);
}
