import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:eagly/features/logs/services/log_parsers/logcat_parser.dart';

import '../../data/device.dart';
import '../../features/apps/data/app_info.dart';
import '../../features/device_home/data/installed_app_info.dart';
import '../../features/logs/data/models/log_entry.dart';
import '../../features/wireless_connection/data/wireless_debug_models.dart';
import '../../utils/utils.dart';
import 'tool_process_runner.dart';

class AdbTool extends ToolProcessRunner {
  AdbTool({super.executablePath}) : super(executableName: 'adb');

  static const int _defaultServerPort = 5037;

  Future<void>? _serverStartup;

  /// Ensures an adb server is listening before any command runs. We must not
  /// rely on adb's implicit `start-server`: its fork-server readiness handshake
  /// hangs on some Windows setups (the client never sees the server's "ready"
  /// signal), wedging the very first `adb devices`. Instead we launch the
  /// server directly in `nodaemon` mode as a *detached* process — it binds the
  /// port and runs independently of us — then wait until it accepts
  /// connections. Once up, every normal adb command connects and returns.
  /// Idempotent and cached, so concurrent callers share one startup; a
  /// no-op when a server is already running.
  Future<void> ensureServerRunning() => _serverStartup ??= _startServer();

  Future<void> _startServer() async {
    final port =
        int.tryParse(Platform.environment['ANDROID_ADB_SERVER_PORT'] ?? '') ??
        _defaultServerPort;

    if (await _serverIsListening(port)) return;

    try {
      // Detached so the server's stdio isn't tied to ours (avoiding the
      // inherited-handle hang) and it outlives this call like a normal adb
      // server. A second server can't bind a busy port and simply exits, which
      // is harmless — we connect to whichever server ends up listening.
      await startProcess([
        '-L',
        'tcp:$port',
        'nodaemon',
        'server',
      ], mode: ProcessStartMode.detached);
    } catch (error) {
      logError('Failed to launch adb server', error);
    }

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      if (await _serverIsListening(port)) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    logError('adb server did not start listening on port $port within timeout');
    _serverStartup = null; // allow a retry on the next call
  }

