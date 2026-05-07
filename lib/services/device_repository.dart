import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/device.dart';
import '../data/ios_device_info.dart';
import '../data/wireless_debug_models.dart';
import '../utils/apple_device_mapping.dart';
import 'tools/adb_tool.dart';
import 'tools/idevice_id_tool.dart';
import 'tools/idevice_info_tool.dart';

class DeviceRepository extends ChangeNotifier {
  DeviceRepository._({
    AdbTool? adbTool,
    IdeviceIdTool? ideviceIdTool,
    IdeviceInfoTool? ideviceInfoTool,
  }) : _adbTool = adbTool ?? AdbTool(),
       _ideviceIdTool = ideviceIdTool ?? IdeviceIdTool(),
       _ideviceInfoTool = ideviceInfoTool ?? IdeviceInfoTool();

  factory DeviceRepository.forTesting({
    AdbTool? adbTool,
    IdeviceIdTool? ideviceIdTool,
    IdeviceInfoTool? ideviceInfoTool,
  }) {
    return DeviceRepository._(
      adbTool: adbTool,
      ideviceIdTool: ideviceIdTool,
      ideviceInfoTool: ideviceInfoTool,
    );
  }

  static final DeviceRepository instance = DeviceRepository._();

  static const Duration _minimumRefreshInterval = Duration(seconds: 2);
  static const Duration _androidRefreshDebounce = Duration(milliseconds: 350);
  static const Duration _androidWatcherRestartDelay = Duration(seconds: 2);
  static const Duration _iosRefreshInterval = Duration(seconds: 4);
  static const Duration _manualRetryInterval = Duration(milliseconds: 500);
  static const int _manualRetryCountMax = 10;
  static const Duration _mdnsRetryInterval = Duration(milliseconds: 500);
  static const int _mdnsRetryCountMax = 20;

  final AdbTool _adbTool;
  final IdeviceIdTool _ideviceIdTool;
  final IdeviceInfoTool _ideviceInfoTool;
  final Map<String, _CachedAndroidDeviceDescription> _androidDescriptionCache =
      {};
  final Map<String, _CachedIosDeviceDescription> _iosDescriptionCache = {};

  List<Device> _devices = const [];
  bool _isLoading = false;
  bool _hasAttemptedLoad = false;
  bool _started = false;
  bool _disposed = false;
  bool _refreshQueued = false;
  DateTime? _lastRefreshAt;

  Future<void>? _refreshInFlight;
  StreamSubscription<List<Device>>? _androidDeviceChangesSub;
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

    final refresh = _reloadDevicesWith(retry: showLoading);
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

  Future<void> _reloadDevicesWith({required bool retry}) async {
    await _reloadDevices();

    if (retry) {
      for (int attempt = 0; attempt < _manualRetryCountMax; attempt++) {
        if (_disposed) return;
        if (_devices.isNotEmpty) return;
        await Future.delayed(_manualRetryInterval);
        if (_disposed) return;
        await _reloadDevices();
      }
    }
  }

  Future<WirelessServiceDiscoveryResult> discoverMdnsServices() async {
    WirelessServiceDiscoveryResult result = await _adbTool
        .discoverMdnsServices();

    for (int attempt = 0; attempt < _mdnsRetryCountMax; attempt++) {
      if (_disposed) break;
      if (result.isSuccess && result.services.isNotEmpty) break;
      await Future.delayed(_mdnsRetryInterval);
      if (_disposed) break;
      result = await _adbTool.discoverMdnsServices();
    }

    return result;
  }

  Future<void> _reloadDevices() async {
    final androidDevices = await _adbTool.getDevices();
    final describedAndroidDevices = await Future.wait(
      androidDevices.map(_resolveAndroidDevice),
    );
    final iosDeviceIds = await _ideviceIdTool.getDeviceIds();
    final iosDevices = await Future.wait(iosDeviceIds.map(_resolveIosDevice));
    final nextDevices = _mergeDevices([
      ...describedAndroidDevices,
      ...iosDevices,
    ]);

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
          brand: device.brand ?? previous?.brand,
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

  Future<Device> _resolveAndroidDevice(Device device) async {
    final cached = _androidDescriptionCache[device.id];
    if (cached != null) {
      return cached.applyTo(device);
    }

    if (device.status != 'device') {
      return device;
    }

    final described = await _adbTool.describeDevice(device.id);
    final enriched = device.copyWith(
      brand: described.brand ?? device.brand,
      model: described.model ?? device.model,
      name: described.name ?? device.name,
    );
    if (enriched.brand != null ||
        enriched.model != null ||
        enriched.name != null) {
      _androidDescriptionCache[device.id] = _CachedAndroidDeviceDescription(
        brand: enriched.brand,
        model: enriched.model,
        name: enriched.name,
      );
    }
    return enriched;
  }

  Future<Device> _resolveIosDevice(String deviceId) async {
    final cached = _iosDescriptionCache[deviceId];
    if (cached != null) {
      return cached.toIosDevice(deviceId);
    }

    final info = await _ideviceInfoTool.readDeviceInfo(deviceId);
    final described = await _mapIosDeviceInfo(info);
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

    _androidDeviceChangesSub = _adbTool.watchDeviceChanges().listen(
      (_) => _scheduleAndroidRefresh(),
      onError: (_, __) => _scheduleAndroidWatcherRestart(),
      onDone: _scheduleAndroidWatcherRestart,
      cancelOnError: true,
    );
  }

  Future<Device> _mapIosDeviceInfo(IosDeviceInfo info) async {
    if (!info.isAvailable) {
      return Device.ios(info.deviceId, info.status);
    }

    return Device.ios(
      info.deviceId,
      info.status,
      name: _firstNonEmpty(info.deviceName, info.productName),
      model: await _resolveIosModel(info),
    );
  }

  Future<String?> _resolveIosModel(IosDeviceInfo info) async {
    final productType = info.productType;
    if (productType != null && productType.trim().isNotEmpty) {
      final normalizedProductType = productType.trim();
      final human = await getAppleDeviceName(normalizedProductType);
      return human ?? normalizedProductType;
    }

    return _firstNonEmpty(info.hardwareModel, null);
  }

  String? _firstNonEmpty(String? first, String? second) {
    if (first != null && first.trim().isNotEmpty) {
      return first.trim();
    }
    if (second != null && second.trim().isNotEmpty) {
      return second.trim();
    }
    return null;
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

class _CachedAndroidDeviceDescription {
  const _CachedAndroidDeviceDescription({this.brand, this.model, this.name});

  final String? brand;
  final String? model;
  final String? name;

  Device applyTo(Device device) {
    return device.copyWith(
      brand: brand ?? device.brand,
      model: model ?? device.model,
      name: name ?? device.name,
    );
  }
}

class _CachedIosDeviceDescription {
  const _CachedIosDeviceDescription({this.name, this.model});

  final String? name;
  final String? model;

  Device toIosDevice(String deviceId) {
    return Device.ios(
      deviceId,
      'device',
      name: name,
      model: model,
      connectionState: DeviceConnectionState.connected,
    );
  }
}
