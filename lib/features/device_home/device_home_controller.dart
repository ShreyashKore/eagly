import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../session/feature_controller.dart';
import 'data/device_performance_stats.dart';
import 'data/installed_app_info.dart';

/// Per-device home/dashboard feature. Owns live device performance stats,
/// refreshed on a configurable interval while the device is connected.
class DeviceHomeController extends FeatureController {
  DeviceHomeController(super.session) {
    _maybeStartPolling();
  }

  @visibleForTesting
  static Duration statsPollInterval = const Duration(seconds: 3);

  DevicePerformanceStats _stats = const DevicePerformanceStats();
  List<InstalledAppInfo> _recentApps = const [];
  Timer? _pollTimer;
  bool _disposed = false;
  bool _loading = false;
  bool _loadingRecentApps = false;

  DevicePerformanceStats get stats => _stats;
  bool get isLoading => _loading;
  List<InstalledAppInfo> get recentApps => _recentApps;
  bool get isLoadingRecentApps => _loadingRecentApps;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void onDeviceConnected() {
    _loading = true;
    _notify();
    _maybeStartPolling();
    unawaited(_refreshStats());
    unawaited(refreshRecentApps());
  }

  @override
  void onDeviceDisconnected() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _stats = const DevicePerformanceStats();
    _recentApps = const [];
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

  Future<void> refreshRecentApps() async {
    if (_disposed || !isConnected) return;
    _loadingRecentApps = true;
    _notify();
    try {
      _recentApps = await service.listRecentlyInstalledApps();
      _loadingRecentApps = false;
      _notify();
    } catch (_) {
      _loadingRecentApps = false;
      _recentApps = const [];
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
