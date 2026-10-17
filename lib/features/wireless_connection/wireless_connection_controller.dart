import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../data/device.dart';
import 'data/wireless_debug_models.dart';
import '../../services/devices_repository.dart';

class const WirelessPairResult({
  required this.paired,
  this.autoConnected = false,
  this.connectAddresses = const [],
  this.message,
  this.error,
}) {
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

/// Holds the credentials encoded in a wireless debugging pairing QR code.
///
/// Both fields are generated locally — the device contributes nothing to the
/// code, so building one is pure computation with no I/O and no failure mode.
/// The Android device scans [payload] and then advertises an mDNS pairing
/// service whose name equals [serviceName]; the scan loop matches on that name
/// and pairs against that service using [password] as the pairing code.
///
/// There is no server side and therefore no expiry: a code stays valid until it
/// is used. It is single-use, though — regenerate after a pair attempt.
class const WirelessQrPairingSession({
  required this.serviceName,
  required this.password,
}) {
  final String serviceName;
  final String password;

  /// The `WIFI:T:ADB;...` string rendered as a QR code for the device to scan.
  String get payload => 'WIFI:T:ADB;S:$serviceName;P:$password;;';
}

/// Drives the wireless ADB dialog: one QR pairing session plus one background
/// mDNS scan that serves both the nearby device list and QR scan detection.
///
/// The single loop is deliberate. Pairing by QR and listing nearby devices both
/// need the same `adb mdns services` snapshot, and running them as two
/// independent operations meant one starved the other — opening the QR pane
/// while a discovery was in flight left the code ungenerated for ~10 s. Nothing
/// here should reintroduce a second poller or widen [isWirelessBusy].
class WirelessConnectionController({
  required this._devicesRepository,
  required this._onDevicesApplied,
  required this._onActivateDevice,
  this.isDeviceSelectedInAnotherTab,
  this.selectedDeviceIdProvider,
  this.isRunningProvider,
  this._onQrPairingCompleted,
}) extends ChangeNotifier {
  final DevicesRepository _devicesRepository;
  final Future<void> Function(List<Device> devices) _onDevicesApplied;
  final Future<void> Function(Device device) _onActivateDevice;
  final bool Function(String deviceId)? isDeviceSelectedInAnotherTab;
  final String? Function()? selectedDeviceIdProvider;
  final bool Function()? isRunningProvider;

  /// Called when a QR code was scanned and the resulting pair (plus automatic
  /// connect) attempt finished — the scan loop, not the UI, drives that flow.
  final void Function(WirelessPairResult result)? _onQrPairingCompleted;

  var _pairingWireless = false;
  var _connectingWireless = false;
  var _hasAttemptedWirelessDiscovery = false;
  var _wirelessServices = <WirelessDebugService>[];
  String? _wirelessMessage;
  String? _wirelessError;
  var _disposed = false;
  WirelessQrPairingSession? _qrSession;
  var _scanning = false;
  var _scanGeneration = 0;

  /// How often the background scan re-probes mDNS while the pair pane is open.
  @visibleForTesting
  static Duration scanInterval = const Duration(milliseconds: 1200);

  bool get isPairingWireless => _pairingWireless;
  bool get isConnectingWireless => _connectingWireless;

  /// Whether the background mDNS scan is running. It is passive: it never
  /// blocks pairing, connecting or QR generation.
  bool get isScanning => _scanning;
  bool get isWaitingForQrScan =>
      _qrSession != null && _scanning && !isWirelessBusy;
  WirelessQrPairingSession? get qrSession => _qrSession;

  /// True while an action that must not overlap another one is in flight.
  ///
  /// Deliberately *excludes* the background scan: the scan is passive and must
  /// never block QR generation, pairing or connecting. Widening this to cover
  /// scanning is exactly the starvation bug this design removed.
  bool get isWirelessBusy => _pairingWireless || _connectingWireless;
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
    if (_connectingWireless) {
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
      final result = await _devicesRepository.pairWirelessAndroidDevice(
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

  // ── Pair pane: QR code + background mDNS scan ───────────────────────────

  /// Opens the pairing pane: publishes a QR code and starts the background
  /// scan that both refreshes the nearby list and watches for the code being
  /// scanned.
  ///
  /// The code is generated locally, so it is on screen from the first frame —
  /// it never waits on an mDNS probe. Keep it that way: anything that makes
  /// code generation await I/O puts the ~10 s discovery stall back in the UI.
  void beginPairing() {
    if (_qrSession == null) {
      regenerateQrCode();
    }
    startScanning();
  }

  /// Publishes a fresh single-use pairing code. Cheap and synchronous.
  void regenerateQrCode() {
    _qrSession = WirelessQrPairingSession(
      serviceName: _generateQrServiceName(),
      password: _generateQrPassword(),
    );
    _notify();
  }

  /// Starts the background mDNS scan. Safe to call when already scanning.
  ///
  /// [_scanGeneration] is the cancellation token: a loop parked in its interval
  /// delay cannot be interrupted, so it re-checks the generation on waking and
  /// returns if it has been superseded.
  void startScanning() {
    if (_scanning || _disposed) return;
    _scanning = true;
    _scanGeneration++;
    _notify();
    unawaited(_runScanLoop(_scanGeneration));
  }

  void stopScanning() {
    if (!_scanning) return;
    _scanning = false;
    _scanGeneration++;
    _notify();
  }

  void cancelAllOperations() {
    stopScanning();
  }

  /// Polls mDNS until stopped. Each pass refreshes [wirelessServices] and, when
  /// a pairing service matching the published QR session appears, hands off to
  /// [pairWirelessDevice]. Passes are skipped while another action holds adb.
  Future<void> _runScanLoop(int generation) async {
    bool isStale() => _disposed || !_scanning || generation != _scanGeneration;

    while (!isStale()) {
      // Skipped, not queued: pairing/connecting already hold adb, and a probe
      // running alongside `adb pair` is both wasteful and flaky.
      if (!isWirelessBusy) {
        // `retry: false` is essential — the default retries for ~10 s before
        // returning empty, which would make this loop tick once per 10 s and
        // hold adb the whole time. We do the pacing ourselves.
        final result = await _devicesRepository.discoverMdnsServices(
          retry: false,
        );
        if (isStale()) return;

        if (!result.isSuccess) {
          // adb itself failed; retrying on a timer would only repeat the error.
          _wirelessError = result.error;
          _wirelessMessage = null;
          stopScanning();
          return;
        }

        // The scan repeats every second or so; only wake the UI on a change.
        final changed =
            !_hasAttemptedWirelessDiscovery ||
            !_sameServices(_wirelessServices, result.services);
        _wirelessServices = result.services;
        _hasAttemptedWirelessDiscovery = true;
        if (changed) _notify();

        // The device only starts advertising this name *after* it scans our
        // code, so a name match is the scan signal — there is no callback.
        final session = _qrSession;
        final scannedService = session == null
            ? null
            : result.services.firstWhereOrNull(
                (service) =>
                    service.type == WirelessDebugServiceType.pairing &&
                    service.name == session.serviceName,
              );
        if (session != null && scannedService != null) {
          await _completeQrPairing(session, scannedService);
          if (isStale()) return;
        }
      }

      await Future<void>.delayed(scanInterval);
    }
  }

  bool _sameServices(
    List<WirelessDebugService> left,
    List<WirelessDebugService> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].name != right[index].name ||
          left[index].type != right[index].type ||
          left[index].address != right[index].address) {
        return false;
      }
    }
    return true;
  }

  /// Runs the regular pairing flow with the credentials the device just read
  /// off the QR code. The code is single-use, so a fresh one is published
  /// unless pairing carried all the way through to a connected device.
  ///
  /// The new code carries a new service name, so the device's still-advertised
  /// pairing service cannot re-trigger this on the next pass.
  Future<void> _completeQrPairing(
    WirelessQrPairingSession session,
    WirelessDebugService pairingService,
  ) async {
    _qrSession = null;
    _notify();

    final result = await pairWirelessDevice(
      address: pairingService.address,
      pairingCode: session.password,
    );
    if (_disposed) return;

    if (!result.autoConnected) {
      regenerateQrCode();
    }
    _onQrPairingCompleted?.call(result);
  }

  String _generateQrServiceName() => 'eagly-${_randomAlphaNumeric(10)}';

  String _generateQrPassword() => _randomAlphaNumeric(12);

  String _randomAlphaNumeric(int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
      ),
    );
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
    if (_pairingWireless) {
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
      await _devicesRepository.refreshDevices(force: true);
      if (_disposed) return null;

      final fetchedDevices = _devicesRepository.devices;
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
        final result = await _devicesRepository.connectWirelessAndroidDevice(
          candidate,
        );
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

  Future<WirelessServiceDiscoveryResult>
  _refreshWirelessServicesSnapshot() async {
    _hasAttemptedWirelessDiscovery = true;
    final result = await _devicesRepository.discoverMdnsServices();
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
    await _devicesRepository.refreshDevices(force: true);
    if (_disposed) return null;

    final fetchedDevices = _devicesRepository.devices;
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
    _scanning = false;
    _scanGeneration++;
    super.dispose();
  }
}
