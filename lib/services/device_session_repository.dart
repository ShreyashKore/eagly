import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../data/device.dart';
import '../features/apps/data/app_info.dart';
import '../features/device_home/data/device_info.dart';
import '../features/device_home/data/device_performance_stats.dart';
import '../features/device_home/data/installed_app_info.dart';
import '../features/layout_inspector/data/layout_parsers.dart';
import '../features/layout_inspector/data/layout_snapshot.dart';
import '../features/layout_inspector/data/view_hierarchy.dart';
import '../features/layout_inspector/services/inspector_helper.dart';
import '../features/logs/data/models/log_entry.dart';
import '../features/network/services/inspektor/inspektor_endpoint.dart';
import '../features/terminal/data/terminal_line.dart';
import '../features/terminal/data/terminal_process.dart';
import '../features/terminal/data/terminal_tools.dart';
import '../features/utilities/data/utility_command.dart';
import '../features/wireless_connection/data/wireless_debug_models.dart';
import '../features/app_log/app_logger.dart';
import '../features/flutter_scrcpy/flutter_scrcpy.dart';
import '../features/mirror/services/ios_screen_capture.dart';
import '../features/mirror/services/screen_recording.dart';
import '../utils/tools_path.dart';
import 'tools/adb_tool.dart';
import 'tools/device_tool_runner.dart';
import 'tools/android_apk_icon_extractor.dart';
import 'tools/idevice_crash_report_tool.dart';
import 'ios/ios_device_domains.dart';
import 'ios/ios_app_service.dart';
import 'ios/ios_crash_report_service.dart';
import 'ios/ios_device_service.dart';
import 'ios/ios_log_service.dart';
import 'ios/ios_mirror_service.dart';
import 'ios/ios_network_service.dart';
import 'ios/libimobiledevice_ios_app_service.dart';
import 'ios/libimobiledevice_ios_crash_report_service.dart';
import 'ios/libimobiledevice_ios_log_service.dart';
import 'tools/ideviceinstaller_tool.dart';
import 'tools/idevice_syslog_tool.dart';
import 'tools/tool_process_runner.dart';

