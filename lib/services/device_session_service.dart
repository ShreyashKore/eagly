import 'dart:async';

import '../data/device.dart';
import '../data/log_entry.dart';
import '../data/wireless_debug_models.dart';
import 'tools/adb_tool.dart';
import 'tools/idevice_syslog_tool.dart';
import 'tools/tool_process_runner.dart';

class DeviceSessionService {
  final AdbTool _adbTool;
  final IdeviceSyslogTool _ideviceSyslogTool;
  final Map<String, String> _pidToPackageCache = {};
  Timer? _cacheRefreshTimer;
  ToolStreamSession<LogEntry>? _activeLogSession;
  String? _activeDeviceId;

  DeviceSessionService({
    String? adbPath,
    String? ideviceSyslogPath,
    AdbTool? adbTool,
    IdeviceSyslogTool? ideviceSyslogTool,
  }) : _adbTool = adbTool ?? AdbTool(executablePath: adbPath),
       _ideviceSyslogTool =
           ideviceSyslogTool ??
           IdeviceSyslogTool(executablePath: ideviceSyslogPath);

  Future<DeviceCommandResult> pairDevice({
    required String address,
    required String pairingCode,
  }) => _adbTool.pairDevice(address: address, pairingCode: pairingCode);

  Future<DeviceCommandResult> connectDevice(String address) =>
      _adbTool.connectDevice(address);

  /// Refresh the PID to package name mapping.
  Future<void> refreshPidToPackageMap(String deviceId) async {
    _pidToPackageCache
      ..clear()
      ..addAll(await _adbTool.getPidToPackageMap(deviceId));
  }

  String? getPackageNameFromPid(String pid) {
    return _pidToPackageCache[pid];
  }

  /// Starts a live log stream for a specific device and returns log entries.
  Stream<LogEntry> startLogStream(Device device) async* {
    switch (device) {
      case IosDevice():
        yield* _startIosSyslog(device);
      case AndroidDevice():
        yield* _startAndroidLogcat(device.id);
    }
  }

  Stream<LogEntry> _startAndroidLogcat(String deviceId) async* {
    await stopActiveLogStream();
    await refreshPidToPackageMap(deviceId);

    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      refreshPidToPackageMap(deviceId);
    });

    final session = _adbTool.startLogcat(deviceId);
    try {
      _activeLogSession = session;
      _activeDeviceId = deviceId;
      await for (final entry in session.stream) {
        entry.packageName ??= getPackageNameFromPid(entry.pid);
        yield entry;
      }
    } finally {
      if (identical(_activeLogSession, session)) {
        _activeLogSession = null;
        _activeDeviceId = null;
      }
      _cacheRefreshTimer?.cancel();
      _cacheRefreshTimer = null;
      await session.stop();
    }
  }

  Stream<LogEntry> _startIosSyslog(Device device) async* {
    await stopActiveLogStream();
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = null;

    final session = _ideviceSyslogTool.start(
      deviceId: device.id,
      processName: device.displayName,
    );

    try {
      _activeLogSession = session;
      _activeDeviceId = device.id;
      yield* session.stream;
    } finally {
      if (identical(_activeLogSession, session)) {
        _activeLogSession = null;
        _activeDeviceId = null;
      }
      await session.stop();
    }
  }

  Future<void> stopActiveLogStream() async {
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = null;

    final session = _activeLogSession;
    _activeLogSession = null;
    _activeDeviceId = null;

    if (session == null) return;
    await session.stop();
  }

  /// Stops logcat for a device (by killing the process).
  Future<void> stopLogStream(String deviceId) async {
    if (_activeDeviceId == deviceId) {
      await stopActiveLogStream();
      return;
    }

    await _adbTool.stopLogcat(deviceId);
  }

  /// Clears the logcat buffer on the Android device.
  Future<void> clearLogs(String deviceId) async {
    await _adbTool.clearLogs(deviceId);
  }

  Future<void> dispose() => stopActiveLogStream();
}
