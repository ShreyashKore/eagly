import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../data/device.dart';
import '../features/logs/data/models/log_entry.dart';
import '../features/wireless_connection/data/wireless_debug_models.dart';
import '../features/app_log/app_logger.dart';
import '../features/flutter_scrcpy/flutter_scrcpy.dart';
import '../utils/tools_path.dart';
import 'tools/adb_tool.dart';
import 'tools/idevice_crash_report_tool.dart';
import 'tools/ideviceinstaller_tool.dart';
import 'tools/idevice_syslog_tool.dart';
import 'tools/tool_process_runner.dart';

/// Per-device facade over the platform tools (adb / libimobiledevice / scrcpy).
///
/// One instance is created per detected device and owned by its
/// [DeviceSessionController]. It exposes platform-agnostic device operations and
/// holds no feature state — feature controllers own their own state.
class DeviceSessionRepository {
  final Device device;
  final AdbTool _adbTool;
  final IdeviceInstallerTool _ideviceInstallerTool;
  final IdeviceSyslogTool _ideviceSyslogTool;
  final IdeviceCrashReportTool _ideviceCrashReportTool;
  final ScrcpyMirror _scrcpyMirror;
  final AppLogger _logger = AppLogger(source: 'DeviceSessionService');
  final Map<String, String> _pidToPackageCache = {};
  Timer? _cacheRefreshTimer;
  ToolStreamSession<LogEntry>? _activeLogSession;
  bool _logStreamActive = false;

  /// Optional human-readable label used to tag [AppLogger] entries. Defaults to
  /// the device id when unset.
  String? sessionLabel;

  String get _deviceId => device.id;

  DeviceSessionRepository({
    required this.device,
    String? adbPath,
    String? ideviceInstallerPath,
    String? ideviceSyslogPath,
    String? ideviceCrashReportPath,
    AdbTool? adbTool,
    IdeviceInstallerTool? ideviceInstallerTool,
    IdeviceSyslogTool? ideviceSyslogTool,
    IdeviceCrashReportTool? ideviceCrashReportTool,
    ScrcpyMirror? scrcpyMirror,
  }) : _adbTool = adbTool ?? AdbTool(executablePath: adbPath),
       _ideviceInstallerTool =
           ideviceInstallerTool ??
           IdeviceInstallerTool(executablePath: ideviceInstallerPath),
       _ideviceSyslogTool =
           ideviceSyslogTool ??
           IdeviceSyslogTool(executablePath: ideviceSyslogPath),
       _ideviceCrashReportTool =
           ideviceCrashReportTool ??
           IdeviceCrashReportTool(executablePath: ideviceCrashReportPath),
       _scrcpyMirror =
           scrcpyMirror ??
           ScrcpyMirror(
             adbExecutablePath:
                 resolveBundledExecutablePath('adb') ?? adbPath ?? 'adb',
             serverJarPath:
                 '${resolveBundledToolsDirectory()?.path}/scrcpy-server',
             onLog: (message) => AppLogger(
               source: 'DeviceSessionService',
             ).info('[scrcpy] $message'),
           );

  AppLogger get _sessionLogger =>
      _logger.scoped(sessionTag: sessionLabel ?? _deviceId);

  /// Starts a live log stream for the bound device.
  Stream<LogEntry> startLogStream() async* {
    switch (device) {
      case IosDevice():
        yield* _startIosSyslog();
      case AndroidDevice():
        yield* _startAndroidLogcat();
    }
  }

