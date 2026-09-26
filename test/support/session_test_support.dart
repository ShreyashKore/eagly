import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/apps/data/app_info.dart';
import 'package:eagly/features/device_home/data/device_info.dart';
import 'package:eagly/features/logs/data/models/log_column.dart';
import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/features/logs/data/models/log_tab_settings.dart';
import 'package:eagly/features/logs/presentation/models/log_view_mode.dart';
import 'package:eagly/features/terminal/data/terminal_line.dart';
import 'package:eagly/features/terminal/data/terminal_process.dart';
import 'package:eagly/features/terminal/data/terminal_tools.dart';
import 'package:eagly/features/utilities/data/utility_command.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/features/flutter_scrcpy/flutter_scrcpy.dart';
import 'package:eagly/services/device_session_repository.dart';
import 'package:eagly/services/tools/adb_tool.dart';
import 'package:eagly/data/ios_device_info.dart';
import 'package:eagly/services/ios/ios_device_domains.dart';
import 'package:eagly/services/ios/ios_device_service.dart';
import 'package:eagly/services/tools/idevice_info_tool.dart';
import 'package:eagly/services/tools/tool_process_runner.dart';

LogTabSettings testSettings({
  int logLinesLimit = 50000,
  LogFilterViewMode filterViewMode = LogFilterViewMode.classic,
}) {
  return LogTabSettings(
    wrapText: false,
    autoScroll: true,
    selectedLogLevel: LogLevel.verbose,
    filterViewMode: filterViewMode,
    logLinesLimit: logLinesLimit,
    hiddenColumns: const {},
    columnWidths: {
      for (final column in LogColumn.values) column.name: column.defaultWidth,
    },
  );
}

LogEntry testLogEntry({
  required String message,
  String pid = '123',
  String tid = '456',
  String level = 'I',
  String tag = 'TestTag',
  String timestamp = '2026-04-26 10:00:00.000',
  String? packageName,
  String? processName,
}) {
  return LogEntry(
    timestamp: timestamp,
    pid: pid,
    tid: tid,
    level: level,
    tag: tag,
    message: message,
    packageName: packageName,
    processName: processName,
  );
}

/// Fake [DeviceSessionRepository] that records calls and lets tests emit log
/// entries on the live stream.
class FakeSessionService extends DeviceSessionRepository {
  FakeSessionService(Device device)
    : super(
        device: device,
        adbPath: '/usr/bin/true',
        ideviceSyslogPath: '/usr/bin/true',
      );

  int startLogStreamCount = 0;
  int startedMirrorCount = 0;
  int stoppedMirrorCount = 0;
  int pingCount = 0;
  int recoverCount = 0;

  /// Controls what [pingDevice] reports. Set to false to simulate a wedged /
  /// unresponsive device.
  bool pingResult = true;
  final List<String> installRequests = [];
  DeviceCommandResult installResult = DeviceCommandResult.success(
    message: 'Success',
  );
  StreamController<LogEntry>? _activeStream;

  @override
  Stream<LogEntry> startLogStream() {
    startLogStreamCount++;
    final controller = StreamController<LogEntry>();
    _activeStream = controller;
    return controller.stream;
  }

  void emit(LogEntry entry) => _activeStream?.add(entry);

  int pidRefreshRequests = 0;

  @override
  void requestPidToPackageRefresh() => pidRefreshRequests++;

  /// Simulates the underlying tool/pipe dying so the live stream completes.
  Future<void> endStream() async {
    final controller = _activeStream;
    _activeStream = null;
    await controller?.close();
  }

