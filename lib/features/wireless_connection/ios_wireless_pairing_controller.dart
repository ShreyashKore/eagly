import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/ios/ios_wireless_service.dart';

/// Drives the iOS wireless (remote) pairing flow: advertise this computer as a
/// pairable host, show the 6-digit setup code once a device connects, and
/// surface the paired device when the rppairing conversation completes.
///
/// Unlike wireless ADB there is no QR code — the *device* browses for the host
/// and drives the pairing — so the controller's only jobs are to start/stop the
/// advertising session and carry the stream's events into UI state.
class IosWirelessPairingController extends ChangeNotifier {
  IosWirelessPairingController({
    required this._service,
    Future<String> Function()? resolveStorageDir,
    this._hostName,
    this.hostModel = 'Mac17,7',
  }) : _resolveStorageDir = resolveStorageDir ?? _applicationSupportDir;

  final IosWirelessService _service;
  final Future<String> Function() _resolveStorageDir;
  final String? _hostName;

  /// What the device shows as this host's model. iOS treats the host as a
  /// computer, so a Mac identifier keeps the device UI sensible on any OS.
  final String hostModel;

  IosWirelessPairSession? _session;
  StreamSubscription<IosWirelessPairEvent>? _subscription;
  String? _storageDir;
  String? _resolvedHostName;
  var _disposed = false;
  // Bumped by every start and stop, so a start that resumes from its await to
  // find a newer call has happened leaves the session to that call.
  var _generation = 0;
  var _advertising = false;
  String? _pin;
  String? _deviceName;
  String? _deviceModel;
  String? _deviceUdid;
  String? _error;

  bool get isPairing => _session != null;

  /// The host name being advertised to devices, once [start] has resolved it.
  String? get hostName => _resolvedHostName;

  /// True while advertising over mDNS and no device has connected yet.
  bool get isWaitingForDevice =>
      _advertising && _pin == null && _deviceUdid == null && _error == null;

  bool get isAdvertising => _advertising;
  String? get pin => _pin;
  String? get deviceName => _deviceName;
  String? get deviceModel => _deviceModel;
  String? get deviceUdid => _deviceUdid;
  String? get error => _error;
  bool get isPaired => _deviceUdid != null;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Starts advertising and listening for a device. No-op once running.
  Future<void> start() async {
    if (_session != null || _disposed) return;
    final generation = ++_generation;
    _storageDir ??= await _resolveStorageDir();
    if (generation != _generation || _session != null || _disposed) return;
    final hostName = _hostName ?? _defaultHostName();
    _resolvedHostName = hostName;

    _session = _service.startPairing(
      hostName: hostName,
      hostModel: hostModel,
      storageDir: _storageDir!,
    );
    _subscription = _session!.events.listen(
      _onEvent,
      onError: (Object error) => _setError(error.toString()),
      onDone: _onDone,
    );
    _notify();
  }

  /// Starts a fresh advertising session, discarding any previous outcome.
  Future<void> restart() async {
    await stop();
    _pin = null;
    _deviceName = null;
    _deviceModel = null;
    _deviceUdid = null;
    _error = null;
    await start();
  }

  Future<void> stop() async {
    _generation++;
    final session = _session;
    final subscription = _subscription;
    if (session == null) return;
    // Cleared first so the stream closing as Rust shuts down is not mistaken
    // for a failed pairing, and Rust is stopped before the subscription is
    // cancelled so the advertisement cannot outlive a cancel that stalls.
    _session = null;
    _subscription = null;
    _advertising = false;
    _notify();
    await session.stop();
    await subscription?.cancel();
  }

  void _onEvent(IosWirelessPairEvent event) {
    if (event.isListening) {
      _advertising = true;
    } else if (event.isPin) {
      _pin = event.pin;
    } else if (event.isPaired) {
      _advertising = false;
      _deviceName = event.deviceName;
      _deviceModel = event.deviceModel;
      _deviceUdid = event.deviceUdid;
    } else if (event.isError) {
      _setError(event.message);
    }
    _notify();
  }

  void _setError(String? message) {
    _advertising = false;
    _error = message;
    _notify();
  }

  void _onDone() {
    // The stream closing means the Rust task ended. If neither outcome arrived,
    // the device (or stream) went away mid-flight.
    if (_deviceUdid == null && _error == null && _session != null) {
      _setError('Pairing ended without completing.');
      return;
    }
    _advertising = false;
    _notify();
  }

  static Future<String> _applicationSupportDir() async =>
      (await getApplicationSupportDirectory()).path;

  String _defaultHostName() {
    try {
      final name = Platform.localHostname.trim();
      if (name.isNotEmpty) return name;
    } catch (_) {
      // Fall through to the static name.
    }
    return 'Eagly';
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
