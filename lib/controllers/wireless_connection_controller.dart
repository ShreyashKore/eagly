import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../data/device.dart';
import '../data/wireless_debug_models.dart';
import '../services/device_repository.dart';
import '../services/device_session_service.dart';

class WirelessPairResult {
  const WirelessPairResult({
    required this.paired,
    this.autoConnected = false,
    this.connectAddresses = const [],
    this.message,
    this.error,
  });

  final bool paired;
  final bool autoConnected;
  final List<String> connectAddresses;
  final String? message;
  final String? error;

  bool get isSuccess => error == null;
  bool get shouldShowConnectAction =>
      paired && !autoConnected && connectAddresses.isNotEmpty;

  factory WirelessPairResult.failure({required String error}) {
    return WirelessPairResult(paired: false, error: error);
  }

  factory WirelessPairResult.paired({
    String? message,
    List<String> connectAddresses = const [],
  }) {
    return WirelessPairResult(
      paired: true,
      message: message,
      connectAddresses: connectAddresses,
    );
  }

  factory WirelessPairResult.autoConnected({required String message}) {
    return WirelessPairResult(
      paired: true,
      autoConnected: true,
      message: message,
    );
  }
}

class WirelessConnectionController extends ChangeNotifier {
  WirelessConnectionController({
    required DeviceRepository deviceRepository,
    required DeviceSessionService deviceSessionService,
    required Future<void> Function(List<Device> devices) onDevicesApplied,
    required Future<void> Function(Device device) onActivateDevice,
    this.isDeviceSelectedInAnotherTab,
    this.selectedDeviceIdProvider,
    this.isRunningProvider,
  }) : _deviceRepository = deviceRepository,
       _deviceSessionService = deviceSessionService,
       _onDevicesApplied = onDevicesApplied,
       _onActivateDevice = onActivateDevice;

  final DeviceRepository _deviceRepository;
  final DeviceSessionService _deviceSessionService;
  final Future<void> Function(List<Device> devices) _onDevicesApplied;
  final Future<void> Function(Device device) _onActivateDevice;
  final bool Function(String deviceId)? isDeviceSelectedInAnotherTab;
  final String? Function()? selectedDeviceIdProvider;
  final bool Function()? isRunningProvider;

  var _discoveringWireless = false;
  var _pairingWireless = false;
  var _connectingWireless = false;
  var _hasAttemptedWirelessDiscovery = false;
  var _wirelessServices = <WirelessDebugService>[];
  String? _wirelessMessage;
  String? _wirelessError;
  var _disposed = false;

  bool get isDiscoveringWireless => _discoveringWireless;
  bool get isPairingWireless => _pairingWireless;
  bool get isConnectingWireless => _connectingWireless;
  bool get isWirelessBusy =>
      _discoveringWireless || _pairingWireless || _connectingWireless;
  bool get hasAttemptedWirelessDiscovery => _hasAttemptedWirelessDiscovery;
  List<WirelessDebugService> get wirelessServices =>
      List.unmodifiable(_wirelessServices);
  List<WirelessDebugService> get wirelessPairingServices => _wirelessServices
      .where((service) => service.type == WirelessDebugServiceType.pairing)
      .toList(growable: false);
  List<WirelessDebugService> get wirelessConnectServices => _wirelessServices
      .where((service) => service.type == WirelessDebugServiceType.connect)
      .toList(growable: false);
  String? get wirelessMessage => _wirelessMessage;
  String? get wirelessError => _wirelessError;
  String? get suggestedWirelessPairingAddress =>
      wirelessPairingServices.firstOrNull?.address;
  String? get suggestedWirelessConnectAddress =>
      wirelessConnectServices.firstOrNull?.address;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<WirelessServiceDiscoveryResult> discoverWirelessServices() async {
    if (_pairingWireless || _connectingWireless) {
      const error =
          'Finish the current wireless ADB action before starting another one.';
      _wirelessError = error;
      _wirelessMessage = null;
      _notify();
      return WirelessServiceDiscoveryResult.failure(error: error);
    }

    _discoveringWireless = true;
    _hasAttemptedWirelessDiscovery = true;
    _wirelessMessage = null;
    _wirelessError = null;
    _notify();

    try {
      final result = await _deviceRepository.discoverMdnsServices();
      if (_disposed) return result;

      if (result.isSuccess) {
        _wirelessServices = result.services;
        _wirelessError = null;
        _wirelessMessage = result.services.isEmpty
            ? 'No wireless ADB services found on the local network.'
            : 'Found ${result.services.length} wireless ADB service${result.services.length == 1 ? '' : 's'}.';
      } else {
        _wirelessServices = [];
        _wirelessMessage = null;
        _wirelessError = result.error;
      }

      return result;
    } finally {
      _discoveringWireless = false;
      _notify();
    }
  }