/// Per-device facade over the platform tools (adb / libimobiledevice / scrcpy).
///
/// One instance is created per detected device and owned by its
/// [DeviceSessionController]. It exposes platform-agnostic device operations and
/// holds no feature state — feature controllers own their own state.
class DeviceSessionRepository({
  required final Device device,
  String? adbPath,
  String? ideviceInstallerPath,
  String? ideviceSyslogPath,
  String? ideviceCrashReportPath,
  AdbTool? adbTool,
  IdeviceInstallerTool? ideviceInstallerTool,
  IdeviceSyslogTool? ideviceSyslogTool,
  IdeviceCrashReportTool? ideviceCrashReportTool,
  IosAppService? iosAppService,
  IosCrashReportService? iosCrashReportService,
  IosDeviceService? iosDeviceService,
  IosLogService? iosLogService,
  IosMirrorService? iosMirrorService,
  IosNetworkService? iosNetworkService,
  final IosScreenCapture _iosScreenCapture = const IosScreenCapture(),
  ScrcpyMirror? scrcpyMirror,

  /// The layout helper jar's path on this machine; tests pass their own.
  final Future<String> Function() _inspectorHelperJar =
      extractInspectorHelperJar,
}) {
  final AdbTool _adbTool;
  final IosAppService _iosAppService;
  final IosCrashReportService _iosCrashReportService;
  final IosDeviceService _iosDeviceService;
  final IosLogService _iosLogService;
  final IosMirrorService _iosMirrorService;
  final IosNetworkService _iosNetworkService;
  final ScrcpyMirror _scrcpyMirror;
  final AppLogger _logger = AppLogger(source: 'DeviceSessionService');
  final Map<String, String> _pidToPackageCache = {};

  /// Shared PID→package refresh timer, ref-counted by [_pidCacheConsumers] so
  /// concurrent Android log streams share a single `ps -A` poll.
  Timer? _pidCacheRefreshTimer;
  int _pidCacheConsumers = 0;

  /// Minimum gap between a requested refresh and the end of the previous
  /// `ps -A`, polled or requested; see [requestPidToPackageRefresh].
  @visibleForTesting
  static Duration pidRefreshMinInterval = const Duration(seconds: 1);
  DateTime? _lastPidRefreshAt;
  Future<void>? _pidRefreshInFlight;
  bool _pidRefreshRequested = false;
  final StreamController<Map<String, String>> _pidToPackageUpdates =
      StreamController.broadcast();

  /// Number of live log streams currently open for this device. Each live tab
  /// owns an independent stream (see [startLogStream]); this is just a counter
  /// for [isLogStreamActive].
  int _activeStreamCount = 0;

  /// Optional human-readable label used to tag [AppLogger] entries. Defaults to
  /// the device id when unset.
  String? sessionLabel;

  String get _deviceId => device.id;

  this
    : _adbTool = adbTool ?? AdbTool(executablePath: adbPath),
      _iosAppService =
          iosAppService ??
          _defaultIosAppService(ideviceInstallerTool, ideviceInstallerPath),
      _iosCrashReportService =
          iosCrashReportService ??
          _defaultIosCrashReportService(
            ideviceCrashReportTool,
            ideviceCrashReportPath,
          ),
      _iosDeviceService = iosDeviceService ?? createIosDeviceService(),
      _iosLogService =
          iosLogService ??
          _defaultIosLogService(ideviceSyslogTool, ideviceSyslogPath),
      _iosMirrorService = iosMirrorService ?? createIosMirrorService(),
      _iosNetworkService = iosNetworkService ?? createIosNetworkService(),
      _scrcpyMirror =
          scrcpyMirror ??
          ScrcpyMirror(
            adbExecutablePath:
                resolveBundledExecutablePath('adb') ?? adbPath ?? 'adb',
            serverJarPath:
                '${resolveBundledToolsDirectory()?.path}/scrcpy-server',
            onLog: (message) =>
                AppLogger(source: 'DeviceSessionService')
                    .info('[scrcpy] $message'),
          );

  /// See [_defaultIosLogService] — same reasoning for crash reports.
  static IosCrashReportService _defaultIosCrashReportService(
    IdeviceCrashReportTool? tool,
    String? executablePath,
  ) {
    if (tool != null || executablePath != null) {
      return LibimobiledeviceIosCrashReportService(
        ideviceCrashReportTool:
            tool ?? IdeviceCrashReportTool(executablePath: executablePath),
      );
    }
    return createIosCrashReportService();
  }

  /// See [_defaultIosLogService] — same reasoning for the installer.
  static IosAppService _defaultIosAppService(
    IdeviceInstallerTool? tool,
    String? executablePath,
  ) {
    if (tool != null || executablePath != null) {
      return LibimobiledeviceIosAppService(
        ideviceInstallerTool:
            tool ?? IdeviceInstallerTool(executablePath: executablePath),
      );
    }
    return createIosAppService();
  }

  /// An explicitly supplied tool or executable path pins the libimobiledevice
  /// backend — that is what a caller passing one is asking for, and it is how
  /// the session tests point the stream at a stub executable.
  static IosLogService _defaultIosLogService(
    IdeviceSyslogTool? tool,
    String? executablePath,
  ) {
    if (tool != null || executablePath != null) {
      return LibimobiledeviceIosLogService(
        ideviceSyslogTool:
            tool ?? IdeviceSyslogTool(executablePath: executablePath),
      );
    }
    return createIosLogService();
  }

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

    final session = _iosLogService.startSyslog(
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

  /// Broader device info (identity, battery, storage, display, connectivity,
  /// cellular, developer state, software) for the device home screen. See
  /// [AdbTool.fetchDeviceInfo] / [buildIosDeviceInfo] for what each platform
  /// can and can't reliably report.
  Future<DeviceInfo> fetchDeviceInfo() {
    return switch (device) {
      final AndroidDevice d => _adbTool.fetchDeviceInfo(d),
      final IosDevice d => _fetchIosDeviceInfo(d),
    };
  }

  Future<DeviceInfo> _fetchIosDeviceInfo(IosDevice device) async {
    return buildIosDeviceInfo(
      device,
      await _iosDeviceService.readDeviceDomains(device.id),
    );
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
    await _pidToPackageUpdates.close();
    final iconTempDir = _iconTempDir;
    if (iconTempDir != null) {
      try {
        if (await iconTempDir.exists()) {
          await iconTempDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<DeviceCommandResult> installApp({required String filePath}) {
    return switch (device) {
      AndroidDevice() => _adbTool.installApk(
        deviceId: _deviceId,
        apkPath: filePath,
      ),
      IosDevice() => _iosAppService.installApp(
        deviceId: _deviceId,
        appPath: filePath,
      ),
    };
  }

  Future<List<InstalledAppInfo>> listRecentlyInstalledApps() {
    return switch (device) {
      AndroidDevice() => _adbTool.listRecentlyInstalledApps(_deviceId),
      IosDevice() => _iosAppService.listApps(_deviceId).then(takeRecentIosApps),
    };
  }

  // ── Apps feature (device-wide app management) ───────────────────────────

  /// Full app inventory for the Apps feature. [includeSystemApps] adds the
  /// preinstalled apps, where [canListSystemApps].
  Future<List<AppInfo>> listApps({bool includeSystemApps = false}) {
    return switch (device) {
      AndroidDevice() => _adbTool.listApps(
        _deviceId,
        includeSystemApps: includeSystemApps,
      ),
      IosDevice() =>
        _iosAppService
            .listApps(_deviceId, includeSystemApps: includeSystemApps)
            .then(sortIosApps),
    };
  }

  /// Whether [listApps] can include system apps: always on Android, and on
  /// iOS unless the CLI backend is in use.
  bool get canListSystemApps => switch (device) {
    AndroidDevice() => true,
    IosDevice() => _iosAppService.listsSystemApps,
  };

  Future<DeviceCommandResult> uninstallApp(String packageName) {
    return switch (device) {
      AndroidDevice() => _adbTool.uninstallApp(_deviceId, packageName),
      IosDevice() => _iosAppService.uninstallApp(
        deviceId: _deviceId,
        bundleId: packageName,
      ),
    };
  }

  /// Whether [launchApp] and [forceStopApp] work: always on Android; on iOS
  /// only while the phone offers CoreDevice's app service (Developer Mode and
  /// Xcode's developer disk image), which opening a tunnel finds out.
  Future<bool> canControlApps() => switch (device) {
    AndroidDevice() => Future.value(true),
    IosDevice() => _iosAppService.canControlApps(_deviceId),
  };

  /// Opens [packageName]: its launcher activity on Android.
  Future<DeviceCommandResult> launchApp(String packageName) {
    return switch (device) {
      AndroidDevice() => _adbTool.launchApp(_deviceId, packageName),
      IosDevice() => _iosAppService.launchApp(
        deviceId: _deviceId,
        bundleId: packageName,
      ),
    };
  }

  /// Force-stops [packageName], extensions and services included.
  Future<DeviceCommandResult> forceStopApp(String packageName) {
    return switch (device) {
      AndroidDevice() => _adbTool.forceStopApp(_deviceId, packageName),
      IosDevice() => _iosAppService.forceStopApp(
        deviceId: _deviceId,
        bundleId: packageName,
      ),
    };
  }

  /// Wipes [packageName]'s data and cache. Irreversible — the caller must
  /// confirm with the user first. On iOS only a debug build can be cleared
  /// ([AppInfo.isDebuggable]).
  Future<DeviceCommandResult> clearAppData(String packageName) {
    return switch (device) {
      AndroidDevice() => _adbTool.clearAppData(_deviceId, packageName),
      IosDevice() => _iosAppService.clearAppData(
        deviceId: _deviceId,
        bundleId: packageName,
      ),
    };
  }

  /// Whether [clearAppData] exists for this device: always on Android, and
  /// on iOS unless the CLI backend is in use.
  bool get canClearAppData => switch (device) {
    AndroidDevice() => true,
    IosDevice() => _iosAppService.clearsAppData,
  };

  /// Opens the OS "App info" settings screen for [packageName]. Android only.
  Future<void> openAppInfoSettings(String packageName) {
    if (device is! AndroidDevice) {
      throw UnsupportedError(
        'Opening app info is currently supported for Android devices only.',
      );
    }
    return _adbTool.openAppInfoSettings(_deviceId, packageName);
  }

  /// Best-effort launcher icon and user-visible label for [packageName].
  /// Returns null when the device couldn't be read (worth asking again);
  /// either half is null when it can't be resolved — never throws.
  ///
  /// Android pulls the APK to a scratch temp directory, extracts both via
  /// [ApkIconExtractor], then deletes the pulled APK. iOS asks SpringBoard for
  /// the icon alone: its installer already reports names.
  Future<({Uint8List? icon, String? label})?> fetchAppDetails(
    String packageName,
  ) {
    return switch (device) {
      AndroidDevice() => _fetchAndroidAppDetails(packageName),
      IosDevice() => _fetchIosAppDetails(packageName),
    };
  }

  Future<({Uint8List? icon, String? label})?> _fetchIosAppDetails(
    String bundleId,
  ) async {
    try {
      final icon = await _iosAppService.fetchAppIcon(
        deviceId: _deviceId,
        bundleId: bundleId,
      );
      return (icon: icon, label: null);
    } catch (error) {
      _sessionLogger.error(
        'Failed to fetch the icon for $bundleId',
        detail: error.toString(),
      );
      return null;
    }
  }

  Future<({Uint8List? icon, String? label})?> _fetchAndroidAppDetails(
    String packageName,
  ) async {
    File? localApk;
    try {
      final apkPath = await _adbTool.getApkPath(_deviceId, packageName);
      if (apkPath == null) return null;

      final tempDir = await _ensureIconTempDir();
      final safePackageName = packageName.replaceAll(RegExp(r'[\\/]'), '_');
      localApk = File('${tempDir.path}/$safePackageName.apk');
      await _adbTool.pullFile(_deviceId, apkPath, localApk.path);
      if (!await localApk.exists()) return null;

      final bytes = await localApk.readAsBytes();
      return ApkIconExtractor.extractDetails(bytes);
    } catch (error) {
      _sessionLogger.error(
        'Failed to fetch app details for $packageName',
        detail: error.toString(),
      );
      return null;
    } finally {
      if (localApk != null) {
        try {
          if (await localApk.exists()) await localApk.delete();
        } catch (_) {}
      }
    }
  }

  Directory? _iconTempDir;
  Future<Directory>? _iconTempDirCreation;

  Future<Directory> _ensureIconTempDir() {
    final existing = _iconTempDir;
    if (existing != null) return Future.value(existing);
    return _iconTempDirCreation ??= Directory.systemTemp
        .createTemp('eagly-app-icons-')
        .then((dir) => _iconTempDir = dir);
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
    return _iosCrashReportService.pullReports(_deviceId);
  }

  // ── Network inspection ────────────────────────────────────────────────

  /// The iOS ports this session holds an Inspektor tunnel to. They are not
  /// probed: a probe is a connection the app sees, and the app is there for as
  /// long as the connection through the tunnel lasts.
  final Set<int> _tunnelledIosPorts = {};

  /// The Inspektor servers listening on the device right now. Android: their
  /// abstract sockets in `/proc/net/unix`. iOS: the ports in [inspektorPorts]
  /// that accept a connection over usbmux.
  Future<List<InspektorEndpoint>> findInspektorEndpoints() async {
    switch (device) {
      case AndroidDevice():
        final lines = await _adbTool.grepProcNetUnix(
          _deviceId,
          inspektorSocketMarker,
        );
        return parseInspektorSockets(lines);
      case IosDevice():
        final open = {
          ..._tunnelledIosPorts,
          ...await _iosNetworkService.probePorts(_deviceId, [
            for (final port in inspektorPorts)
              if (!_tunnelledIosPorts.contains(port)) port,
          ]),
        };
        return [
          for (final port in inspektorPorts)
            if (open.contains(port)) InspektorEndpoint.tcp(port),
        ];
    }
  }

  /// Opens a host-side tunnel to [endpoint]: from a free loopback port, an
  /// `adb forward` to its abstract socket on Android, a usbmux forward to its
  /// port on iOS.
  Future<InspektorTunnel> openInspektorTunnel(
    InspektorEndpoint endpoint,
  ) async {
    switch (device) {
      case AndroidDevice():
        final port = await _adbTool.forwardToAbstractSocket(
          _deviceId,
          endpoint.name,
        );
        return InspektorTunnel(
          host: InternetAddress.loopbackIPv4,
          port: port,
          close: () => _adbTool.removeForward(_deviceId, port),
        );
      case IosDevice():
        final devicePort = endpoint.port;
        if (devicePort == null) {
          throw ArgumentError.value(endpoint, 'endpoint', 'has no iOS port');
        }
        final port = await _iosNetworkService.forwardPort(
          _deviceId,
          devicePort,
        );
        _tunnelledIosPorts.add(devicePort);
        return InspektorTunnel(
          host: InternetAddress.loopbackIPv4,
          port: port,
          close: () {
            _tunnelledIosPorts.remove(devicePort);
            return _iosNetworkService.removeForward(port);
          },
        );
    }
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

  /// Captures a full-resolution PNG screenshot: `screencap` on Android,
  /// CoreDevice's screenshot service on iOS.
  Future<Uint8List> captureScreenshot() => switch (device) {
    AndroidDevice() => _adbTool.captureScreenshotPng(_deviceId),
    IosDevice() => _iosMirrorService.captureScreenshot(_deviceId),
  };

  // ── Layout inspector (docs/LAYOUT_INSPECTOR.md) ───────────────────────

  /// Where the helper jar lives on the device.
  static const _inspectorHelperDevicePath =
      '/data/local/tmp/eagly-inspector.jar';

  /// The UI as `uiautomator dump` sees it, with a `screencap` taken at the
  /// same time: ~2 s, the active window only. The route that needs nothing
  /// but adb, for when the helper can't run. Android only.
  Future<LayoutSnapshot> captureLayoutWithUiAutomator() async {
    final started = DateTime.now();
    final (dump, screenshot) = await (
      _adbTool.dumpUiHierarchy(_deviceId),
      _adbTool.captureScreenshotPng(_deviceId),
    ).wait;
    return parseUiAutomatorDump(
      dump,
      displaySize: pngSize(screenshot) ?? Size.zero,
      screenshot: screenshot,
      capturedAt: started,
      elapsed: DateTime.now().difference(started),
    );
  }

  /// The resumed activity's View tree, from `dumpsys activity top`, or null
  /// when it printed none. Android only.
  Future<ViewHierarchy?> dumpViewHierarchy() async =>
      ViewHierarchy.parse(await _adbTool.dumpTopActivity(_deviceId));

  /// Pushes the layout helper and starts it. Throws an
  /// [InspectorHelperException] when it can't connect — most often because
  /// another UI Automation client holds the connection. Android only.
  Future<InspectorHelper> startInspectorHelper() async {
    await _adbTool.pushFile(
      _deviceId,
      await _inspectorHelperJar(),
      _inspectorHelperDevicePath,
    );
    final process = await _adbTool.startAppProcess(
      _deviceId,
      jarPath: _inspectorHelperDevicePath,
      mainClass: inspectorHelperMainClass,
    );
    return InspectorHelper.attach(process);
  }

  // ── iOS screen mirror (docs/IOS_SCREEN_MIRROR.md) ─────────────────────

  /// What the phone offers the mirror through CoreDevice. Never throws.
  Future<IosMirrorSupport> probeIosMirror() =>
      _iosMirrorService.probe(_deviceId);

  /// Starts QuickTime's capture route for this phone: macOS only. Throws
  /// [IosScreenCaptureException].
  Future<IosScreenCaptureHandle> startIosScreenCapture() =>
      _iosScreenCapture.start(device.name ?? '');

  /// PNG screenshots back to back, where the capture route is not available.
  Stream<Uint8List> iosScreenshots() =>
      _iosMirrorService.screenshots(_deviceId);

  Future<IosInputSession> startIosInput() =>
      _iosMirrorService.startInput(_deviceId);

  Future<IosInterfaceOrientation> iosInterfaceOrientation() =>
      _iosMirrorService.interfaceOrientation(_deviceId);

  /// Cycles the device display orientation (0→1→2→3) via `settings`.
  Future<void> rotateDevice() async {
    final current = await _adbTool.getUserRotation(_deviceId);
    await _adbTool.setUserRotation(_deviceId, current + 1);
  }

  /// Starts an on-device `screenrecord`. Finalize + save it via
  /// [ScreenRecordingSession.save].
  Future<ScreenRecordingSession> startScreenRecording({
    int bitRate = 8000000,
  }) async {
    final devicePath =
        '/sdcard/eagly-rec-${DateTime.now().millisecondsSinceEpoch}.mp4';
    // screenrecord's own cap; it stops writing (and keeps the file) there.
    const timeLimit = Duration(minutes: 3);
    final process = await _adbTool.startScreenRecord(
      _deviceId,
      devicePath,
      bitRate: bitRate,
      timeLimitSeconds: timeLimit.inSeconds,
    );
    return ScreenRecordingSession(
      adbTool: _adbTool,
      deviceId: _deviceId,
      devicePath: devicePath,
      process: process,
      timeLimit: timeLimit,
    );
  }

  // ── Utilities feature (generic tool invocations) ────────────────────────

  /// Lazily-created runners for the bundled CLIs, keyed by executable name.
  /// `adb` reuses the session's [AdbTool] so ad-hoc commands go through the
  /// same server startup handling as everything else.
  final Map<String, ToolProcessRunner> _toolRunners = {};

  ToolProcessRunner _toolRunner(String executableName) {
    if (executableName == _adbExecutableName) return _adbTool;
    return _toolRunners[executableName] ??= DeviceToolRunner(
      executableName: executableName,
    );
  }

  static const _adbExecutableName = 'adb';

  /// Runs one [invocation] against the bound device, prepending the tool's
  /// device selector (`adb -s <serial>` / `idevicefoo -u <udid>`). Never
  /// throws: a failure to even start the tool comes back as a non-zero
  /// [ToolCommandResult] carrying the error text.
  Future<ToolCommandResult> runUtility(
    UtilityInvocation invocation, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final runner = _toolRunner(invocation.tool.executable);
    final arguments = [
      invocation.tool.deviceFlag,
      _deviceId,
      ...invocation.arguments,
    ];
    _sessionLogger.info('Running utility: ${invocation.displayCommand}');
    try {
      if (invocation.tool == UtilityTool.adb) {
        await _adbTool.ensureServerRunning();
      }
      return await runner.runTextWithTimeout(arguments, timeout: timeout);
    } catch (error) {
      _sessionLogger.error(
        'Utility failed: ${invocation.displayCommand}',
        detail: error.toString(),
      );
      return ToolCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: error.toString(),
      );
    }
  }

  // ── Terminal feature (free-form tool invocations) ────────────────────────

  /// Starts [invocation] and hands back a live [TerminalProcessSession].
  ///
  /// The argv arrives fully formed — the terminal resolves the device selector
  /// itself, because a terminal tab may deliberately aim at a device other than
  /// the one this repository is bound to. Nothing here rewrites the command;
  /// this only owns process startup, output merging and teardown. Throws when
  /// the tool cannot be started at all.
  ///
  /// Returns `null` when [isCancelled] turns true while the adb server is
  /// still starting: the command is never launched, so a cancelled
  /// `adb reboot` doesn't get to run before it is killed.
  Future<TerminalProcessSession?> startTerminalProcess(
    TerminalInvocation invocation, {
    bool Function()? isCancelled,
  }) async {
    final runner = _toolRunner(invocation.executable);
    _sessionLogger.info('Terminal: ${invocation.displayCommand}');
    if (invocation.executable == _adbExecutableName) {
      await _adbTool.ensureServerRunning();
    }
    if (isCancelled?.call() ?? false) return null;

    final process = await runner.startProcess(invocation.arguments);
    final output = StreamController<TerminalOutputChunk>();
    const decoder = Utf8Decoder(allowMalformed: true);

    var openPipes = 2;
    void closePipe() {
      if (--openPipes == 0 && !output.isClosed) unawaited(output.close());
    }

    StreamSubscription<String> pipe(Stream<List<int>> source, bool isError) {
      return source
          .transform(decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (!output.isClosed) {
                output.add(TerminalOutputChunk(line, isError: isError));
              }
            },
            onError: (Object error) {
              if (!output.isClosed) {
                output.add(
                  TerminalOutputChunk(error.toString(), isError: true),
                );
              }
            },
            onDone: closePipe,
          );
    }

    // Both pipes close on their own when the process ends, which closes
    // [output] — so nothing here cancels them early and drops trailing lines.
    pipe(process.stdout, false);
    pipe(process.stderr, true);
    // Writing to a process that has exited fails with EPIPE, and that error
    // is reported on `stdin.done`, not thrown by `writeln` — unobserved, it
    // escapes as an uncaught async error.
    unawaited(process.stdin.done.catchError((_) {}));

    return TerminalProcessSession(
      output: output.stream,
      exitCode: process.exitCode,
      onKill: () async {
        process.kill(ProcessSignal.sigterm);
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
        }
      },
      onInput: (text) {
        try {
          process.stdin.writeln(text);
        } catch (_) {
          // The process exited between the check and the write; the caller
          // finds out from the exit-code line either way.
        }
      },
    );
  }

  /// Refresh the PID to package name mapping. One `ps -A` runs at a time — an
  /// adb round trip can take a second on a slow device, longer than the
  /// spacing between requests — so a call while one is in flight shares it.
  Future<void> refreshPidToPackageMap() =>
      _pidRefreshInFlight ??= _refreshPidToPackageMap().whenComplete(() {
        _pidRefreshInFlight = null;
        _lastPidRefreshAt = DateTime.now();
      });

  Future<void> _refreshPidToPackageMap() async {
    final next = await _adbTool.getPidToPackageMap(_deviceId);
    final changed = {
      for (final MapEntry(key: pid, value: package) in next.entries)
        if (_pidToPackageCache[pid] != package) pid: package,
    };
    _pidToPackageCache
      ..clear()
      ..addAll(next);
    if (changed.isNotEmpty && !_pidToPackageUpdates.isClosed) {
      _pidToPackageUpdates.add(changed);
    }
  }

  /// The mappings each refresh added or changed: PIDs it sees for the first
  /// time, or whose process changed. Lets a log tab re-evaluate lines that
  /// arrived before the refresh — otherwise they wait for their PID to log
  /// again, which never happens if the process has gone quiet.
  Stream<Map<String, String>> get pidToPackageUpdates =>
      _pidToPackageUpdates.stream;

  /// Asks for the pid→package map to be refreshed soon rather than at the next
  /// poll, for a log line from a PID the map doesn't know yet — typically an
  /// app that has just launched. Requests coalesce into one pending refresh,
  /// starting at least [pidRefreshMinInterval] after the previous `ps -A`
  /// finished, so a burst of unknown PIDs costs at most one refresh per
  /// interval plus round trip. Android only: iOS lines carry their process
  /// name.
  void requestPidToPackageRefresh() {
    if (device is! AndroidDevice ||
        _pidRefreshRequested ||
        _pidToPackageUpdates.isClosed) {
      return;
    }
    _pidRefreshRequested = true;
    unawaited(_runRequestedPidRefresh());
  }

  Future<void> _runRequestedPidRefresh() async {
    // A refresh already under way may have listed processes before the PID
    // behind this request appeared, so it doesn't count: wait it out, then
    // keep the usual spacing after it.
    await _pidRefreshInFlight;
    final last = _lastPidRefreshAt;
    if (last != null) {
      final wait = pidRefreshMinInterval - DateTime.now().difference(last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    if (_pidToPackageUpdates.isClosed) return;
    _pidRefreshRequested = false;
    await refreshPidToPackageMap();
  }

  String? getProcessNameFromPid(String pid) {
    return _pidToPackageCache[pid];
  }
}

/// A running on-device `screenrecord`. Stop it with [save] to finalize the
/// mp4 and copy it to the host, or [cancel] to discard it.
class ScreenRecordingSession({
  required final AdbTool _adbTool,
  required final String deviceId,
  required final String devicePath,
  required final Process process,

  /// How long screenrecord runs before it stops by itself.
  @override required final Duration timeLimit,
}) implements ScreenRecording {
  /// When recording began (roughly: when screenrecord was launched).
  @override
  final DateTime startedAt = DateTime.now();

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
  @override
  Future<void> save(String localPath) async {
    await _finish();
    await _adbTool.pullFile(deviceId, devicePath, localPath);
    await _adbTool.removeFile(deviceId, devicePath);
  }

  /// Stops recording and discards the on-device file without saving.
  @override
  Future<void> cancel() async {
    await _finish();
    await _adbTool.removeFile(deviceId, devicePath);
  }
}
