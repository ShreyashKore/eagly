import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/device.dart';
import '../data/log_entry.dart';
import '../utils/adb_path.dart';

enum AdbMdnsServiceType { connect, pairing, unknown }

class AdbMdnsService {
  const AdbMdnsService({
    required this.name,
    required this.type,
    required this.host,
    required this.port,
  });

  final String name;
  final AdbMdnsServiceType type;
  final String host;
  final int port;

  String get address => '$host:$port';

  String get typeLabel => switch (type) {
    AdbMdnsServiceType.connect => 'Connect',
    AdbMdnsServiceType.pairing => 'Pairing',
    AdbMdnsServiceType.unknown => 'Unknown',
  };
}

class AdbMdnsDiscoveryResult {
  const AdbMdnsDiscoveryResult({this.services = const [], this.error});

  final List<AdbMdnsService> services;
  final String? error;

  bool get isSuccess => error == null;

  factory AdbMdnsDiscoveryResult.success({
    required List<AdbMdnsService> services,
  }) {
    return AdbMdnsDiscoveryResult(services: services);
  }

  factory AdbMdnsDiscoveryResult.failure({required String error}) {
    return AdbMdnsDiscoveryResult(error: error);
  }
}

class AdbCommandResult {
  const AdbCommandResult({this.message, this.error});

  final String? message;
  final String? error;

  bool get isSuccess => error == null;

  factory AdbCommandResult.success({required String message}) {
    return AdbCommandResult(message: message);
  }

  factory AdbCommandResult.failure({required String error}) {
    return AdbCommandResult(error: error);
  }
}

class AdbService {
  final String adbPath;
  final Map<String, String> _pidToPackageCache = {};
  Timer? _cacheRefreshTimer;
  Process? _activeLogcatProcess;
  String? _activeDeviceId;

  AdbService({String? adbPath})
    : adbPath = adbPath ?? resolveBundledAdbPath() ?? 'adb';

  /// Fetches the list of connected devices
  Future<List<Device>> getDevices() async {
    final result = await Process.run(adbPath, ['devices', '-l']);
    final lines = (result.stdout as String).split('\n');

    final deviceList = <Device>[];

    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;

      // Parse output format: ID status usb:X-Y product:PRODUCT model:MODEL device:DEVICE transport_id:N
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;

      final deviceId = parts[0];
      final status = parts[1];

      // Parse optional attributes
      String? model;
      String? product;

      for (int i = 2; i < parts.length; i++) {
        if (parts[i].startsWith('model:')) {
          model = parts[i].substring('model:'.length);
        } else if (parts[i].startsWith('product:')) {
          product = parts[i].substring('product:'.length);
        }
      }

      // Use product as name if available
      deviceList.add(Device(deviceId, status, model: model, name: product));
    }

