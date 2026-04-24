import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/device.dart';
import '../data/log_entry.dart';
import '../utils/adb_path.dart';
import 'ios_syslog_parser.dart';

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
  final String ideviceIdPath;
  final String ideviceInfoPath;
  final String ideviceSyslogPath;
  final Map<String, String> _pidToPackageCache = {};
  Timer? _cacheRefreshTimer;
  Process? _activeLogcatProcess;
  String? _activeDeviceId;

  AdbService({
    String? adbPath,
    String? ideviceIdPath,
    String? ideviceInfoPath,
    String? ideviceSyslogPath,
  }) : adbPath = adbPath ?? resolveBundledAdbPath() ?? 'adb',
       ideviceIdPath =
           ideviceIdPath ??
           resolveBundledExecutablePath('idevice_id') ??
           'idevice_id',
       ideviceInfoPath =
           ideviceInfoPath ??
           resolveBundledExecutablePath('ideviceinfo') ??
           'ideviceinfo',
       ideviceSyslogPath =
           ideviceSyslogPath ??
           resolveBundledExecutablePath('idevicesyslog') ??
           'idevicesyslog';

  /// Fetches the list of connected Android and iOS devices.
  Future<List<Device>> getDevices() async {
    final androidDevices = await _getAndroidDevices();
    final iosDevices = await _getIosDevices();
    final devices = [...androidDevices, ...iosDevices];

    devices.sort((left, right) {
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

    return devices;
  }

  Future<List<Device>> _getAndroidDevices() async {
    try {
      final result = await _runTool(adbPath, ['devices', '-l']);
      if (result.exitCode != 0) {
        return const [];
      }

      final lines = (result.stdout as String).split('\n');
      final deviceList = <Device>[];

      for (final line in lines.skip(1)) {
        if (line.trim().isEmpty) continue;

        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 2) continue;

        final deviceId = parts[0];
        final status = parts[1];

        String? model;
        String? product;

        for (var i = 2; i < parts.length; i++) {
          if (parts[i].startsWith('model:')) {
            model = parts[i].substring('model:'.length);
          } else if (parts[i].startsWith('product:')) {
            product = parts[i].substring('product:'.length);
          }
        }

        deviceList.add(
          Device(
            deviceId,
            status,
            model: model,
            name: product,
            platform: DevicePlatform.android,
          ),
        );
      }

      return deviceList;
    } on ProcessException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<List<Device>> _getIosDevices() async {
    try {
      final result = await _runTool(ideviceIdPath, ['-l']);
      if (result.exitCode != 0) {
        return const [];
      }

      final deviceIds = const LineSplitter()
          .convert((result.stdout as String).trim())
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      if (deviceIds.isEmpty) {
        return const [];
      }

      return Future.wait(deviceIds.map(_describeIosDevice));
    } on ProcessException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<Device> _describeIosDevice(String deviceId) async {
    try {
      final result = await _runTool(ideviceInfoPath, ['-u', deviceId]);
      if (result.exitCode != 0) {
        return Device(
          deviceId,
          _describeIosDeviceStatus(result),
          platform: DevicePlatform.ios,
        );
      }

      final info = _parseIdeviceInfoOutput(result.stdout as String);
      return Device(
        deviceId,
        'device',
        name: _firstNonEmpty(info['DeviceName'], info['ProductName']),
        model: _firstNonEmpty(info['ProductType'], info['HardwareModel']),
        platform: DevicePlatform.ios,
      );
    } on ProcessException {
      return Device(deviceId, 'unavailable', platform: DevicePlatform.ios);
    } catch (_) {
      return Device(deviceId, 'unavailable', platform: DevicePlatform.ios);
    }
  }

  Future<AdbMdnsDiscoveryResult> discoverMdnsServices() async {
    try {
      final result = await _runTool(adbPath, ['mdns', 'services']);
      if (result.exitCode != 0) {
        return AdbMdnsDiscoveryResult.failure(
          error: _describeCommandFailure(
            'Failed to discover wireless ADB services.',
            result,
          ),
        );
      }

      final services = <AdbMdnsService>[];
      for (final rawLine in const LineSplitter().convert(result.stdout as String)) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('List of discovered mdns services')) {
          continue;
        }

        final match = RegExp(
          r'^(.+?)\s+(_adb-tls-(?:connect|pairing)\._tcp)\.?\s+([^\s:]+):(\d+)$',
        ).firstMatch(line);
        if (match == null) {
          continue;
        }

        final port = int.tryParse(match.group(4)!);
        if (port == null) {
          continue;
        }

        services.add(
          AdbMdnsService(
            name: match.group(1)!.trim(),
            type: _parseMdnsServiceType(match.group(2)!),
            host: match.group(3)!.trim(),
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
      final result = await _runTool(adbPath, ['pair', address, pairingCode]);
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
      final result = await _runTool(adbPath, ['connect', address]);
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

  /// Refresh the PID to package name mapping.
  Future<void> refreshPidToPackageMap(String deviceId) async {
    try {
      final result = await _runTool(adbPath, [
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

  String? getPackageNameFromPid(String pid) {
    return _pidToPackageCache[pid];
  }

  /// Starts a live log stream for a specific device and returns a stream of log entries.
  Stream<LogEntry> startLogcat(Device device) async* {
    if (device.isIos) {
      yield* _startIosSyslog(device);
      return;
    }

    yield* _startAndroidLogcat(device.id);
  }

  Stream<LogEntry> _startAndroidLogcat(String deviceId) async* {
    await stopActiveLogcat();
    await refreshPidToPackageMap(deviceId);

    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      refreshPidToPackageMap(deviceId);
    });

    Process? process;
    try {
      process = await _startTool(adbPath, [
        '-s',
        deviceId,
        'logcat',
        '-v',
        'threadtime',
      ]);
      _activeLogcatProcess = process;
      _activeDeviceId = deviceId;
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      var emittedLogs = false;

      await for (final line
          in process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final parsed = LogEntry.parse(line);
        if (parsed != null) {
          parsed.packageName = getPackageNameFromPid(parsed.pid);
          emittedLogs = true;
          yield parsed;
        }
      }

      final stderrOutput = (await stderrFuture).trim();
      if (!emittedLogs && stderrOutput.isNotEmpty) {
        yield _buildToolErrorEntry(
          stderrOutput,
          tag: 'adb logcat',
          processName: deviceId,
        );
      }
    } on ProcessException catch (error) {
      yield _buildToolErrorEntry(
        'Failed to start adb logcat: ${_describeError(error)}',
        tag: 'adb logcat',
        processName: deviceId,
      );
    } finally {
      if (identical(_activeLogcatProcess, process)) {
        _activeLogcatProcess = null;
        _activeDeviceId = null;
      }
      _cacheRefreshTimer?.cancel();
      _cacheRefreshTimer = null;
      if (process?.kill(ProcessSignal.sigterm) ?? false) {
        try {
          await process?.exitCode.timeout(const Duration(seconds: 1));
        } catch (_) {}
      }
    }
  }

  Stream<LogEntry> _startIosSyslog(Device device) async* {
    await stopActiveLogcat();
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = null;

    Process? process;
    final parser = IosSyslogParser();

    try {
      process = await _startTool(ideviceSyslogPath, ['-u', device.id]);
      _activeLogcatProcess = process;
      _activeDeviceId = device.id;
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      var emittedLogs = false;

      await for (final line
          in process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        for (final entry in parser.addLine(line)) {
          emittedLogs = true;
          yield entry;
        }
      }

      final trailingEntry = parser.flush();
      if (trailingEntry != null) {
        emittedLogs = true;
        yield trailingEntry;
      }

      final stderrOutput = (await stderrFuture).trim();
      if (!emittedLogs && stderrOutput.isNotEmpty) {
        yield _buildToolErrorEntry(
          stderrOutput,
          tag: 'idevicesyslog',
          processName: device.displayName,
        );
      }
    } on ProcessException catch (error) {
      yield _buildToolErrorEntry(
        'Failed to start idevicesyslog: ${_describeError(error)}',
        tag: 'idevicesyslog',
        processName: device.displayName,
      );
    } finally {
      if (identical(_activeLogcatProcess, process)) {
        _activeLogcatProcess = null;
        _activeDeviceId = null;
      }
      if (process?.kill(ProcessSignal.sigterm) ?? false) {
        try {
          await process?.exitCode.timeout(const Duration(seconds: 1));
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

  /// Stops logcat for a device (by killing the process).
  Future<void> stopLogcat(String deviceId) async {
    if (_activeDeviceId == deviceId) {
      await stopActiveLogcat();
      return;
    }

    await _runTool(adbPath, ['-s', deviceId, 'shell', 'pkill', 'logcat']);
  }

  /// Clears the logcat buffer on the Android device.
  Future<void> clearLogcat(String deviceId) async {
    await _runTool(adbPath, ['-s', deviceId, 'logcat', '-c']);
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

  String? _firstNonEmpty(String? first, String? second) {
    if (first != null && first.trim().isNotEmpty) {
      return first.trim();
    }
    if (second != null && second.trim().isNotEmpty) {
      return second.trim();
    }
    return null;
  }

  Map<String, String> _parseIdeviceInfoOutput(String stdout) {
    final info = <String, String>{};
    for (final line in const LineSplitter().convert(stdout)) {
      final separatorIndex = line.indexOf(':');
      if (separatorIndex <= 0) continue;
      final key = line.substring(0, separatorIndex).trim();
      final value = line.substring(separatorIndex + 1).trim();
      if (key.isEmpty || value.isEmpty) continue;
      info[key] = value;
    }
    return info;
  }

  String _describeIosDeviceStatus(ProcessResult result) {
    final output = _combinedProcessOutput(result).toLowerCase();
    if (output.contains('not paired') || output.contains('pair')) {
      return 'unpaired';
    }
    if (output.contains('locked') || output.contains('passcode')) {
      return 'locked';
    }
    if (output.contains('no device') || output.contains('not found')) {
      return 'offline';
    }
    return 'unavailable';
  }

  LogEntry _buildToolErrorEntry(
    String message, {
    required String tag,
    required String processName,
  }) {
    return LogEntry(
      timestamp: _formatNowTimestamp(),
      pid: '0',
      tid: '0',
      level: 'E',
      tag: tag,
      message: message,
      packageName: processName,
      processName: processName,
    );
  }

  String _formatNowTimestamp() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    final millisecond = now.millisecond.toString().padLeft(3, '0');
    return '$year-$month-$day $hour:$minute:$second.$millisecond';
  }

  Future<ProcessResult> _runTool(String executable, List<String> arguments) {
    return Process.run(
      executable,
      arguments,
      environment: _toolEnvironment(executable),
      workingDirectory: _toolWorkingDirectory(executable),
    );
  }

  Future<Process> _startTool(String executable, List<String> arguments) {
    return Process.start(
      executable,
      arguments,
      environment: _toolEnvironment(executable),
      workingDirectory: _toolWorkingDirectory(executable),
    );
  }

  Map<String, String>? _toolEnvironment(String executable) {
    final toolDirectory = _toolDirectoryPath(executable);
    if (toolDirectory == null) {
      return null;
    }

    final environment = <String, String>{};
    _prependEnvironmentPath(environment, 'PATH', toolDirectory);

    if (Platform.isWindows) {
      _prependEnvironmentPath(environment, _windowsPathKey, toolDirectory);
    } else if (Platform.isLinux) {
      _prependEnvironmentPath(environment, 'LD_LIBRARY_PATH', toolDirectory);
    } else if (Platform.isMacOS) {
      _prependEnvironmentPath(environment, 'DYLD_LIBRARY_PATH', toolDirectory);
    }

    return environment.isEmpty ? null : environment;
  }

  String? _toolWorkingDirectory(String executable) => _toolDirectoryPath(executable);

  String? _toolDirectoryPath(String executable) {
    final absoluteExecutable = File(executable);
    if (absoluteExecutable.isAbsolute) {
      return absoluteExecutable.parent.path;
    }

    return resolveBundledToolsDirectory()?.path;
  }

  void _prependEnvironmentPath(
    Map<String, String> environment,
    String key,
    String directoryPath,
  ) {
    final pathSeparator = Platform.isWindows ? ';' : ':';
    final inheritedValue =
        environment[key] ??
        Platform.environment[key] ??
        (Platform.isWindows && key != 'PATH'
            ? Platform.environment['PATH']
            : null) ??
        '';
    environment[key] = inheritedValue.isEmpty
        ? directoryPath
        : '$directoryPath$pathSeparator$inheritedValue';
  }

  String get _windowsPathKey {
    for (final key in Platform.environment.keys) {
      if (key.toLowerCase() == 'path') {
        return key;
      }
    }
    return 'Path';
  }
}

