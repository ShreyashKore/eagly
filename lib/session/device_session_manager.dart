import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../data/device.dart';
import '../features/logs/services/log_file_service.dart';
import '../services/devices_repository.dart';
import '../services/device_session_repository.dart';
import 'device_session_controller.dart';

typedef DeviceSessionServiceFactory =
    DeviceSessionRepository Function(Device device);

/// App-level coordinator. Listens to the [DevicesRepository] and maintains one
/// [DeviceSessionController] per detected device, the tab order, and the
/// currently selected device (null = Home).
///
/// Disconnected devices keep their session (so logs survive and the device can
/// reconnect). Closing a disconnected tab dismisses it permanently until the
/// device reconnects.
class DeviceSessionManager extends ChangeNotifier {
  DeviceSessionManager({
    DevicesRepository? repository,
    DeviceSessionServiceFactory? serviceFactory,
  }) : _repository = repository ?? DevicesRepository.instance,
       _serviceFactory = serviceFactory {
    _repository.addListener(_sync);
    unawaited(_repository.ensureStarted(refreshImmediately: true));
    _sync();
  }

  final DevicesRepository _repository;
  final DeviceSessionServiceFactory? _serviceFactory;

  final Map<String, DeviceSessionController> _sessions = {};
  final List<String> _order = [];
  final Set<String> _dismissed = {};
  DeviceSessionController? _importedWorkspace;
  String? _selectedId;
  bool _autoSelectedOnce = false;
  bool _disposed = false;

  DevicesRepository get repository => _repository;

  List<DeviceSessionController> get sessions =>
      List.unmodifiable([for (final id in _order) _sessions[id]!]);

  bool get hasSessions => _order.isNotEmpty;
  bool get isHome => _selectedId == null;
  String? get selectedId => _selectedId;
  DeviceSessionController? get selected =>
      _selectedId == null ? null : _sessions[_selectedId];

  bool get isLoadingDevices => _repository.isLoading;
  bool get hasAttemptedDeviceLoad => _repository.hasAttemptedLoad;
  bool get iosSupportUnavailable => _repository.iosSupportUnavailable;
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
    if (identical(controller, _importedWorkspace)) {
      // Drop the pointer so the next import builds a fresh workspace.
      _importedWorkspace = null;
    }
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

  /// Opens a log file (via picker, or [path] to re-open a recent file) without
  /// needing a connected device. Imported files are hosted in a single synthetic
  /// "Imported Logs" workspace tab; each file becomes a sub-tab inside it.
  /// Returns the [LogImportResult] (may be cancelled or fail).
  Future<LogImportResult> importLog({String? path}) async {
    final result = await LogFileService.importLogs(path: path);
    if (_disposed || !result.isSuccess) return result;

    final workspace = _ensureImportedWorkspace();
    workspace.logSessionManager.addImportedEntries(
      result.logs!,
      result.fileName!,
    );
    select(workspace.id);
    return result;
  }

  DeviceSessionController _ensureImportedWorkspace() {
    final existing = _importedWorkspace;
    if (existing != null) return existing;

    final device = Device.android(
      AppConstants.importedWorkspaceId,
      'offline',
      name: AppConstants.importedWorkspaceLabel,
      connectionState: DeviceConnectionState.disconnected,
    );
    final workspace = DeviceSessionController.importedWorkspace(
      device: device,
      service: _serviceFactory?.call(device),
    );
    _importedWorkspace = workspace;
    _dismissed.remove(device.id);
    _sessions[device.id] = workspace;
    _order.add(device.id);
    workspace.activate();
    return workspace;
  }

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