  @override
  Future<bool> pingDevice({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    pingCount++;
    return pingResult;
  }

  @override
  Future<void> recoverConnection() async {
    recoverCount++;
  }

  @override
  Future<DeviceCommandResult> installApp({required String filePath}) async {
    installRequests.add(filePath);
    return installResult;
  }

  /// Loopback control channel handed to the next mirror session, so tests can
  /// assert on the bytes the controller actually writes. Null ⇒ no control.
  FakeScrcpyControlChannel? mirrorControlChannel;

  @override
  Future<ScrcpyMirrorSession> startScreenMirror({
    ScrcpyVideoOptions? options,
  }) async {
    startedMirrorCount++;
    final exitCode = Completer<int>();
    return ScrcpyMirrorSession(
      serial: device.id,
      textureId: 1,
      deviceName: device.id,
      width: 1080,
      height: 1920,
      control: mirrorControlChannel?.control,
      exitCode: exitCode.future,
      streamEnded: Completer<void>().future,
      onStop: () async {
        stoppedMirrorCount++;
        if (!exitCode.isCompleted) {
          exitCode.complete(0);
        }
      },
    );
  }

  // ── Apps feature ──────────────────────────────────────────────────────────
  List<AppInfo> appsToReturn = const [];
  final List<String> uninstallRequests = [];
  DeviceCommandResult uninstallResult = DeviceCommandResult.success(
    message: 'Uninstalled.',
  );
  final List<String> launchRequests = [];
  DeviceCommandResult launchResult = DeviceCommandResult.success(
    message: 'Opened.',
  );
  final List<String> forceStopRequests = [];
  DeviceCommandResult forceStopResult = DeviceCommandResult.success(
    message: 'Force-stopped.',
  );
  final List<String> clearDataRequests = [];
  DeviceCommandResult clearDataResult = DeviceCommandResult.success(
    message: 'Cleared.',
  );
  final List<String> appInfoRequests = [];
  final List<String> iconFetchRequests = [];
  final List<bool> listAppsIncludeSystemAppsRequests = [];
  Uint8List? iconToReturn;

  @override
  Future<List<AppInfo>> listApps({bool includeSystemApps = false}) async {
    listAppsIncludeSystemAppsRequests.add(includeSystemApps);
    return appsToReturn;
  }

  @override
  Future<DeviceCommandResult> uninstallApp(String packageName) async {
    uninstallRequests.add(packageName);
    return uninstallResult;
  }

  @override
  Future<DeviceCommandResult> launchApp(String packageName) async {
    launchRequests.add(packageName);
    return launchResult;
  }

  @override
  Future<DeviceCommandResult> forceStopApp(String packageName) async {
    forceStopRequests.add(packageName);
    return forceStopResult;
  }

  @override
  Future<DeviceCommandResult> clearAppData(String packageName) async {
    clearDataRequests.add(packageName);
    return clearDataResult;
  }

  @override
  Future<void> openAppInfoSettings(String packageName) async {
    appInfoRequests.add(packageName);
  }

  @override
  Future<Uint8List?> fetchAppIcon(String packageName) async {
    iconFetchRequests.add(packageName);
    return iconToReturn;
  }

  // ── Device home feature ──────────────────────────────────────────────────
  DeviceInfo deviceInfoToReturn = const DeviceInfo();
  int fetchDeviceInfoCount = 0;

  @override
  Future<DeviceInfo> fetchDeviceInfo() async {
    fetchDeviceInfoCount++;
    return deviceInfoToReturn;
  }

  // ── Utilities feature ─────────────────────────────────────────────────────
  final List<UtilityInvocation> utilityRequests = [];
  ToolCommandResult utilityResult = const ToolCommandResult(
    exitCode: 0,
    stdout: 'ok',
    stderr: '',
  );

  /// Thrown by [runUtility] when set, to exercise the controller's error path.
  Object? utilityError;

  @override
  Future<ToolCommandResult> runUtility(
    UtilityInvocation invocation, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    utilityRequests.add(invocation);
    final error = utilityError;
    if (error != null) throw error;
    return utilityResult;
  }

  // ── Terminal feature ──────────────────────────────────────────────────────
  final List<TerminalInvocation> terminalRequests = [];
  final List<FakeTerminalProcess> terminalProcesses = [];

  /// Thrown by [startTerminalProcess] when set, to exercise the "tool won't
  /// even start" path.
  Object? terminalStartError;

  @override
  Future<TerminalProcessSession> startTerminalProcess(
    TerminalInvocation invocation,
  ) async {
    terminalRequests.add(invocation);
    final error = terminalStartError;
    if (error != null) throw error;
    final process = FakeTerminalProcess();
    terminalProcesses.add(process);
    return process.session;
  }

  @override
  Future<void> dispose() async {
    await _activeStream?.close();
    _activeStream = null;
    for (final process in terminalProcesses) {
      await process.finish(0);
    }
    await super.dispose();
  }
}

/// A terminal process the test drives by hand: emit output, then [finish] it.
class FakeTerminalProcess {
  final StreamController<TerminalOutputChunk> _output =
      StreamController<TerminalOutputChunk>();
  final Completer<int> _exitCode = Completer<int>();

