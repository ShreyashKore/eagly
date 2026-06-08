import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../data/device.dart';
import '../data/log_entry.dart';
import '../data/wireless_debug_models.dart';
import '../features/app_log/app_logger.dart';
import '../features/flutter_scrcpy/flutter_scrcpy.dart';
import '../utils/adb_path.dart';
import 'tools/adb_tool.dart';
import 'tools/ideviceinstaller_tool.dart';
import 'tools/idevice_syslog_tool.dart';
import 'tools/tool_process_runner.dart';

class DeviceSessionService {
  final AdbTool _adbTool;
  final IdeviceInstallerTool _ideviceInstallerTool;
  final IdeviceSyslogTool _ideviceSyslogTool;
  final ScrcpyMirror _scrcpyMirror;
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
    ScrcpyMirror? scrcpyMirror,
  }) : _adbTool = adbTool ?? AdbTool(executablePath: adbPath),
       _ideviceInstallerTool =
           ideviceInstallerTool ??
           IdeviceInstallerTool(executablePath: ideviceInstallerPath),
       _ideviceSyslogTool =
           ideviceSyslogTool ??
           IdeviceSyslogTool(executablePath: ideviceSyslogPath),
       _scrcpyMirror =
           scrcpyMirror ??
           ScrcpyMirror(
             adbExecutablePath:
                 resolveBundledExecutablePath('adb') ?? adbPath ?? 'adb',
             serverJarPath:
                 '${resolveBundledToolsDirectory()?.path}/scrcpy-server',
           );

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
        final processName = getProcessNameFromPid(entry.pid);
        entry.packageName ??= processName;
        entry.processName ??= processName;
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

  Future<DeviceCommandResult> installApp({
    required Device device,
    required String filePath,
  }) {
    return switch (device) {
      AndroidDevice() => _adbTool.installApk(
        deviceId: device.id,
        apkPath: filePath,
      ),
      IosDevice() => _ideviceInstallerTool.installApp(
        deviceId: device.id,
        appPath: filePath,
      ),
    };
  }

  Future<ScrcpyMirrorSession> startScreenMirror(
    Device device, {
    ScrcpyVideoOptions? options,
  }) async {
    if (device is! AndroidDevice) {
      throw UnsupportedError(
        'Screen mirroring is currently supported for Android devices only.',
      );
    }
    try {
      return options != null
          ? await _scrcpyMirror.start(device.id, options: options)
          : await _scrcpyMirror.start(device.id);
    } catch (error) {
      _logger.error('Failed to start screen mirror', detail: error.toString());
      rethrow;
    }
  }

  /// Captures a full-resolution PNG screenshot of [deviceId] via `screencap`.
  Future<Uint8List> captureScreenshot(String deviceId) {
    return _adbTool.captureScreenshotPng(deviceId);
  }

  /// Cycles the device display orientation (0→1→2→3) via `settings`.
  Future<void> rotateDevice(String deviceId) async {
    final current = await _adbTool.getUserRotation(deviceId);
    await _adbTool.setUserRotation(deviceId, current + 1);
  }

  /// Starts an on-device `screenrecord`. Finalize + save it via
  /// [ScreenRecordingSession.stopAndPull].
  Future<ScreenRecordingSession> startScreenRecording(
    String deviceId, {
    int bitRate = 8000000,
  }) async {
    final devicePath =
        '/sdcard/eagly-rec-${DateTime.now().millisecondsSinceEpoch}.mp4';
    final process = await _adbTool.startScreenRecord(
      deviceId,
      devicePath,
      bitRate: bitRate,
      timeLimitSeconds: 180,
    );
    return ScreenRecordingSession(
      adbTool: _adbTool,
      deviceId: deviceId,
      devicePath: devicePath,
      process: process,
    );
  }

  /// Refresh the PID to package name mapping.
  Future<void> refreshPidToPackageMap(String deviceId) async {
    _pidToPackageCache
      ..clear()
      ..addAll(await _adbTool.getPidToPackageMap(deviceId));
  }

  String? getProcessNameFromPid(String pid) {
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

/// A running on-device `screenrecord`. Stop it with [stopAndPull] to finalize
/// the mp4 and copy it to the host, or [cancel] to discard it.
class ScreenRecordingSession {
  ScreenRecordingSession({
    required AdbTool adbTool,
    required this.deviceId,
    required this.devicePath,
    required this.process,
  }) : _adbTool = adbTool;

  final AdbTool _adbTool;
  final String deviceId;
  final String devicePath;
  final Process process;

  Future<void> _finish() async {
    await _adbTool.signalStopScreenRecord(deviceId);
    try {
      await process.exitCode.timeout(const Duration(seconds: 8));
    } catch (_) {
      process.kill();
    }
  }

  /// Finalizes the recording and pulls it to [localPath], then deletes it
  /// from the device.
  Future<void> stopAndPull(String localPath) async {
    await _finish();
    await _adbTool.pullFile(deviceId, devicePath, localPath);
    await _adbTool.removeFile(deviceId, devicePath);
  }

  /// Stops recording and discards the on-device file without saving.
  Future<void> cancel() async {
    await _finish();
    await _adbTool.removeFile(deviceId, devicePath);
  }
}