  Future<WirelessPairResult> pairWirelessDevice({
    required String address,
    required String pairingCode,
    Iterable<String> connectAddresses = const [],
  }) async {
    final normalizedAddress = address.trim();
    final normalizedCode = pairingCode.trim();
    if (normalizedAddress.isEmpty) {
      const error = 'Enter a pairing address such as 192.168.0.104:45673.';
      _wirelessError = error;
      _wirelessMessage = null;
      _notify();
      return WirelessPairResult.failure(error: error);
    }
    if (normalizedCode.isEmpty) {
      const error = 'Enter the wireless pairing code shown on the device.';
      _wirelessError = error;
      _wirelessMessage = null;
      _notify();
      return WirelessPairResult.failure(error: error);
    }
    if (_discoveringWireless || _connectingWireless) {
      const error =
          'Finish the current wireless ADB action before pairing a device.';
      _wirelessError = error;
      _wirelessMessage = null;
      _notify();
      return WirelessPairResult.failure(error: error);
    }

    _pairingWireless = true;
    _wirelessMessage = null;
    _wirelessError = null;
    _notify();

    try {
      final result = await _deviceSessionService.pairDevice(
        address: normalizedAddress,
        pairingCode: normalizedCode,
      );
      if (_disposed) {
        return result.isSuccess
            ? WirelessPairResult.paired(message: result.message)
            : WirelessPairResult.failure(
                error:
                    result.error ?? 'Failed to pair with $normalizedAddress.',
              );
      }

      if (!result.isSuccess) {
        final error = result.error ?? 'Failed to pair with $normalizedAddress.';
        _wirelessMessage = null;
        _wirelessError = error;
        return WirelessPairResult.failure(error: error);
      }

      _pairingWireless = false;
      _notify();

      final resolvedConnectAddresses = await _resolveWirelessConnectAddresses(
        pairingAddress: normalizedAddress,
        candidateAddresses: connectAddresses,
      );
      if (_disposed) {
        return WirelessPairResult.paired(
          message: result.message,
          connectAddresses: resolvedConnectAddresses,
        );
      }

      if (resolvedConnectAddresses.isEmpty) {
        final message =
            '${result.message ?? 'Paired successfully.'} No connect endpoint was discovered automatically.';
        _wirelessMessage = message;
        _wirelessError = null;
        return WirelessPairResult.paired(message: message);
      }

      final connectResult = await _connectWirelessDeviceInternal(
        candidateAddresses: resolvedConnectAddresses,
        host: _wirelessHostFromAddress(normalizedAddress),
        suppressFailureState: true,
      );
      if (_disposed) {
        return connectResult.isSuccess
            ? WirelessPairResult.autoConnected(
                message:
                    connectResult.message ??
                    'Paired and connected successfully.',
              )
            : WirelessPairResult.paired(
                message: connectResult.error,
                connectAddresses: resolvedConnectAddresses,
              );
      }

      if (connectResult.isSuccess) {
        final message =
            connectResult.message ?? 'Paired and connected successfully.';
        _wirelessMessage = message;
        _wirelessError = null;
        return WirelessPairResult.autoConnected(message: message);
      }

      final message =
          '${result.message ?? 'Paired successfully.'} Automatic connection could not be completed. You can retry connect manually.';
      _wirelessMessage = message;
      _wirelessError = null;
      return WirelessPairResult.paired(
        message: message,
        connectAddresses: resolvedConnectAddresses,
      );
    } finally {
      _pairingWireless = false;
      _notify();
    }
  }

  Future<DeviceCommandResult> connectWirelessDevice({
    String? address,
    Iterable<String> candidateAddresses = const [],
  }) async {
    final normalizedAddresses = <String>[];
    void addAddress(String raw) {
      final normalized = raw.trim();
      if (normalized.isEmpty || normalizedAddresses.contains(normalized)) {
        return;
      }
      normalizedAddresses.add(normalized);
    }

    if (address != null) {
      addAddress(address);
    }
    for (final candidate in candidateAddresses) {
      addAddress(candidate);
    }

    if (normalizedAddresses.isEmpty) {
      const error = 'Enter a connect address such as 192.168.0.117:37251.';
      _wirelessError = error;
      _wirelessMessage = null;
      _notify();
      return DeviceCommandResult.failure(error: error);
    }
    if (_discoveringWireless || _pairingWireless) {
      const error =
          'Finish the current wireless ADB action before connecting a device.';
      _wirelessError = error;
      _wirelessMessage = null;
      _notify();
      return DeviceCommandResult.failure(error: error);
    }

    return _connectWirelessDeviceInternal(
      candidateAddresses: normalizedAddresses,
      host: _wirelessHostFromAddress(normalizedAddresses.first),
    );
  }

