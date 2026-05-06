import 'dart:async';

import '../data/device.dart';
import '../data/log_entry.dart';
import '../data/wireless_debug_models.dart';
import '../features/app_log/app_logger.dart';
import 'tools/adb_tool.dart';
import 'tools/ideviceinstaller_tool.dart';
import 'tools/idevice_syslog_tool.dart';
import 'tools/tool_process_runner.dart';

class DeviceSessionService {
  final AdbTool _adbTool;
  final IdeviceInstallerTool _ideviceInstallerTool;
  final IdeviceSyslogTool _ideviceSyslogTool;
  final AppLogger _logger = AppLogger(source: 'DeviceSessionService');
  final Map<String, String> _pidToPackageCache = {};
  Timer? _cacheRefreshTimer;
  ToolStreamSession<LogEntry>? _activeLogSession;
  String? _activeDeviceId;

  /// Optional human-readable label for the tab that owns this service,
  /// used to tag [AppLogger] entries (e.g. "Tab 2 – Pixel 6").
  String? sessionLabel;

  DeviceSessionService({
    String? adbPath,
    String? ideviceInstallerPath,
    String? ideviceSyslogPath,
    AdbTool? adbTool,
    IdeviceInstallerTool? ideviceInstallerTool,
    IdeviceSyslogTool? ideviceSyslogTool,
  }) : _adbTool = adbTool ?? AdbTool(executablePath: adbPath),
       _ideviceInstallerTool =
           ideviceInstallerTool ??
           IdeviceInstallerTool(executablePath: ideviceInstallerPath),
       _ideviceSyslogTool =
           ideviceSyslogTool ??
           IdeviceSyslogTool(executablePath: ideviceSyslogPath);

  AppLogger _sessionLogger(String fallbackSessionTag) =>
      _logger.scoped(sessionTag: sessionLabel ?? fallbackSessionTag);



  Stream<LogEntry> _startAndroidLogcat(String deviceId) async* {
    await stopActiveLogStream();
    await refreshPidToPackageMap(deviceId);
    final sessionLogger = _sessionLogger(deviceId);

    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      refreshPidToPackageMap(deviceId);
    });

    sessionLogger.info('Log stream started for $deviceId');

    final session = _adbTool.startLogcat(deviceId);
    try {
      _activeLogSession = session;
      _activeDeviceId = deviceId;
      await for (final entry in session.stream) {
        if (entry.type == LogEntryType.error) {
          sessionLogger.error(
            'Tool error while streaming logs for $deviceId',
            detail: '[${entry.tag}] ${entry.message}',
          );
        }
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
      sessionLogger.info('Log stream stopped for $deviceId');
      await session.stop();
    }
  }

  Stream<LogEntry> _startIosSyslog(Device device) async* {
    await stopActiveLogStream();
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = null;
    final sessionLogger = _sessionLogger(device.id);

    sessionLogger.info('iOS syslog stream started for ${device.displayName}');

    final session = _ideviceSyslogTool.start(
      deviceId: device.id,
      processName: device.displayName,
    );

    try {
      _activeLogSession = session;
      _activeDeviceId = device.id;
      await for (final entry in session.stream) {
        if (entry.type == LogEntryType.error) {
          sessionLogger.error(
            'Tool error while streaming iOS logs for ${device.displayName}',
            detail: '[${entry.tag}] ${entry.message}',
          );
        }
        yield entry;
      }
    } finally {
      if (identical(_activeLogSession, session)) {
        _activeLogSession = null;
        _activeDeviceId = null;
      }
      sessionLogger.info('iOS syslog stream stopped for ${device.displayName}');
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
    final sessionLogger = _sessionLogger(deviceId);
    if (_activeDeviceId == deviceId) {
      sessionLogger.info('Stopping active log stream for $deviceId');
      await stopActiveLogStream();
      return;
    }

    sessionLogger.info('Stopping background logcat process for $deviceId');
    await _adbTool.stopLogcat(deviceId);
  }

  /// Clears the logcat buffer on the Android device.
  Future<void> clearLogs(String deviceId) async {
    final sessionLogger = _sessionLogger(deviceId);
    sessionLogger.info('Clearing logs for $deviceId');
    await _adbTool.clearLogs(deviceId);
  }

  Future<void> dispose() => stopActiveLogStream();


  Future<DeviceCommandResult> pairDevice({
    required String address,
    required String pairingCode,
  }) => _adbTool.pairDevice(address: address, pairingCode: pairingCode);

  Future<DeviceCommandResult> connectDevice(String address) =>
      _adbTool.connectDevice(address);

  Future<DeviceCommandResult> installApp({
    required Device device,
    required String filePath,
  }) {
    return switch (device) {
      AndroidDevice() => _adbTool.installApk(deviceId: device.id, apkPath: filePath),
      IosDevice() =>
        _ideviceInstallerTool.installApp(deviceId: device.id, appPath: filePath),
    };
  }

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
}