  Stream<LogEntry> _startAndroidLogcat() async* {
    await stopActiveLogStream();
    await refreshPidToPackageMap();
    final sessionLogger = _sessionLogger;

    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      refreshPidToPackageMap();
    });

    sessionLogger.info('Log stream started for $_deviceId');

    final session = _adbTool.startLogcat(_deviceId);
    try {
      _activeLogSession = session;
      _logStreamActive = true;
      await for (final entry in session.stream) {
        if (entry.type == LogEntryType.error) {
          sessionLogger.error(
            'Tool error while streaming logs for $_deviceId',
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
        _logStreamActive = false;
      }
      _cacheRefreshTimer?.cancel();
      _cacheRefreshTimer = null;
      sessionLogger.info('Log stream stopped for $_deviceId');
      await session.stop();
    }
  }

  Stream<LogEntry> _startIosSyslog() async* {
    await stopActiveLogStream();
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = null;
    final sessionLogger = _sessionLogger;

    sessionLogger.info('iOS syslog stream started for ${device.displayName}');

    final session = _ideviceSyslogTool.start(
      deviceId: _deviceId,
      processName: device.displayName,
    );

    try {
      _activeLogSession = session;
      _logStreamActive = true;
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
        _logStreamActive = false;
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
    _logStreamActive = false;

    if (session == null) return;
    await session.stop();
  }

  bool get isLogStreamActive => _logStreamActive;

  /// Clears the logcat buffer on the (Android) device.
  Future<void> clearLogs() async {
    _sessionLogger.info('Clearing logs for $_deviceId');
    await _adbTool.clearLogs(_deviceId);
  }

  Future<void> dispose() => stopActiveLogStream();

  Future<DeviceCommandResult> installApp({required String filePath}) {
    return switch (device) {
      AndroidDevice() => _adbTool.installApk(
        deviceId: _deviceId,
        apkPath: filePath,
      ),
      IosDevice() => _ideviceInstallerTool.installApp(
        deviceId: _deviceId,
        appPath: filePath,
      ),
    };
  }

  /// Pulls (and parses) crash reports from the bound iOS device. Reports are
  /// copied into a temp directory exposed on the result for the caller to clean
  /// up. Throws [UnsupportedError] for non-iOS devices.
  Future<CrashReportPullResult> pullCrashReports() {
    if (device is! IosDevice) {
      throw UnsupportedError(
        'Crash report reading is available for iOS devices only.',
      );
    }
    _sessionLogger.info('Reading crash reports for ${device.displayName}');
    return _ideviceCrashReportTool.pullReports(_deviceId);
  }

  Future<ScrcpyMirrorSession> startScreenMirror({
    ScrcpyVideoOptions? options,
  }) async {
    if (device is! AndroidDevice) {
      throw UnsupportedError(
        'Screen mirroring is currently supported for Android devices only.',
      );
    }
    try {
      return options != null
          ? await _scrcpyMirror.start(_deviceId, options: options)
          : await _scrcpyMirror.start(_deviceId);
    } catch (error) {
      _logger.error('Failed to start screen mirror', detail: error.toString());
      rethrow;
    }
  }

  /// Captures a full-resolution PNG screenshot via `screencap`.
  Future<Uint8List> captureScreenshot() {
    return _adbTool.captureScreenshotPng(_deviceId);
  }

  /// Cycles the device display orientation (0→1→2→3) via `settings`.
  Future<void> rotateDevice() async {
    final current = await _adbTool.getUserRotation(_deviceId);
    await _adbTool.setUserRotation(_deviceId, current + 1);
  }

  /// Starts an on-device `screenrecord`. Finalize + save it via
  /// [ScreenRecordingSession.stopAndPull].
  Future<ScreenRecordingSession> startScreenRecording({
    int bitRate = 8000000,
  }) async {
    final devicePath =
        '/sdcard/eagly-rec-${DateTime.now().millisecondsSinceEpoch}.mp4';
    final process = await _adbTool.startScreenRecord(
      _deviceId,
      devicePath,
      bitRate: bitRate,
      timeLimitSeconds: 180,
    );
    return ScreenRecordingSession(
      adbTool: _adbTool,
      deviceId: _deviceId,
      devicePath: devicePath,
      process: process,
    );
  }

  /// Refresh the PID to package name mapping.
  Future<void> refreshPidToPackageMap() async {
    _pidToPackageCache
      ..clear()
      ..addAll(await _adbTool.getPidToPackageMap(_deviceId));
  }

  String? getProcessNameFromPid(String pid) {
    return _pidToPackageCache[pid];
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
