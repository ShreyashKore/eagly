import 'package:flutter/foundation.dart';

import '../data/device.dart';
import '../services/device_session_repository.dart';
import 'device_session_controller.dart';

/// Base class for per-device feature controllers (logs, mirror, …).
///
/// A feature controller receives its owning [DeviceSessionController] and gets
/// convenient access to the device + its [DeviceSessionRepository]. It listens to
/// the session and turns connectivity changes into [onDeviceConnected] /
/// [onDeviceDisconnected] hooks so features can react (e.g. stop a stream when
/// the device drops) without any feature talking to another feature directly.
abstract class FeatureController extends ChangeNotifier {
  FeatureController(this.session) : _wasConnected = session.isConnected {
    session.addListener(_handleSessionChanged);
  }

  final DeviceSessionController session;

  DeviceSessionRepository get service => session.service;
  Device get device => session.device;
  bool get isConnected => session.isConnected;

  bool _wasConnected;

  void _handleSessionChanged() {
    final connected = session.isConnected;
    if (connected != _wasConnected) {
      _wasConnected = connected;
      if (connected) {
        onDeviceConnected();
      } else {
        onDeviceDisconnected();
      }
    }
    onSessionChanged();
  }

  /// Called when the device transitions to connected (including reconnect).
  @protected
  void onDeviceConnected() {}

  /// Called when the device transitions to disconnected.
  @protected
  void onDeviceDisconnected() {}

  /// Called on every session notification (after connectivity hooks).
  @protected
  void onSessionChanged() {}

  @override
  void dispose() {
    session.removeListener(_handleSessionChanged);
    super.dispose();
  }
}