    return deviceList;
  }

  Future<AdbMdnsDiscoveryResult> discoverMdnsServices() async {
    try {
      final result = await Process.run(adbPath, ['mdns', 'services']);
      if (result.exitCode != 0) {
        return AdbMdnsDiscoveryResult.failure(
          error: _describeCommandFailure(
            'Failed to discover wireless ADB services.',
            result,
          ),
        );
      }

      final services = <AdbMdnsService>[];
      final output = (result.stdout as String).trim();

      for (final rawLine in const LineSplitter().convert(output)) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;

        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 3) continue;

        final endpoint = parts[2];
        final separatorIndex = endpoint.lastIndexOf(':');
        if (separatorIndex <= 0 || separatorIndex == endpoint.length - 1) {
          continue;
        }

        final port = int.tryParse(endpoint.substring(separatorIndex + 1));
        if (port == null) continue;

        services.add(
          AdbMdnsService(
            name: parts[0],
            type: _parseMdnsServiceType(parts[1]),
            host: endpoint.substring(0, separatorIndex),
            port: port,
          ),
        );
      }

      services.sort((left, right) {
        final typeOrder = left.type.index.compareTo(right.type.index);
        if (typeOrder != 0) return typeOrder;
        final hostOrder = left.host.compareTo(right.host);
        if (hostOrder != 0) return hostOrder;
        return left.port.compareTo(right.port);
      });

      return AdbMdnsDiscoveryResult.success(services: services);
    } catch (error) {
      return AdbMdnsDiscoveryResult.failure(
        error:
            'Failed to discover wireless ADB services: ${_describeError(error)}',
      );
    }
  }

  Future<AdbCommandResult> pairDevice({
    required String address,
    required String pairingCode,
  }) async {
    try {
      final result = await Process.run(adbPath, ['pair', address, pairingCode]);
      if (result.exitCode != 0) {
        return AdbCommandResult.failure(
          error: _describeCommandFailure(
            'Failed to pair with $address.',
            result,
          ),
        );
      }

      final message = _combinedProcessOutput(result);
      return AdbCommandResult.success(
        message: message.isEmpty
            ? 'Successfully paired with $address.'
            : message,
      );
    } catch (error) {
      return AdbCommandResult.failure(
        error: 'Failed to pair with $address: ${_describeError(error)}',
      );
    }
  }

  Future<AdbCommandResult> connectDevice(String address) async {
    try {
      final result = await Process.run(adbPath, ['connect', address]);
      final output = _combinedProcessOutput(result);
      final normalizedOutput = output.toLowerCase();
      final failed =
          result.exitCode != 0 || normalizedOutput.contains('failed');

      if (failed) {
        return AdbCommandResult.failure(
          error: _describeCommandFailure(
            'Failed to connect to $address.',
            result,
          ),
        );
      }

      return AdbCommandResult.success(
        message: output.isEmpty ? 'Connected to $address.' : output,
      );
    } catch (error) {
      return AdbCommandResult.failure(
        error: 'Failed to connect to $address: ${_describeError(error)}',
      );
    }
  }

  /// Refresh the PID to package name mapping
  Future<void> refreshPidToPackageMap(String deviceId) async {
    try {
      final result = await Process.run(adbPath, [
        '-s',
        deviceId,
        'shell',
        'ps',
        '-A',
      ]);

      final lines = (result.stdout as String).split('\n');
      _pidToPackageCache.clear();

      for (final line in lines.skip(1)) {
        if (line.trim().isEmpty) continue;

        // ps output format varies, but typically: USER PID PPID VSZ RSS WCHAN ADDR S NAME
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 9) {
          final pid = parts[1];
          final packageName = parts[8];
          _pidToPackageCache[pid] = packageName;
        }
      }
    } catch (_) {
      // Ignore PID/package refresh failures so log streaming can continue.
    }
  }

  /// Get package name from PID
  String? getPackageNameFromPid(String pid) {
    return _pidToPackageCache[pid];
  }

  /// Starts logcat for a specific device and returns a stream of log entries
  Stream<LogEntry> startLogcat(String deviceId) async* {
    await stopActiveLogcat();

    // Initial refresh of PID to package mapping
    await refreshPidToPackageMap(deviceId);

    // Refresh the cache every 5 seconds
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      refreshPidToPackageMap(deviceId);
    });

    final process = await Process.start(adbPath, [
      '-s',
      deviceId,
      'logcat',
      '-v',
      'threadtime',
    ]);
    _activeLogcatProcess = process;
    _activeDeviceId = deviceId;

    try {
      await for (final line
          in process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final parsed = LogEntry.parse(line);
        if (parsed != null) {
          parsed.packageName = getPackageNameFromPid(parsed.pid);
          yield parsed;
        }
      }
    } finally {
      if (identical(_activeLogcatProcess, process)) {
        _activeLogcatProcess = null;
        _activeDeviceId = null;
      }
      _cacheRefreshTimer?.cancel();
      _cacheRefreshTimer = null;
      if (process.kill(ProcessSignal.sigterm)) {
        try {
          await process.exitCode.timeout(const Duration(seconds: 1));
        } catch (_) {}
      }
    }
  }

  Future<void> stopActiveLogcat() async {
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = null;

    final process = _activeLogcatProcess;
    _activeLogcatProcess = null;
    _activeDeviceId = null;

    if (process == null) return;
    if (process.kill(ProcessSignal.sigterm)) {
      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
  }

  /// Stops logcat for a device (by killing the process)
  Future<void> stopLogcat(String deviceId) async {
    if (_activeDeviceId == deviceId) {
      await stopActiveLogcat();
      return;
    }

    await Process.run(adbPath, ['-s', deviceId, 'shell', 'pkill', 'logcat']);
  }

  /// Clears the logcat buffer on the device
  Future<void> clearLogcat(String deviceId) async {
    await Process.run(adbPath, ['-s', deviceId, 'logcat', '-c']);
  }

  Future<void> dispose() => stopActiveLogcat();

  AdbMdnsServiceType _parseMdnsServiceType(String rawValue) {
    return switch (rawValue.trim()) {
      '_adb-tls-connect._tcp' => AdbMdnsServiceType.connect,
      '_adb-tls-pairing._tcp' => AdbMdnsServiceType.pairing,
      _ => AdbMdnsServiceType.unknown,
    };
  }

  String _combinedProcessOutput(ProcessResult result) {
    final stdout = (result.stdout as String).trim();
    final stderr = (result.stderr as String).trim();

    if (stdout.isEmpty) return stderr;
    if (stderr.isEmpty) return stdout;
    return '$stdout\n$stderr';
  }

  String _describeCommandFailure(String fallback, ProcessResult result) {
    final output = _combinedProcessOutput(result);
    if (output.isNotEmpty) {
      return output;
    }
    return '$fallback (exit code ${result.exitCode}).';
  }

  String _describeError(Object error) {
    final message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }
}
