import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The helper's entry point in the jar.
const inspectorHelperMainClass = 'dev.eagly.inspector.Main';

/// The helper jar, built by scripts/build_inspector_helper.sh.
const inspectorHelperAsset = 'assets/inspector/eagly-inspector.jar';

Future<String>? _extractedJar;

/// The helper jar as a file `adb push` can read: the asset written to a temp
/// directory, once per run.
Future<String> extractInspectorHelperJar() =>
    _extractedJar ??= _extractJar().catchError((Object error) {
      _extractedJar = null;
      throw error;
    });

Future<String> _extractJar() async {
  final data = await rootBundle.load(inspectorHelperAsset);
  final directory = await Directory.systemTemp.createTemp('eagly-inspector-');
  final file = File('${directory.path}/eagly-inspector.jar');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  return file.path;
}

/// Why the helper couldn't start or answer.
class InspectorHelperException({
  /// `busy` when another UI Automation client holds the device's only
  /// connection; `connect`, `exited`, `timeout` or `protocol` otherwise.
  required final String code,
  required final String message,
}) implements Exception {
  bool get isBusy => code == 'busy';

  @override
  String toString() => message;
}

/// A running copy of Eagly's on-device layout helper
/// (inspector_helper/, docs/LAYOUT_INSPECTOR.md §2.3), spoken to over the
/// `adb shell` process's stdin and stdout: one JSON object per line.
///
/// It holds the device's only UI Automation connection while it runs, so a
/// UI test, Appium or Maestro can't connect until [close] — keep it running
/// only while it is in use.
class InspectorHelper._(final Process _process) {
  /// How long the helper may take to connect and say hello. The first run
  /// on a device also verifies the dex, which takes a moment.
  @visibleForTesting
  static Duration helloTimeout = const Duration(seconds: 10);

  /// How long a request may take. A snapshot is ~0.2 s; a UI that is still
  /// loading can make the tree walk slow, never this slow.
  @visibleForTesting
  static Duration requestTimeout = const Duration(seconds: 15);

  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  final StreamController<void> _changes = StreamController.broadcast();
  final StringBuffer _stderr = StringBuffer();
  final Completer<void> _done = Completer();
  final Completer<Map<String, Object?>> _hello = Completer();
  int _nextId = 1;
  bool _closed = false;

  /// The device's API level, from the helper's hello.
  int sdk = 0;

  /// Fires, coalesced, after the UI changes, while [watch] is on.
  Stream<void> get changes => _changes.stream;

  /// Completes when the helper has exited, for whatever reason.
  Future<void> get done => _done.future;

  bool get isClosed => _closed;

  /// Wraps a just-started helper process and waits for its hello. Throws an
  /// [InspectorHelperException] when it reports an error or exits first.
  static Future<InspectorHelper> attach(Process process) async {
    final helper = InspectorHelper._(process);
    helper._listen();
    try {
      final hello = await helper._hello.future.timeout(helloTimeout);
      helper.sdk = (hello['sdk'] as num?)?.toInt() ?? 0;
      return helper;
    } on TimeoutException {
      await helper.close();
      throw InspectorHelperException(
        code: 'timeout',
        message: 'The inspector helper did not start in time.',
      );
    } catch (_) {
      await helper.close();
      rethrow;
    }
  }

  void _listen() {
    _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_handleLine);
    _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_stderr.write);
    unawaited(_process.exitCode.then(_handleExit));
    // A write after the helper exited fails here, not at the write; the
    // exit is reported through [_handleExit] instead.
    unawaited(_process.stdin.done.catchError((_) {}));
  }

  void _handleLine(String line) {
    final Map<String, Object?> message;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return;
      message = decoded.cast<String, Object?>();
    } on FormatException {
      // Not ours: something on the device wrote to stdout. Skip it.
      return;
    }
    switch (message['event']) {
      case 'hello':
        if (!_hello.isCompleted) _hello.complete(message);
        return;
      case 'error':
        final error = InspectorHelperException(
          code: message['code'] as String? ?? 'connect',
          message: _describeError(message),
        );
        if (!_hello.isCompleted) _hello.completeError(error);
        return;
      case 'changed':
        if (!_changes.isClosed) _changes.add(null);
        return;
    }
    final id = message['id'];
    final completer = id is num ? _pending.remove(id.toInt()) : null;
    if (completer == null) return;
    final error = message['error'];
    if (error != null) {
      completer.completeError(
        InspectorHelperException(code: 'protocol', message: '$error'),
      );
    } else {
      final result = message['result'];
      completer.complete(
        result is Map ? result.cast<String, Object?>() : const {},
      );
    }
  }

  void _handleExit(int code) {
    _closed = true;
    final output = _stderr.toString().trim();
    final error = InspectorHelperException(
      code: 'exited',
      message: output.isEmpty
          ? 'The inspector helper stopped (exit code $code).'
          : 'The inspector helper stopped: ${_lastLines(output)}',
    );
    if (!_hello.isCompleted) _hello.completeError(error);
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
    unawaited(_changes.close());
    if (!_done.isCompleted) _done.complete();
  }

  static String _describeError(Map<String, Object?> message) {
    if (message['code'] == 'busy') {
      return 'Another tool is using UI Automation on this device — a UI '
          'test, Appium, Maestro or uiautomator. Stop it, then capture again.';
    }
    return 'The inspector helper could not connect: ${message['message']}';
  }

  static String _lastLines(String text) {
    final lines = text.split('\n');
    return lines.skip(lines.length > 3 ? lines.length - 3 : 0).join('\n');
  }

  /// Sends [method] and waits for its result.
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (_closed) {
      throw InspectorHelperException(
        code: 'exited',
        message: 'The inspector helper has stopped.',
      );
    }
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _process.stdin.writeln(
      jsonEncode({'id': id, 'method': method, 'params': params}),
    );
    try {
      return await completer.future.timeout(requestTimeout);
    } on TimeoutException {
      _pending.remove(id);
      throw InspectorHelperException(
        code: 'timeout',
        message: 'The inspector helper did not answer "$method" in time.',
      );
    }
  }

  /// The UI as it stands; see `Main.snapshot` for [screenshot] and [idleMs].
  Future<Map<String, Object?>> snapshot({
    bool screenshot = true,
    int idleMs = 0,
  }) => request('snapshot', {'screenshot': screenshot, 'idleMs': idleMs});

  /// Turns [changes] on or off.
  Future<void> watch(bool enabled) => request('watch', {'enabled': enabled});

  /// Ends the helper, releasing UI Automation: closing stdin makes it exit,
  /// and it is killed if it hasn't within a second.
  Future<void> close() async {
    if (_done.isCompleted) return;
    _closed = true;
    try {
      await _process.stdin.close();
    } catch (_) {}
    try {
      await _process.exitCode.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
    }
  }
}
