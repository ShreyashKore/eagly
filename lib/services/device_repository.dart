import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/device.dart';
import 'device_bridge_service.dart';

class DeviceRepository extends ChangeNotifier {
  DeviceRepository._({DeviceBridgeService? deviceBridgeService})
    : _deviceBridgeService = deviceBridgeService ?? DeviceBridgeService();

  factory DeviceRepository.forTesting({
    DeviceBridgeService? deviceBridgeService,
  }) {
    return DeviceRepository._(deviceBridgeService: deviceBridgeService);
  }

  static final DeviceRepository instance = DeviceRepository._();

  static const Duration _minimumRefreshInterval = Duration(seconds: 2);
  static const Duration _androidRefreshDebounce = Duration(milliseconds: 350);
  static const Duration _androidWatcherRestartDelay = Duration(seconds: 2);
  static const Duration _iosRefreshInterval = Duration(seconds: 4);

  final DeviceBridgeService _deviceBridgeService;
  final Map<String, _CachedIosDeviceDescription> _iosDescriptionCache = {};

  List<Device> _devices = const [];
  bool _isLoading = false;
  bool _hasAttemptedLoad = false;
  bool _started = false;
  bool _disposed = false;
  bool _refreshQueued = false;
  DateTime? _lastRefreshAt;

  Future<void>? _refreshInFlight;
  StreamSubscription<String>? _androidDeviceChangesSub;
  Timer? _androidRefreshTimer;
  Timer? _androidWatcherRestartTimer;
  Timer? _iosRefreshTimer;

  List<Device> get devices => List.unmodifiable(_devices);
  bool get isLoading => _isLoading;
  bool get hasAttemptedLoad => _hasAttemptedLoad;

  Future<void> ensureStarted({bool refreshImmediately = false}) async {
    if (_disposed) return;

    if (!_started) {
      _started = true;
      _startAndroidDeviceWatcher();
      _startIosRefreshTimer();
    }

    if (refreshImmediately || _devices.isEmpty) {
      await refreshDevices(force: true, showLoading: refreshImmediately);
    }
  }

  Future<void> refreshDevices({
    bool force = false,
    bool showLoading = false,
  }) async {
    if (_disposed) return;

    _hasAttemptedLoad = true;

    if (_refreshInFlight != null) {
      _refreshQueued = _refreshQueued || force;
      return _refreshInFlight!;
    }

    final now = DateTime.now();
    if (!force &&
        _lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < _minimumRefreshInterval) {
      return;
    }

    if (showLoading) {
      _isLoading = true;
      _notify();
    }

    final refresh = _reloadDevices();
    _refreshInFlight = refresh;

    try {
      await refresh;
    } finally {
      _refreshInFlight = null;
      if (showLoading && _isLoading) {
        _isLoading = false;
        _notify();
      }

      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(refreshDevices(force: true));
      }
    }
  }

  Future<void> _reloadDevices() async {
    final androidDevices = await _deviceBridgeService.getAndroidDevices();
    final iosDeviceIds = await _deviceBridgeService.getIosDeviceIds();
    final iosDevices = await Future.wait(iosDeviceIds.map(_resolveIosDevice));
    final nextDevices = _mergeDevices([...androidDevices, ...iosDevices]);

    nextDevices.sort((left, right) {
      final platformOrder = left.platform.index.compareTo(right.platform.index);
      if (platformOrder != 0) return platformOrder;
      final statusOrder = left.status.compareTo(right.status);
      if (statusOrder != 0) return statusOrder;
      final nameOrder = left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      );
      if (nameOrder != 0) return nameOrder;
      return left.id.compareTo(right.id);
    });

    _lastRefreshAt = DateTime.now();
    if (listEquals(_devices, nextDevices)) {
      return;
    }

    _devices = nextDevices;
    _notify();
  }

  List<Device> _mergeDevices(List<Device> currentDevices) {
    final currentById = {
      for (final device in currentDevices) device.id: device,
    };
    final previousById = {for (final device in _devices) device.id: device};
    final merged = <Device>[];

    for (final device in currentDevices) {
      final previous = previousById[device.id];
      merged.add(
        device.copyWith(
          model: device.model ?? previous?.model,
          name: device.name ?? previous?.name,
          connectionState: DeviceConnectionState.connected,
        ),
      );
    }

    for (final device in _devices) {
      if (currentById.containsKey(device.id)) {
        continue;
      }
      merged.add(
        device.copyWith(connectionState: DeviceConnectionState.disconnected),
      );
    }

    return merged;
  }

  Future<Device> _resolveIosDevice(String deviceId) async {
    final cached = _iosDescriptionCache[deviceId];
    if (cached != null) {
      return cached.toDevice(deviceId);
    }

    final described = await _deviceBridgeService.describeIosDevice(deviceId);
    if (described.name != null || described.model != null) {
      _iosDescriptionCache[deviceId] = _CachedIosDeviceDescription(
        name: described.name,
        model: described.model,
      );
    }
    return described;
  }

  void _startAndroidDeviceWatcher() {
    _androidDeviceChangesSub?.cancel();
    _androidWatcherRestartTimer?.cancel();

    _androidDeviceChangesSub = _deviceBridgeService
        .watchAndroidDeviceChanges()
        .listen(
          (_) => _scheduleAndroidRefresh(),
          onError: (_, __) => _scheduleAndroidWatcherRestart(),
          onDone: _scheduleAndroidWatcherRestart,
          cancelOnError: true,
        );
  }

  void _scheduleAndroidRefresh() {
    if (_disposed) return;

    _androidRefreshTimer?.cancel();
    _androidRefreshTimer = Timer(_androidRefreshDebounce, () {
      if (_disposed) return;
      unawaited(refreshDevices(force: true));
    });
  }

  void _scheduleAndroidWatcherRestart() {
    if (_disposed || !_started) return;

    _androidWatcherRestartTimer?.cancel();
    _androidWatcherRestartTimer = Timer(_androidWatcherRestartDelay, () {
      if (_disposed || !_started) return;
      _startAndroidDeviceWatcher();
    });
  }

  void _startIosRefreshTimer() {
    _iosRefreshTimer?.cancel();
    _iosRefreshTimer = Timer.periodic(_iosRefreshInterval, (_) {
      if (_disposed) return;
      unawaited(refreshDevices());
    });
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _androidRefreshTimer?.cancel();
    _androidWatcherRestartTimer?.cancel();
    _iosRefreshTimer?.cancel();
    unawaited(_androidDeviceChangesSub?.cancel());
    super.dispose();
  }
}

class _CachedIosDeviceDescription {
  const _CachedIosDeviceDescription({this.name, this.model});

  final String? name;
  final String? model;

  Device toDevice(String deviceId) {
    return Device(
      deviceId,
      'device',
      name: name,
      model: model,
      platform: DevicePlatform.ios,
      connectionState: DeviceConnectionState.connected,
    );
  }
}
