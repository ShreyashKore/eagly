import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../data/device.dart';
import '../features/device_home/data/device_performance_stats.dart';
import '../features/device_home/data/installed_app_info.dart';
import '../features/logs/data/models/log_entry.dart';
import '../features/wireless_connection/data/wireless_debug_models.dart';
import '../features/app_log/app_logger.dart';
import '../features/flutter_scrcpy/flutter_scrcpy.dart';
import '../utils/tools_path.dart';
import 'tools/adb_tool.dart';
import 'tools/idevice_crash_report_tool.dart';
import 'tools/ideviceinstaller_tool.dart';
import 'tools/idevice_syslog_tool.dart';

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

  /// Shared PID→package refresh timer, ref-counted by [_pidCacheConsumers] so
  /// concurrent Android log streams share a single `ps -A` poll.
  Timer? _pidCacheRefreshTimer;
  int _pidCacheConsumers = 0;

  /// Number of live log streams currently open for this device. Each live tab
  /// owns an independent stream (see [startLogStream]); this is just a counter
  /// for [isLogStreamActive].
  int _activeStreamCount = 0;

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
    final sessionLogger = _sessionLogger;
    await refreshPidToPackageMap();
    _retainPidCacheRefresh();
    _activeStreamCount++;

    sessionLogger.info('Log stream started for $_deviceId');

    final session = _adbTool.startLogcat(_deviceId);
    try {
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
      _activeStreamCount--;
      _releasePidCacheRefresh();
      sessionLogger.info('Log stream stopped for $_deviceId');
      await session.stop();
    }
  }

  Stream<LogEntry> _startIosSyslog() async* {
    final sessionLogger = _sessionLogger;
    _activeStreamCount++;

    sessionLogger.info('iOS syslog stream started for ${device.displayName}');

    final session = _ideviceSyslogTool.start(
      deviceId: _deviceId,
      processName: device.displayName,
    );

    try {
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
      _activeStreamCount--;
      sessionLogger.info('iOS syslog stream stopped for ${device.displayName}');
      await session.stop();
    }
  }

  /// Each live log tab owns its own stream (the [StreamSubscription] held by its
  /// [LogController]); a stream tears itself down — stopping its tool process and
  /// releasing the shared PID-cache poll — when that subscription is cancelled.
  /// There is deliberately no shared "active stream" to stop, so restarting or
  /// closing one tab never disturbs another tab on the same device.
  bool get isLogStreamActive => _activeStreamCount > 0;

  void _retainPidCacheRefresh() {
    _pidCacheConsumers++;
    _pidCacheRefreshTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(refreshPidToPackageMap());
    });
  }

  void _releasePidCacheRefresh() {
    if (_pidCacheConsumers > 0) _pidCacheConsumers--;
    if (_pidCacheConsumers == 0) {
      _pidCacheRefreshTimer?.cancel();
      _pidCacheRefreshTimer = null;
    }
  }

  /// Lightweight liveness probe for the bound device. Returns false when the
  /// device is not responding within [timeout] (e.g. a wedged adb transport
  /// that still appears connected). iOS devices have no cheap equivalent probe,
  /// so they are assumed responsive here — the log stream's own end-of-stream
  /// signal handles iOS disconnects.
  Future<bool> pingDevice({Duration timeout = const Duration(seconds: 5)}) {
    return switch (device) {
      AndroidDevice() => _adbTool.pingDevice(_deviceId, timeout: timeout),
      IosDevice() => Future<bool>.value(true),
    };
  }

  /// Best-effort recovery of a wedged transport before re-attaching the log
  /// stream. Android issues `adb reconnect`; iOS has no equivalent (no-op).
  Future<void> recoverConnection() async {
    if (device is AndroidDevice) {
      await _adbTool.reconnectDevice(_deviceId);
    }
  }

  /// Clears the logcat buffer on the (Android) device.
  Future<void> clearLogs() async {
    _sessionLogger.info('Clearing logs for $_deviceId');
    await _adbTool.clearLogs(_deviceId);
  }

  Future<DevicePerformanceStats> fetchPerformanceStats() {
    return switch (device) {
      AndroidDevice() => _fetchAndroidPerformanceStats(),
      IosDevice() => Future.value(const DevicePerformanceStats()),
    };
  }

  Future<DevicePerformanceStats> _fetchAndroidPerformanceStats() async {
    final loadavg = await _adbTool.readProcFile(_deviceId, '/proc/loadavg');
    CpuStats? cpu;
    if (loadavg != null && loadavg.isNotEmpty) {
      final columns = loadavg.trim().split(RegExp(r'\s+'));
      if (columns.length >= 3) {
        final load1 = double.tryParse(columns[0]);
        final load5 = double.tryParse(columns[1]);
        final load15 = double.tryParse(columns[2]);
        if (load1 != null && load5 != null && load15 != null) {
          final cpuinfo = await _adbTool.readProcFile(
            _deviceId,
            '/proc/cpuinfo',
          );
          final cores = cpuinfo != null
              ? 'processor\t'.allMatches(cpuinfo).length
              : 0;
          cpu = CpuStats(
            coreCount: cores.clamp(1, 999),
            loadAverage1m: load1,
            loadAverage5m: load5,
            loadAverage15m: load15,
          );
        }
      }
    }

    final meminfo = await _adbTool.readProcFile(_deviceId, '/proc/meminfo');
    MemoryStats? memory;
    if (meminfo != null) {
      final mem = _parseMeminfo(meminfo);
      final total = mem['MemTotal'];
      final available = mem['MemAvailable'];
      final free = mem['MemFree'];
      if (total != null && available != null && free != null) {
        memory = MemoryStats(
          totalKb: total,
          availableKb: available,
          freeKb: free,
        );
      }
    }

    return DevicePerformanceStats(cpu: cpu, memory: memory);
  }

  static Map<String, int> _parseMeminfo(String output) {
    final result = <String, int>{};
    for (final line in output.split('\n')) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final key = line.substring(0, colon).trim();
      final valueStr = line
          .substring(colon + 1)
          .trim()
          .split(RegExp(r'\s+'))
          .first;
      final value = int.tryParse(valueStr);
      if (value != null) result[key] = value;
    }
    return result;
  }

  /// Tears down shared per-device resources. Individual log streams are owned by
  /// their [LogController]s and are stopped when those controllers are disposed
  /// (which cancels each stream's subscription), so by the time this runs only
  /// the shared PID-cache poll remains to clean up.
  Future<void> dispose() async {
    _pidCacheRefreshTimer?.cancel();
    _pidCacheRefreshTimer = null;
    _pidCacheConsumers = 0;
  }

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

  Future<List<InstalledAppInfo>> listRecentlyInstalledApps() {
    return switch (device) {
      AndroidDevice() => _adbTool.listRecentlyInstalledApps(_deviceId),
      IosDevice() => _ideviceInstallerTool.listInstalledApps(_deviceId),
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