  Future<bool> _serverIsListening(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Device>> getDevices() async {
    try {
      await ensureServerRunning();
      final result = await runText(['devices', '-l']);
      if (!result.isSuccess) {
        logError(
          'adb devices -l returned non-zero exit code',
          '${result.exitCode} ${result.combinedOutput}',
        );
        return const [];
      }

      final deviceList = <Device>[];
      for (final line in result.stdout.split('\n').skip(1)) {
        final parsed = _parseDeviceLine(line);
        if (parsed != null) {
          deviceList.add(parsed);
        }
      }

      logInfo('Found ${deviceList.length} device(s)');
      return deviceList;
    } on ProcessException catch (error) {
      logError('ProcessException while listing Android devices', error);
      return const [];
    } catch (error) {
      logError('Unexpected error while listing Android devices', error);
      return const [];
    }
  }

  Stream<List<Device>> watchDeviceChanges() async* {
    Process? process;

    try {
      await ensureServerRunning();
      process = await startProcess(['track-devices', '-l']);
      await for (final line in stdoutLines(process)) {
        if (line.trim().isEmpty) continue;
        yield await getDevices();
      }
    } finally {
      await stopProcess(process);
    }
  }

  Future<Device> describeDevice(String deviceId) async {
    try {
      final result = await runText(['-s', deviceId, 'shell', 'getprop']);
      if (!result.isSuccess) {
        logError(
          'adb shell getprop returned non-zero exit for $deviceId',
          result.combinedOutput,
        );
        return Device.android(deviceId, 'unavailable');
      }

      final properties = _parseAndroidGetPropOutput(result.stdout);
      final brand = _normalizeAndroidBrand(
        _firstNonEmpty(
          properties['ro.product.brand'],
          properties['ro.product.manufacturer'],
        ),
      );
      final model = _firstNonEmpty(
        properties['ro.product.marketname'],
        properties['ro.product.model'],
      );
      final name = _firstNonEmpty(
        properties['ro.product.device'],
        properties['ro.product.name'],
      );
      final serialNumber = _firstNonEmpty(
        properties['ro.serialno'],
        properties['ro.boot.serialno'],
      );

      return AndroidDevice(
        deviceId,
        'device',
        brand: brand,
        model: model,
        name: name,
        serialNumber: serialNumber,
      );
    } on ProcessException catch (error) {
      logError('ProcessException describing Android device $deviceId', error);
      return Device.android(deviceId, 'unavailable');
    } catch (error) {
      logError('Unexpected error describing Android device $deviceId', error);
      return Device.android(deviceId, 'unavailable');
    }
  }

  Future<WirelessServiceDiscoveryResult> discoverMdnsServices() async {
    try {
      final result = await runText(['mdns', 'services']);
      if (!result.isSuccess) {
        final details = describeCommandFailure(
          'Failed to discover wireless ADB services.',
          result,
        );
        logError('Failed to discover wireless ADB services', details);
        return WirelessServiceDiscoveryResult.failure(error: details);
      }

      final services = <WirelessDebugService>[];
      for (final rawLine in result.stdout.split('\n')) {
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
      logError('Exception while discovering mdns services', error);
      return WirelessServiceDiscoveryResult.failure(
        error:
            'Failed to discover wireless ADB services: ${describeError(error)}',
      );
    }
  }

  Future<DeviceCommandResult> pairDevice({
    required String address,
    required String pairingCode,
  }) async {
    logInfo('Pairing with $address…');
    try {
      final result = await runText(['pair', address, pairingCode]);
      if (!result.isSuccess) {
        final details = describeCommandFailure(
          'Failed to pair with $address.',
          result,
        );
        logError('Pair command failed for $address', details);
        return DeviceCommandResult.failure(error: details);
      }

      final message = result.combinedOutput;
      logSuccess('Paired with $address');
      return DeviceCommandResult.success(
        message: message.isEmpty
            ? 'Successfully paired with $address.'
            : message,
      );
    } catch (error) {
      logError('Exception while pairing with $address', error);
      return DeviceCommandResult.failure(
        error: 'Failed to pair with $address: ${describeError(error)}',
      );
    }
  }

  Future<DeviceCommandResult> connectDevice(String address) async {
    logInfo('Connecting to $address…');
    try {
      final result = await runText(['connect', address]);
      final output = result.combinedOutput;
      final failed =
          !result.isSuccess || output.toLowerCase().contains('failed');

      if (failed) {
        final details = describeCommandFailure(
          'Failed to connect to $address.',
          result,
        );
        logError('Connect command failed for $address', details);
        return DeviceCommandResult.failure(error: details);
      }

      logSuccess('Connected to $address');
      return DeviceCommandResult.success(
        message: output.isEmpty ? 'Connected to $address.' : output,
      );
    } catch (error) {
      logError('Exception while connecting to $address', error);
      return DeviceCommandResult.failure(
        error: 'Failed to connect to $address: ${describeError(error)}',
      );
    }
  }

  Future<DeviceCommandResult> installApk({
    required String deviceId,
    required String apkPath,
  }) async {
    try {
      final result = await runText(['-s', deviceId, 'install', '-r', apkPath]);
      final output = result.combinedOutput;
      final failed = !result.isSuccess || _looksLikeInstallFailure(output);

      if (failed) {
        final details = describeCommandFailure(
          'Failed to install APK on $deviceId.',
          result,
        );
        logError('APK install failed for $deviceId', details);
        return DeviceCommandResult.failure(error: details);
      }

      return DeviceCommandResult.success(
        message: output.isEmpty ? 'Installed APK on $deviceId.' : output,
      );
    } catch (error) {
      logError('Exception while installing APK on $deviceId', error);
      return DeviceCommandResult.failure(
        error: 'Failed to install APK on $deviceId: ${describeError(error)}',
      );
    }
  }

  Future<Map<String, String>> getPidToPackageMap(String deviceId) async {
    try {
      final result = await runText(['-s', deviceId, 'shell', 'ps', '-A']);
      final pidToPackage = <String, String>{};

      for (final line in result.stdout.split('\n').skip(1)) {
        if (line.trim().isEmpty) continue;

        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 9) {
          pidToPackage[parts[1]] = parts[8];
        }
      }

      return pidToPackage;
    } catch (error) {
      logError('Failed to read PID->package map for $deviceId', error);
      return const {};
    }
  }

  ToolStreamSession<LogEntry> startLogcat(String deviceId) {
    Process? process;
    var stopRequested = false;
    var stopFuture = Future<void>.value();
    late final StreamController<LogEntry> controller;
    final LogcatParser parser = const LogcatParser();

    Future<void> stop() {
      if (stopRequested) {
        return stopFuture;
      }
      stopRequested = true;
      stopFuture = stopProcess(process);
      return stopFuture;
    }

    controller = StreamController<LogEntry>(
      onListen: () async {
        logInfo('Starting logcat for $deviceId');
        try {
          process = await startProcess([
            '-s',
            deviceId,
            'logcat',
            '-v',
            'threadtime',
          ]);
          final stderrFuture = stderrText(process!);
          var emittedLogs = false;

          await for (final line in stdoutLines(process!)) {
            final parsed = parser.parse(line);
            if (parsed != null) {
              emittedLogs = true;
              controller.add(parsed);
            }
          }

          final stderrOutput = (await stderrFuture).trim();
          if (!emittedLogs && stderrOutput.isNotEmpty) {
            controller.add(
              buildToolErrorEntry(
                stderrOutput,
                tag: 'adb logcat',
                processName: deviceId,
              ),
            );
          }
        } on ProcessException catch (error) {
          logError('Failed to start adb logcat for $deviceId', error);
          controller.add(
            buildToolErrorEntry(
              'Failed to start adb logcat: ${describeError(error)}',
              tag: 'adb logcat',
              processName: deviceId,
            ),
          );
        } catch (error) {
          logError(
            'Unexpected error while streaming adb logcat for $deviceId',
            error,
          );
          controller.add(
            buildToolErrorEntry(
              'adb logcat error: ${describeError(error)}',
              tag: 'adb logcat',
              processName: deviceId,
            ),
          );
        } finally {
          logInfo('Logcat stream ended for $deviceId');
          await stop();
          await controller.close();
        }
      },
      onCancel: stop,
    );

    return ToolStreamSession(stream: controller.stream, onStop: stop);
  }

  Future<void> stopLogcat(String deviceId) async {
    logInfo('Stopping logcat for $deviceId');
    await runText(['-s', deviceId, 'shell', 'pkill', 'logcat']);
  }

  /// Best-effort `adb reconnect <id>` to recover a wedged USB/TCP transport.
  /// The device briefly bounces (drops offline then re-enumerates), which the
  /// device watcher observes and reflects in the device list.
  Future<void> reconnectDevice(String deviceId) async {
    logInfo('Reconnecting $deviceId');
    try {
      await runText(['-s', deviceId, 'reconnect']);
    } catch (error) {
      logError('Failed to reconnect $deviceId', error);
    }
  }

  /// Returns true when the device answers a lightweight shell round-trip within
  /// [timeout]. A healthy (even idle) device replies almost immediately, while
  /// a wedged transport hangs — so the timeout elapses and this returns false.
  Future<bool> pingDevice(
    String deviceId, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    Process? process;
    try {
      process = await startProcess(['-s', deviceId, 'shell', 'true']);
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process?.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      return exitCode == 0;
    } catch (error) {
      logError('Liveness probe failed for $deviceId', error);
      return false;
    }
  }

  Future<void> clearLogs(String deviceId) async {
    logInfo('Clearing adb logcat buffer for $deviceId');
    await runText(['-s', deviceId, 'logcat', '-c']);
  }

  /// Captures the device framebuffer as PNG bytes via `screencap`.
  Future<Uint8List> captureScreenshotPng(String deviceId) async {
    final bytes = await runBytes([
      '-s',
      deviceId,
      'exec-out',
      'screencap',
      '-p',
    ]);
    return Uint8List.fromList(bytes);
  }

  /// Starts `screenrecord` writing to [devicePath] on the device. Stop it with
  /// [signalStopScreenRecord] (so the mp4 is finalized), then [pullFile] it.
  Future<Process> startScreenRecord(
    String deviceId,
    String devicePath, {
    int? bitRate,
    int? timeLimitSeconds,
  }) {
    final args = <String>['-s', deviceId, 'shell', 'screenrecord'];
    if (bitRate != null) args.addAll(['--bit-rate', '$bitRate']);
    if (timeLimitSeconds != null) {
      args.addAll(['--time-limit', '$timeLimitSeconds']);
    }
    args.add(devicePath);
    return startProcess(args);
  }

  /// Sends SIGINT to `screenrecord` so it flushes and finalizes the mp4.
  Future<void> signalStopScreenRecord(String deviceId) async {
    await runText(['-s', deviceId, 'shell', 'pkill', '-INT', 'screenrecord']);
  }

  Future<void> pullFile(String deviceId, String devicePath, String localPath) {
    return runText(['-s', deviceId, 'pull', devicePath, localPath]);
  }

  Future<void> removeFile(String deviceId, String devicePath) {
    return runText(['-s', deviceId, 'shell', 'rm', '-f', devicePath]);
  }

  Future<int> getUserRotation(String deviceId) async {
    final result = await runText([
      '-s',
      deviceId,
      'shell',
      'settings',
      'get',
      'system',
      'user_rotation',
    ]);
    return int.tryParse(result.stdout.trim()) ?? 0;
  }

  /// Forces the device display [rotation] (0–3). Disables auto-rotate so it
  /// sticks; the user can re-enable auto-rotate on the device afterwards.
  Future<void> setUserRotation(String deviceId, int rotation) async {
    await runText([
      '-s',
      deviceId,
      'shell',
      'settings',
      'put',
      'system',
      'accelerometer_rotation',
      '0',
    ]);
    await runText([
      '-s',
      deviceId,
      'shell',
      'settings',
      'put',
      'system',
      'user_rotation',
      '${rotation % 4}',
    ]);
  }

  Device? _parseDeviceLine(String line) {
    if (line.trim().isEmpty) return null;

    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;

    final deviceId = parts[0];
    final status = parts[1];

    String? model;
    String? product;

    for (var index = 2; index < parts.length; index++) {
      if (parts[index].startsWith('model:')) {
        model = parts[index].substring('model:'.length);
      } else if (parts[index].startsWith('product:')) {
        product = parts[index].substring('product:'.length);
      }
    }

    return Device.android(deviceId, status, model: model, name: product);
  }

  WirelessDebugServiceType _parseMdnsServiceType(String rawValue) {
    return switch (rawValue.trim()) {
      '_adb-tls-connect._tcp' => WirelessDebugServiceType.connect,
      '_adb-tls-pairing._tcp' => WirelessDebugServiceType.pairing,
      _ => WirelessDebugServiceType.unknown,
    };
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

  String? _normalizeAndroidBrand(String? brand) {
    if (brand == null) {
      return null;
    }

    final trimmed = brand.trim();
    if (trimmed.isEmpty || trimmed != trimmed.toLowerCase()) {
      return trimmed.isEmpty ? null : trimmed;
    }

    final words = trimmed.split(RegExp(r'\s+'));
    return words
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  bool _looksLikeInstallFailure(String output) {
    final normalized = output.toLowerCase();
    return normalized.contains('failure [') ||
        normalized.contains('install_failed') ||
        normalized.contains('failed');
  }

  Map<String, String> _parseAndroidGetPropOutput(String stdout) {
    final properties = <String, String>{};
    final propertyPattern = RegExp(r'^\[([^\]]+)\]:\s*\[(.*)\]$');

    for (final rawLine in stdout.split('\n')) {
      final line = rawLine.trim();
      final match = propertyPattern.firstMatch(line);
      if (match == null) {
        continue;
      }

      final key = match.group(1)?.trim();
      final value = match.group(2)?.trim();
      if (key == null || key.isEmpty || value == null || value.isEmpty) {
        continue;
      }

      properties[key] = value;
    }

    return properties;
  }

  Future<String?> readProcFile(String deviceId, String path) async {
    try {
      final result = await runText(['-s', deviceId, 'shell', 'cat', path]);
      if (!result.isSuccess) return null;
      return result.stdout;
    } catch (_) {
      return null;
    }
  }

  Future<List<InstalledAppInfo>> listRecentlyInstalledApps(
    String deviceId,
  ) async {
    try {
      final apps = await _dumpInstalledApps(deviceId);
      final thirdParty =
          apps
              .where((app) => !app.isSystemApp && app.installTime != null)
              .toList()
            ..sort((a, b) => b.installTime!.compareTo(a.installTime!));

      return thirdParty
          .take(5)
          .map(
            (app) => InstalledAppInfo(
              packageName: app.packageName,
              installTime: app.installTime,
            ),
          )
          .toList();
    } catch (error) {
      logError('Failed to list recently installed apps', error);
      return [];
    }
  }

  /// Full app inventory for the Apps feature — every installed package with
  /// version, system/enabled flags, and on-device APK path, alphabetized.
  /// System apps are excluded by default; pass [includeSystemApps] to see
  /// them too (there can be hundreds on a stock device).
  Future<List<AppInfo>> listApps(
    String deviceId, {
    bool includeSystemApps = false,
  }) async {
    try {
      final apps = await _dumpInstalledApps(deviceId);
      final filtered = includeSystemApps
          ? apps
          : apps.where((app) => !app.isSystemApp).toList();
      filtered.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      return filtered;
    } catch (error) {
      logError('Failed to list apps for $deviceId', error);
      return [];
    }
  }

  Future<DeviceCommandResult> uninstallApp(
    String deviceId,
    String packageName,
  ) async {
    try {
      final result = await runText(['-s', deviceId, 'uninstall', packageName]);
      final output = result.combinedOutput;
      final failed =
          !result.isSuccess || output.toLowerCase().contains('failure');
      if (failed) {
        final details = describeCommandFailure(
          'Failed to uninstall $packageName.',
          result,
        );
        logError('Uninstall failed for $packageName on $deviceId', details);
        return DeviceCommandResult.failure(error: details);
      }

      logSuccess('Uninstalled $packageName from $deviceId');
      return DeviceCommandResult.success(message: 'Uninstalled $packageName.');
    } catch (error) {
      logError('Exception while uninstalling $packageName on $deviceId', error);
      return DeviceCommandResult.failure(
        error: 'Failed to uninstall $packageName: ${describeError(error)}',
      );
    }
  }

  /// Launches [packageName]'s launcher activity via the well-known `monkey`
  /// single-event trick (`-p <pkg> -c android.intent.category.LAUNCHER 1`) —
  /// works without first resolving the app's actual launch component.
  Future<DeviceCommandResult> launchApp(
    String deviceId,
    String packageName,
  ) async {
    try {
      final result = await runText([
        '-s',
        deviceId,
        'shell',
        'monkey',
        '-p',
        packageName,
        '-c',
        'android.intent.category.LAUNCHER',
        '1',
      ]);
      final output = result.combinedOutput.toLowerCase();
      final failed =
          !result.isSuccess ||
          output.contains('no activities found') ||
          output.contains('aborting');
      if (failed) {
        final details = describeCommandFailure(
          'Failed to open $packageName.',
          result,
        );
        logError('Launch failed for $packageName on $deviceId', details);
        return DeviceCommandResult.failure(error: details);
      }

      return DeviceCommandResult.success(message: 'Opened $packageName.');
    } catch (error) {
      logError('Exception while launching $packageName on $deviceId', error);
      return DeviceCommandResult.failure(
        error: 'Failed to open $packageName: ${describeError(error)}',
      );
    }
  }

  Future<DeviceCommandResult> forceStopApp(
    String deviceId,
    String packageName,
  ) async {
    try {
      final result = await runText([
        '-s',
        deviceId,
        'shell',
        'am',
        'force-stop',
        packageName,
      ]);
      if (!result.isSuccess) {
        final details = describeCommandFailure(
          'Failed to force-stop $packageName.',
          result,
        );
        logError('Force-stop failed for $packageName on $deviceId', details);
        return DeviceCommandResult.failure(error: details);
      }
      return DeviceCommandResult.success(
        message: 'Force-stopped $packageName.',
      );
    } catch (error) {
      logError(
        'Exception while force-stopping $packageName on $deviceId',
        error,
      );
      return DeviceCommandResult.failure(
        error: 'Failed to force-stop $packageName: ${describeError(error)}',
      );
    }
  }

  /// Wipes [packageName]'s data and cache via `pm clear` — irreversible, the
  /// caller must confirm with the user first.
  Future<DeviceCommandResult> clearAppData(
    String deviceId,
    String packageName,
  ) async {
    try {
      final result = await runText([
        '-s',
        deviceId,
        'shell',
        'pm',
        'clear',
        packageName,
      ]);
      final output = result.combinedOutput;
      final failed =
          !result.isSuccess || !output.toLowerCase().contains('success');
      if (failed) {
        final details = describeCommandFailure(
          'Failed to clear data for $packageName.',
          result,
        );
        logError('Clear data failed for $packageName on $deviceId', details);
        return DeviceCommandResult.failure(error: details);
      }

      return DeviceCommandResult.success(
        message: 'Cleared data for $packageName.',
      );
    } catch (error) {
      logError(
        'Exception while clearing data for $packageName on $deviceId',
        error,
      );
      return DeviceCommandResult.failure(
        error: 'Failed to clear data for $packageName: ${describeError(error)}',
      );
    }
  }

  /// Opens the OS "App info" settings screen for [packageName].
  Future<void> openAppInfoSettings(String deviceId, String packageName) async {
    await runText([
      '-s',
      deviceId,
      'shell',
      'am',
      'start',
      '-a',
      'android.settings.APPLICATION_DETAILS_SETTINGS',
      '-d',
      'package:$packageName',
    ]);
  }

  /// Resolves the on-device path to [packageName]'s base APK (preferred over
  /// any split APKs) via `pm path`, for icon extraction.
  Future<String?> getApkPath(String deviceId, String packageName) async {
    try {
      final result = await runText([
        '-s',
        deviceId,
        'shell',
        'pm',
        'path',
        packageName,
      ]);
      if (!result.isSuccess) return null;

      String? firstPath;
      for (final rawLine in result.stdout.split('\n')) {
        final line = rawLine.trim();
        if (!line.startsWith('package:')) continue;
        final path = line.substring('package:'.length).trim();
        firstPath ??= path;
        if (path.endsWith('base.apk')) return path;
      }
      return firstPath;
    } catch (error) {
      logError(
        'Failed to resolve APK path for $packageName on $deviceId',
        error,
      );
      return null;
    }
  }

  /// Parses `dumpsys package packages` into one [AppInfo] per package block —
  /// the shared source for [listApps] (full inventory) and
  /// [listRecentlyInstalledApps] (top-5 third-party by install time).
  Future<List<AppInfo>> _dumpInstalledApps(String deviceId) async {
    final pkgsResult = await runText([
      '-s',
      deviceId,
      'shell',
      'pm',
      'list',
      'packages',
      '-3',
    ]);
    final thirdParty = <String>{};
    final thirdPartyEnumerated = pkgsResult.isSuccess;
    if (thirdPartyEnumerated) {
      for (final line in pkgsResult.stdout.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('package:')) {
          thirdParty.add(trimmed.substring('package:'.length));
        }
      }
    }

    final dumpsysResult = await runText([
      '-s',
      deviceId,
      'shell',
      'dumpsys',
      'package',
      'packages',
    ]);
    if (!dumpsysResult.isSuccess) return [];

    final apps = <AppInfo>[];
    String? currentPackage;
    String? versionName;
    String? versionCode;
    DateTime? firstInstall;
    DateTime? lastUpdate;
    String? codePath;
    var sawSystemFlag = false;
    var sawEnabledLine = false;
    var sawEnabledFalse = false;

    void flush() {
      final packageName = currentPackage;
      if (packageName == null) return;
      apps.add(
        AppInfo(
          packageName: packageName,
          versionName: versionName,
          versionCode: versionCode,
          isSystemApp: thirdPartyEnumerated
              ? (sawSystemFlag || !thirdParty.contains(packageName))
              : sawSystemFlag,
          isEnabled: sawEnabledLine ? !sawEnabledFalse : true,
          apkPath: codePath,
          installTime: firstInstall,
          updateTime: lastUpdate,
        ),
      );
    }

    for (final rawLine in dumpsysResult.stdout.split('\n')) {
      final line = rawLine.trim();

      final pkgMatch = RegExp(r'^Package\s*\[([^\]]+)\]').firstMatch(line);
      if (pkgMatch != null) {
        flush();
        currentPackage = pkgMatch.group(1)!;
        versionName = null;
        versionCode = null;
        firstInstall = null;
        lastUpdate = null;
        codePath = null;
        sawSystemFlag = false;
        sawEnabledLine = false;
        sawEnabledFalse = false;
        continue;
      }
      if (currentPackage == null) continue;

      final versionNameMatch = RegExp(r'versionName=(\S+)').firstMatch(line);
      if (versionNameMatch != null) versionName = versionNameMatch.group(1);

      final versionCodeMatch = RegExp(r'versionCode=(\d+)').firstMatch(line);
      if (versionCodeMatch != null) versionCode = versionCodeMatch.group(1);

      final firstInstallMatch = RegExp(
        r'firstInstallTime=(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})',
      ).firstMatch(line);
      if (firstInstallMatch != null) {
        firstInstall = DateTime.tryParse(firstInstallMatch.group(1)!);
      }

      final lastUpdateMatch = RegExp(
        r'lastUpdateTime=(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})',
      ).firstMatch(line);
      if (lastUpdateMatch != null) {
        lastUpdate = DateTime.tryParse(lastUpdateMatch.group(1)!);
      }

      final codePathMatch = RegExp(r'^codePath=(.+)$').firstMatch(line);
      if (codePathMatch != null) codePath = codePathMatch.group(1)!.trim();

      if (line.startsWith('flags=') || line.startsWith('pkgFlags=')) {
        if (line.contains('SYSTEM')) sawSystemFlag = true;
      }

      if (!sawEnabledLine) {
        final enabledMatch = RegExp(r'\benabled=(\d+)').firstMatch(line);
        if (enabledMatch != null) {
          sawEnabledLine = true;
          final value = int.tryParse(enabledMatch.group(1)!) ?? 0;
          // COMPONENT_ENABLED_STATE_DISABLED = 2,
          // COMPONENT_ENABLED_STATE_DISABLED_USER = 3.
          sawEnabledFalse = value == 2 || value == 3;
        }
      }
    }
    flush();

    return apps;
  }
}
