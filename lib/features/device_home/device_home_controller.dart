import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../session/feature_controller.dart';
import 'data/device_info.dart';
import 'data/device_performance_stats.dart';
import 'data/installed_app_info.dart';

/// Per-device home/dashboard feature. Owns live device performance stats and
/// device info, each refreshed on its own configurable interval while the
/// device is connected.
class DeviceHomeController extends FeatureController {
  DeviceHomeController(super.session) {
    _maybeStartPolling();
  }

  @visibleForTesting
  static Duration statsPollInterval = const Duration(seconds: 3);

  /// Device info (battery/storage/connectivity/…) changes far less often than
  /// performance stats and costs more subprocess calls to collect, so it
  /// polls on its own, slower cadence.
  @visibleForTesting
  static Duration deviceInfoPollInterval = const Duration(seconds: 5);

  DevicePerformanceStats _stats = const DevicePerformanceStats();
  DeviceInfo _deviceInfo = const DeviceInfo();
  List<InstalledAppInfo> _recentApps = const [];
  Timer? _pollTimer;
  Timer? _deviceInfoPollTimer;
  bool _disposed = false;
  bool _loading = false;
  bool _loadingDeviceInfo = false;
  bool _loadingRecentApps = false;
  DateTime? _lastUpdatedAt;

  DevicePerformanceStats get stats => _stats;
  DeviceInfo get deviceInfo => _deviceInfo;

  /// When the snapshot below was last refreshed off the device — `null` until
  /// the first successful read.
  DateTime? get lastUpdatedAt => _lastUpdatedAt;

  /// Whether there is anything worth rendering. Stays `true` after a
  /// disconnect: the dashboard keeps showing the last known state.
  bool get hasSnapshot => !_deviceInfo.isEmpty || !_stats.isEmpty;
  bool get isLoading => _loading;
  bool get isLoadingDeviceInfo => _loadingDeviceInfo;
  List<InstalledAppInfo> get recentApps => _recentApps;
  bool get isLoadingRecentApps => _loadingRecentApps;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void onDeviceConnected() {
    _loading = true;
    _loadingDeviceInfo = true;
    _notify();
    _maybeStartPolling();
    unawaited(_refreshStats());
    unawaited(_refreshDeviceInfo());
    unawaited(refreshRecentApps());
  }

  /// Stops polling but *keeps* the last snapshot — the home view renders it
  /// as stale rather than dropping to an empty screen. It is replaced on the
  /// next successful read after a reconnect.
  @override
  void onDeviceDisconnected() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _deviceInfoPollTimer?.cancel();
    _deviceInfoPollTimer = null;
    _loading = false;
    _loadingDeviceInfo = false;
    _loadingRecentApps = false;
    _notify();
  }

  void _maybeStartPolling() {
    if (!isConnected) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(statsPollInterval, (_) {
      unawaited(_refreshStats());
    });
    unawaited(_refreshStats());

    _deviceInfoPollTimer?.cancel();
    _deviceInfoPollTimer = Timer.periodic(deviceInfoPollInterval, (_) {
      unawaited(_refreshDeviceInfo());
    });
    unawaited(_refreshDeviceInfo());

    // The device is usually already connected when this controller is first
    // created, so `onDeviceConnected` never fires for the initial load.
    unawaited(refreshRecentApps());
  }

  Future<void> _refreshDeviceInfo() async {
    if (_disposed || !isConnected) return;
    try {
      _deviceInfo = await service.fetchDeviceInfo();
      _lastUpdatedAt = DateTime.now();
      _loadingDeviceInfo = false;
      _notify();
    } catch (_) {
      _loadingDeviceInfo = false;
      _notify();
    }
  }

  Future<void> _refreshStats() async {
    if (_disposed || !isConnected) return;
    try {
      _stats = await service.fetchPerformanceStats();
      _lastUpdatedAt = DateTime.now();
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
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _deviceInfoPollTimer?.cancel();
    super.dispose();
  }
}