  Future<Device?> _awaitWirelessDevice({
    String? exactAddress,
    String? host,
  }) async {
    const attempts = 5;
    for (var attempt = 0; attempt < attempts; attempt++) {
      await _deviceRepository.refreshDevices(force: true);
      if (_disposed) return null;

      final fetchedDevices = _deviceRepository.devices;
      await _onDevicesApplied(fetchedDevices);
      final matchedDevice = fetchedDevices.firstWhereOrNull(
        (device) => _matchesConnectedWirelessDevice(
          device,
          exactAddress: exactAddress,
          host: host,
        ),
      );
      if (matchedDevice != null) {
        return matchedDevice;
      }

      if (attempt < attempts - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    return null;
  }

  Future<DeviceCommandResult> _connectWirelessDeviceInternal({
    required Iterable<String> candidateAddresses,
    String? host,
    bool suppressFailureState = false,
  }) async {
    final addresses = <String>[];
    for (final candidate in candidateAddresses) {
      final normalized = candidate.trim();
      if (normalized.isEmpty || addresses.contains(normalized)) continue;
      addresses.add(normalized);
    }

    if (addresses.isEmpty) {
      const error = 'Enter a connect address such as 192.168.0.117:37251.';
      if (!suppressFailureState) {
        _wirelessError = error;
        _wirelessMessage = null;
        _notify();
      }
      return DeviceCommandResult.failure(error: error);
    }

    _connectingWireless = true;
    _wirelessMessage = null;
    _wirelessError = null;
    _notify();

    try {
      final existingDevice = await _findConnectedWirelessDevice(
        exactAddresses: addresses,
        host: host,
      );
      if (_disposed) {
        return DeviceCommandResult.success(
          message: 'Using existing wireless connection.',
        );
      }
      if (existingDevice != null) {
        final reusedResult = await _activateConnectedWirelessDevice(
          existingDevice,
          prefixMessage: 'Wireless device is already connected.',
        );
        if (!suppressFailureState || reusedResult.isSuccess) {
          _wirelessMessage = reusedResult.message;
          _wirelessError = reusedResult.error;
        }
        return reusedResult;
      }

      final failures = <String>[];
      for (final candidate in addresses) {
        final result = await _deviceSessionService.connectDevice(candidate);
        if (_disposed) {
          return result;
        }

        if (!result.isSuccess) {
          failures.add(result.error ?? 'Failed to connect to $candidate.');
          continue;
        }

        final matchedDevice = await _awaitWirelessDevice(
          exactAddress: candidate,
          host: host,
        );
        if (_disposed) {
          return result;
        }

        if (matchedDevice == null) {
          final message =
              '${result.message ?? 'Connected to $candidate.'} The device has not appeared in the device list yet.';
          if (!suppressFailureState) {
            _wirelessMessage = message;
            _wirelessError = null;
          }
          return DeviceCommandResult.success(message: message);
        }

        final activatedResult = await _activateConnectedWirelessDevice(
          matchedDevice,
          prefixMessage: result.message ?? 'Connected to ${matchedDevice.id}.',
        );
        if (!suppressFailureState || activatedResult.isSuccess) {
          _wirelessMessage = activatedResult.message;
          _wirelessError = activatedResult.error;
        }
        return activatedResult;
      }

      final error = _describeWirelessConnectFailures(addresses, failures);
      if (!suppressFailureState) {
        _wirelessMessage = null;
        _wirelessError = error;
      }
      return DeviceCommandResult.failure(error: error);
    } finally {
      _connectingWireless = false;
      _notify();
    }
  }

  Future<List<String>> _resolveWirelessConnectAddresses({
    required String pairingAddress,
    Iterable<String> candidateAddresses = const [],
  }) async {
    final providedAddresses = <String>[];
    for (final candidate in candidateAddresses) {
      final normalized = candidate.trim();
      if (normalized.isEmpty || providedAddresses.contains(normalized)) {
        continue;
      }
      providedAddresses.add(normalized);
    }
    if (providedAddresses.isNotEmpty) {
      return providedAddresses;
    }

    final host = _wirelessHostFromAddress(pairingAddress);
    final cachedAddresses = _pickWirelessConnectAddresses(
      services: _wirelessServices,
      host: host,
    );
    if (cachedAddresses.isNotEmpty) {
      return cachedAddresses;
    }

    final refreshedDiscovery = await _refreshWirelessServicesSnapshot();
    if (_disposed || !refreshedDiscovery.isSuccess) {
      return cachedAddresses;
    }

    return _pickWirelessConnectAddresses(
      services: refreshedDiscovery.services,
      host: host,
    );
  }

  Future<WirelessServiceDiscoveryResult> _refreshWirelessServicesSnapshot() async {
    _hasAttemptedWirelessDiscovery = true;
    final result = await _deviceRepository.discoverMdnsServices();
    if (_disposed) return result;
    if (result.isSuccess) {
      _wirelessServices = result.services;
      _notify();
    }
    return result;
  }

  List<String> _pickWirelessConnectAddresses({
    required List<WirelessDebugService> services,
    required String? host,
  }) {
    final addresses = <String>[];
    final connectServices = services.where(
      (service) => service.type == WirelessDebugServiceType.connect,
    );

    for (final service in connectServices) {
      if (host != null && service.host != host) continue;
      if (!addresses.contains(service.address)) {
        addresses.add(service.address);
      }
    }

    if (addresses.isNotEmpty || host != null) {
      return addresses;
    }

    final allConnectAddresses = connectServices
        .map((service) => service.address)
        .toSet()
        .toList(growable: false);
    return allConnectAddresses.length == 1 ? allConnectAddresses : const [];
  }

  Future<Device?> _findConnectedWirelessDevice({
    required List<String> exactAddresses,
    required String? host,
  }) async {
    await _deviceRepository.refreshDevices(force: true);
    if (_disposed) return null;

    final fetchedDevices = _deviceRepository.devices;
    await _onDevicesApplied(fetchedDevices);
    return fetchedDevices.firstWhereOrNull(
      (device) => _matchesConnectedWirelessDevice(
        device,
        exactAddresses: exactAddresses,
        host: host,
      ),
    );
  }

  bool _matchesConnectedWirelessDevice(
    Device device, {
    String? exactAddress,
    List<String> exactAddresses = const [],
    String? host,
  }) {
    if (!device.isConnected || device.status != 'device') {
      return false;
    }
    if (exactAddress != null && device.id == exactAddress) {
      return true;
    }
    if (exactAddresses.contains(device.id)) {
      return true;
    }
    final deviceHost = _wirelessHostFromAddress(device.id);
    return host != null && deviceHost == host;
  }

  Future<DeviceCommandResult> _activateConnectedWirelessDevice(
    Device matchedDevice, {
    String? prefixMessage,
  }) async {
    final selectedDeviceId = selectedDeviceIdProvider?.call();
    if ((isDeviceSelectedInAnotherTab?.call(matchedDevice.id) ?? false) &&
        selectedDeviceId != matchedDevice.id) {
      final message =
          '${prefixMessage ?? 'Wireless device is already connected.'} The device is already open in another tab.';
      return DeviceCommandResult.success(message: message);
    }

    await _onActivateDevice(matchedDevice);
    if (_disposed) {
      return DeviceCommandResult.success(
        message: prefixMessage ?? 'Connected to ${matchedDevice.id}.',
      );
    }

    final isActivatedInTab =
        selectedDeviceIdProvider?.call() == matchedDevice.id &&
        (isRunningProvider?.call() ?? false);
    final message = isActivatedInTab
        ? '${prefixMessage ?? 'Connected to ${matchedDevice.id}.'} Live logs are ready in this tab.'
        : 'Connected to ${matchedDevice.id} and started live logs in this tab.';
    return DeviceCommandResult.success(message: message);
  }

  String _describeWirelessConnectFailures(
    List<String> addresses,
    List<String> failures,
  ) {
    if (addresses.length == 1) {
      return failures.isNotEmpty
          ? failures.last
          : 'Failed to connect to ${addresses.single}.';
    }

    final summary = failures.isNotEmpty
        ? failures.last
        : 'None of the discovered connect ports succeeded.';
    return 'Tried ${addresses.length} connect ports (${addresses.join(', ')}), but none succeeded. $summary';
  }

  String? _wirelessHostFromAddress(String? address) {
    if (address == null) return null;
    final trimmed = address.trim();
    if (trimmed.isEmpty) return null;
    final separatorIndex = trimmed.lastIndexOf(':');
    if (separatorIndex <= 0) return null;
    return trimmed.substring(0, separatorIndex);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

