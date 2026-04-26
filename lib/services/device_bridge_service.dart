import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/device.dart';
import '../data/log_entry.dart';
import '../data/wireless_debug_models.dart';
import '../utils/adb_path.dart';
import '../utils/apple_device_mapping.dart';
import 'ios_syslog_parser.dart';

class DeviceBridgeService {
  final String adbPath;
  final String ideviceIdPath;
  final String ideviceInfoPath;
  final String ideviceSyslogPath;
  final Map<String, String> _pidToPackageCache = {};
  Timer? _cacheRefreshTimer;
  Process? _activeLogProcess;
  String? _activeDeviceId;

  DeviceBridgeService({
    String? adbPath,
    String? ideviceIdPath,
    String? ideviceInfoPath,
    String? ideviceSyslogPath,
  }) : adbPath = adbPath ?? resolveBundledExecutablePath('adb') ?? 'adb',
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
        _logError(
          'adb devices -l returned non-zero exit code',
          _combinedProcessOutput(result),
        );
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
    } on ProcessException catch (e) {
      _logError('ProcessException while listing Android devices', e);
      return const [];
    } catch (e) {
      _logError('Unexpected error while listing Android devices', e);
      return const [];
    }
  }

  Future<List<Device>> _getIosDevices() async {
    try {
      final result = await _runTool(ideviceIdPath, ['-l']);
      if (result.exitCode != 0) {
        _logError(
          'idevice_id -l returned non-zero exit code',
          _combinedProcessOutput(result),
        );
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
    } on ProcessException catch (e) {
      _logError('ProcessException while listing iOS devices', e);
      return const [];
    } catch (e) {
      _logError('Unexpected error while listing iOS devices', e);
      return const [];
    }
  }

  Future<Device> _describeIosDevice(String deviceId) async {
    try {
      final result = await _runTool(ideviceInfoPath, ['-u', deviceId]);
      if (result.exitCode != 0) {
        _logError(
          'ideviceinfo returned non-zero exit for $deviceId',
          _combinedProcessOutput(result),
        );
        return Device(
          deviceId,
          _describeIosDeviceStatus(result),
          platform: DevicePlatform.ios,
        );
      }

      final info = _parseIdeviceInfoOutput(result.stdout as String);
      // Prefer the human-friendly product name for ProductType (e.g. "iPhone7,2"
      // -> "iPhone 6"), falling back to the raw ProductType code or the
      // HardwareModel when necessary.
      final productType = info['ProductType'];
      String? model;
      if (productType != null && productType.trim().isNotEmpty) {
        final human = await getAppleDeviceName(productType.trim());
        model = human ?? productType.trim();
      } else {
        model = _firstNonEmpty(info['HardwareModel'], null);
      }

      return Device(
        deviceId,
        'device',
        name: _firstNonEmpty(info['DeviceName'], info['ProductName']),
        model: model,
        platform: DevicePlatform.ios,
      );
    } on ProcessException catch (e) {
      _logError('ProcessException describing iOS device $deviceId', e);
      return Device(deviceId, 'unavailable', platform: DevicePlatform.ios);
    } catch (e) {
      _logError('Unexpected error describing iOS device $deviceId', e);
      return Device(deviceId, 'unavailable', platform: DevicePlatform.ios);
    }
  }

  Future<WirelessServiceDiscoveryResult> discoverMdnsServices() async {
    try {
      final result = await _runTool(adbPath, ['mdns', 'services']);
      if (result.exitCode != 0) {
        final details = _describeCommandFailure(
          'Failed to discover wireless ADB services.',
          result,
        );
        _logError('Failed to discover wireless ADB services', details);
        return WirelessServiceDiscoveryResult.failure(error: details);
      }

      final services = <WirelessDebugService>[];
      for (final rawLine in const LineSplitter().convert(
        result.stdout as String,
      )) {
        final line = rawLine.trim();
        if (line.isEmpty ||
            line.startsWith('List of discovered mdns services')) {
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
          WirelessDebugService(
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

      return WirelessServiceDiscoveryResult.success(services: services);
    } catch (error) {
      _logError('Exception while discovering mdns services', error);
      return WirelessServiceDiscoveryResult.failure(
        error:
            'Failed to discover wireless ADB services: ${_describeError(error)}',
      );
    }
  }

  Future<DeviceCommandResult> pairDevice({
    required String address,
    required String pairingCode,
  }) async {
    try {
      final result = await _runTool(adbPath, ['pair', address, pairingCode]);
      if (result.exitCode != 0) {
        final details = _describeCommandFailure(
          'Failed to pair with $address.',
          result,
        );
        _logError('Pair command failed for $address', details);
        return DeviceCommandResult.failure(error: details);
      }

      final message = _combinedProcessOutput(result);
      return DeviceCommandResult.success(
        message: message.isEmpty
            ? 'Successfully paired with $address.'
            : message,
      );
    } catch (error) {
      _logError('Exception while pairing with $address', error);
      return DeviceCommandResult.failure(
        error: 'Failed to pair with $address: ${_describeError(error)}',
      );
    }
  }

  Future<DeviceCommandResult> connectDevice(String address) async {
    try {
      final result = await _runTool(adbPath, ['connect', address]);
      final output = _combinedProcessOutput(result);
      final normalizedOutput = output.toLowerCase();
      final failed =
          result.exitCode != 0 || normalizedOutput.contains('failed');

      if (failed) {
        final details = _describeCommandFailure(
          'Failed to connect to $address.',
          result,
        );
        _logError('Connect command failed for $address', details);
        return DeviceCommandResult.failure(error: details);
      }

      return DeviceCommandResult.success(
        message: output.isEmpty ? 'Connected to $address.' : output,
      );
    } catch (error) {
      _logError('Exception while connecting to $address', error);
      return DeviceCommandResult.failure(
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
    } catch (e) {
      // Log PID/package refresh failures but keep streaming running.
      _logError('Failed to refresh PID->package map for $deviceId', e);
    }
  }

  String? getPackageNameFromPid(String pid) {
    return _pidToPackageCache[pid];
  }

  /// Starts a live log stream for a specific device and returns log entries.
  Stream<LogEntry> startLogStream(Device device) async* {
    if (device.isIos) {
      yield* _startIosSyslog(device);
      return;
    }

    yield* _startAndroidLogcat(device.id);
  }

  Stream<LogEntry> _startAndroidLogcat(String deviceId) async* {
    await stopActiveLogStream();
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
      _activeLogProcess = process;
      _activeDeviceId = deviceId;
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      var emittedLogs = false;

      await for (final line
          in process.stdout
              .transform(Utf8Decoder(allowMalformed: true))
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
      _logError('Failed to start adb logcat for $deviceId', error);
      yield _buildToolErrorEntry(
        'Failed to start adb logcat: ${_describeError(error)}',
        tag: 'adb logcat',
        processName: deviceId,
      );
    } finally {
      if (identical(_activeLogProcess, process)) {
        _activeLogProcess = null;
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
    await stopActiveLogStream();
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = null;

    Process? process;
    final parser = IosSyslogParser();

    try {
      process = await _startTool(ideviceSyslogPath, ['-u', device.id]);
      _activeLogProcess = process;
      _activeDeviceId = device.id;
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      var emittedLogs = false;

      await for (final line
          in process.stdout
              .transform(Utf8Decoder(allowMalformed: true))
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
      _logError(
        'Failed to start idevicesyslog for ${device.displayName}',
        error,
      );
      yield _buildToolErrorEntry(
        'Failed to start idevicesyslog: ${_describeError(error)}',
        tag: 'idevicesyslog',
        processName: device.displayName,
      );
    } finally {
      if (identical(_activeLogProcess, process)) {
        _activeLogProcess = null;
        _activeDeviceId = null;
      }
      if (process?.kill(ProcessSignal.sigterm) ?? false) {
        try {
          await process?.exitCode.timeout(const Duration(seconds: 1));
        } catch (_) {}
      }
    }
  }

  Future<void> stopActiveLogStream() async {
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = null;

    final process = _activeLogProcess;
    _activeLogProcess = null;
    _activeDeviceId = null;

    if (process == null) return;
    if (process.kill(ProcessSignal.sigterm)) {
      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
  }

  /// Stops logcat for a device (by killing the process).
  Future<void> stopLogStream(String deviceId) async {
    if (_activeDeviceId == deviceId) {
      await stopActiveLogStream();
      return;
    }

    await _runTool(adbPath, ['-s', deviceId, 'shell', 'pkill', 'logcat']);
  }

  /// Clears the logcat buffer on the Android device.
  Future<void> clearLogs(String deviceId) async {
    await _runTool(adbPath, ['-s', deviceId, 'logcat', '-c']);
  }

  Future<void> dispose() => stopActiveLogStream();

  WirelessDebugServiceType _parseMdnsServiceType(String rawValue) {
    return switch (rawValue.trim()) {
      '_adb-tls-connect._tcp' => WirelessDebugServiceType.connect,
      '_adb-tls-pairing._tcp' => WirelessDebugServiceType.pairing,
      _ => WirelessDebugServiceType.unknown,
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

  void _logError(String message, [Object? error]) {
    final errorPart = error == null ? '' : ' | ${error.toString()}';
    // ignore: avoid_print
    print('[DeviceBridgeService] $message$errorPart');
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

  String? _toolWorkingDirectory(String executable) =>
      _toolDirectoryPath(executable);

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