  final List<String> stdinLines = [];
  bool killed = false;

  late final TerminalProcessSession session = TerminalProcessSession(
    output: _output.stream,
    exitCode: _exitCode.future,
    onKill: () async {
      killed = true;
      await finish(-15);
    },
    onInput: stdinLines.add,
  );

  void emit(String text, {bool isError = false}) {
    if (!_output.isClosed) {
      _output.add(TerminalOutputChunk(text, isError: isError));
    }
  }

  Future<void> finish(int exitCode) async {
    if (!_output.isClosed) await _output.close();
    if (!_exitCode.isCompleted) _exitCode.complete(exitCode);
  }
}

class FakeAdbTool extends AdbTool {
  FakeAdbTool() : super(executablePath: '/usr/bin/true');

  List<Device> androidDevices = const [];
  WirelessServiceDiscoveryResult discoveryResult =
      const WirelessServiceDiscoveryResult();
  final StreamController<List<Device>> _watchController =
      StreamController<List<Device>>.broadcast();

  @override
  Future<List<Device>> getDevices() async => List.of(androidDevices);

  @override
  Future<WirelessServiceDiscoveryResult> discoverMdnsServices() async =>
      discoveryResult;

  @override
  Stream<List<Device>> watchDeviceChanges() => _watchController.stream;

  Future<void> disposeTool() async {
    await _watchController.close();
  }
}

class FakeIosDeviceService implements IosDeviceService {
  List<String> deviceIds = const [];
  bool usbmuxdUnavailableValue = false;
  final Map<String, IosDeviceInfo> infos = {};
  final Map<String, int> describeCalls = {};
  final Map<String, IosDeviceDomains> domains = {};

  @override
  Future<List<String>> listDeviceIds() async => List.of(deviceIds);

  @override
  Future<IosDeviceInfo> describeDevice(String deviceId) async {
    describeCalls.update(deviceId, (count) => count + 1, ifAbsent: () => 1);
    return infos[deviceId] ??
        IosDeviceInfo(deviceId: deviceId, status: 'device');
  }

  @override
  Future<IosDeviceDomains> readDeviceDomains(String deviceId) async =>
      domains[deviceId] ?? const IosDeviceDomains();

  @override
  bool get usbmuxdUnavailable => usbmuxdUnavailableValue;
}

class FakeIdeviceInfoTool extends IdeviceInfoTool {
  FakeIdeviceInfoTool() : super(executablePath: '/usr/bin/true');
}

/// A [ScrcpyControl] wired to a loopback socket, so a test can read back the
/// control messages a controller wrote. `ScrcpyControl` speaks to a real
/// `Socket`, and faking one is more code (and less proof) than connecting two.
class FakeScrcpyControlChannel {
  FakeScrcpyControlChannel._(this._server, this._peer, this.control);

  static Future<FakeScrcpyControlChannel> open() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final client = await Socket.connect(server.address, server.port);
    final peer = await server.first;
    final channel = FakeScrcpyControlChannel._(
      server,
      peer,
      ScrcpyControl(client),
    );
    channel._subscription = peer.listen(channel._received.add);
    return channel;
  }

  final ServerSocket _server;
  final Socket _peer;
  final ScrcpyControl control;

  final BytesBuilder _received = BytesBuilder();
  StreamSubscription<Uint8List>? _subscription;

  /// Every control-message byte written so far.
  Uint8List get bytes => Uint8List.fromList(_received.toBytes());

  /// Waits for the writes in flight to land, then returns everything seen.
  Future<Uint8List> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return bytes;
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await control.close();
    _peer.destroy();
    await _server.close();
  }
}
