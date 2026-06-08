import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/device.dart';
import '../services/device_repository.dart';
import '../services/device_session_service.dart';
import 'device_session_controller.dart';

typedef DeviceSessionServiceFactory =
    DeviceSessionService Function(Device device);

/// App-level coordinator. Listens to the [DeviceRepository] and maintains one
/// [DeviceSessionController] per detected device, the tab order, and the
/// currently selected device (null = Home).
///
/// Disconnected devices keep their session (so logs survive and the device can
/// reconnect). Closing a disconnected tab dismisses it permanently until the
/// device reconnects.
class DeviceSessionManager extends ChangeNotifier {
  DeviceSessionManager({
    DeviceRepository? repository,
    DeviceSessionServiceFactory? serviceFactory,
  }) : _repository = repository ?? DeviceRepository.instance,
       _serviceFactory = serviceFactory {
    _repository.addListener(_sync);
    unawaited(_repository.ensureStarted(refreshImmediately: true));
    _sync();
  }

  final DeviceRepository _repository;
  final DeviceSessionServiceFactory? _serviceFactory;

  final Map<String, DeviceSessionController> _sessions = {};
  final List<String> _order = [];
  final Set<String> _dismissed = {};
  String? _selectedId;
  bool _autoSelectedOnce = false;
  bool _disposed = false;

  DeviceRepository get repository => _repository;

  List<DeviceSessionController> get sessions => List.unmodifiable([
    for (final id in _order) _sessions[id]!,
  ]);

  bool get hasSessions => _order.isNotEmpty;
  String? get selectedId => _selectedId;
  bool get isHome => _selectedId == null;
  DeviceSessionController? get selected =>
      _selectedId == null ? null : _sessions[_selectedId];

  bool get isLoadingDevices => _repository.isLoading;
  bool get hasAttemptedDeviceLoad => _repository.hasAttemptedLoad;
  List<Device> get devices => _repository.devices;

  void _sync() {
    if (_disposed) return;

    for (final device in _repository.devices) {
      final id = device.id;
      if (device.isConnected) {
        _dismissed.remove(id);
      }
      if (_dismissed.contains(id)) continue;

      final existing = _sessions[id];
      if (existing == null) {
        _sessions[id] = DeviceSessionController(
          device: device,
          service: _serviceFactory?.call(device),
        );
        _order.add(id);
      } else {
        existing.updateDevice(device);
      }
    }

    _maybeAutoSelect();
    if (!_disposed) notifyListeners();
  }

  /// Auto-selects the single connected device once on first load (mirrors the
  /// old "auto-start single device" behavior). Disabled after any user action.
  void _maybeAutoSelect() {
    if (_autoSelectedOnce || _selectedId != null) return;
    final connected = _order
        .map((id) => _sessions[id]!)
        .where((session) => session.isConnected)
        .toList(growable: false);
    if (connected.length == 1) {
      _autoSelectedOnce = true;
      _selectAndActivate(connected.single.id);
    }
  }

  void _selectAndActivate(String id) {
    _selectedId = id;
    _sessions[id]?.activate();
  }

  void select(String id) {
    if (!_sessions.containsKey(id)) return;
    _autoSelectedOnce = true;
    _selectAndActivate(id);
    notifyListeners();
  }

  void goHome() {
    _autoSelectedOnce = true;
    if (_selectedId == null) return;
    _selectedId = null;
    notifyListeners();
  }

  /// Whether the device's tab can be closed (only disconnected devices).
  bool canClose(String id) {
    final session = _sessions[id];
    return session != null && !session.isConnected;
  }

  void close(String id) {
    final controller = _sessions[id];
    if (controller == null || controller.isConnected) return;
    _sessions.remove(id);
    _order.remove(id);
    _dismissed.add(id);
    controller.dispose();
    if (_selectedId == id) {
      _selectedId = _order.isNotEmpty ? _order.last : null;
      if (_selectedId != null) {
        _sessions[_selectedId]!.activate();
      }
    }
    notifyListeners();
  }

  Future<void> refreshDevices() =>
      _repository.refreshDevices(force: true, showLoading: true);

  @override
  void dispose() {
    _disposed = true;
    _repository.removeListener(_sync);
    for (final controller in _sessions.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
