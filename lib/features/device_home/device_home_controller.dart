import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../session/feature_controller.dart';
import 'data/device_performance_stats.dart';

/// Per-device home/dashboard feature. Owns live device performance stats,
/// refreshed on a configurable interval while the device is connected.
class DeviceHomeController extends FeatureController {
  DeviceHomeController(super.session) {
    _maybeStartPolling();
  }

  @visibleForTesting
  static Duration statsPollInterval = const Duration(seconds: 3);

  DevicePerformanceStats _stats = const DevicePerformanceStats();
  Timer? _pollTimer;
  bool _disposed = false;
  bool _loading = false;

  DevicePerformanceStats get stats => _stats;
  bool get isLoading => _loading;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void onDeviceConnected() {
    _loading = true;
    _notify();
    _maybeStartPolling();
    unawaited(_refreshStats());
  }

  @override
  void onDeviceDisconnected() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _stats = const DevicePerformanceStats();
    _notify();
  }

  void _maybeStartPolling() {
    if (!isConnected) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(statsPollInterval, (_) {
      unawaited(_refreshStats());
    });
    unawaited(_refreshStats());
  }

  Future<void> _refreshStats() async {
    if (_disposed || !isConnected) return;
    try {
      _stats = await service.fetchPerformanceStats();
      _loading = false;
      _notify();
    } catch (_) {
      _loading = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }
}
