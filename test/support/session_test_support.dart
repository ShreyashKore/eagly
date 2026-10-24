import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:eagly/data/device.dart';
import 'package:eagly/features/apps/data/app_info.dart';
import 'package:eagly/features/device_home/data/device_info.dart';
import 'package:eagly/features/logs/data/models/log_column.dart';
import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/features/logs/data/models/log_tab_settings.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_endpoint.dart';
import 'package:eagly/features/terminal/data/terminal_line.dart';
import 'package:eagly/features/terminal/data/terminal_process.dart';
import 'package:eagly/features/terminal/data/terminal_tools.dart';
import 'package:eagly/features/utilities/data/utility_command.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/features/flutter_scrcpy/flutter_scrcpy.dart';
import 'package:eagly/features/mirror/services/ios_screen_capture.dart';
import 'package:eagly/features/mirror/services/screen_recording.dart';
import 'package:eagly/services/device_session_repository.dart';
import 'package:eagly/services/tools/adb_tool.dart';
import 'package:eagly/data/ios_device_info.dart';
import 'package:eagly/services/ios/ios_device_domains.dart';
import 'package:eagly/services/ios/ios_crash_report_service.dart';
import 'package:eagly/services/ios/ios_device_service.dart';
import 'package:eagly/services/ios/ios_mirror_service.dart';
import 'package:eagly/services/tools/idevice_info_tool.dart';
import 'package:eagly/services/tools/tool_process_runner.dart';

LogTabSettings testSettings({int logLinesLimit = 50000}) {
  return LogTabSettings(
    wrapText: false,
    autoScroll: true,
    selectedLogLevel: LogLevel.verbose,
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
class FakeSessionService(Device device) extends DeviceSessionRepository {
  this
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

  final _pidPackageUpdates = StreamController<Map<String, String>>.broadcast();

  @override
  Stream<Map<String, String>> get pidToPackageUpdates =>
      _pidPackageUpdates.stream;

  /// Simulates a `ps -A` refresh that added or changed these mappings.
  void pushPidPackages(Map<String, String> updates) =>
      _pidPackageUpdates.add(updates);

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

  /// When set, [installApp] waits on it, so a test can look at the UI
  /// while an install is still running.
  Completer<void>? installGate;

  @override
  Future<DeviceCommandResult> installApp({required String filePath}) async {
    installRequests.add(filePath);
    await installGate?.future;
    return installResult;
  }

  /// What [pullCrashReports] hands back; refuses when unset.
  CrashReportPullResult? crashReports;

  @override
  Future<CrashReportPullResult> pullCrashReports() async =>
      crashReports ?? (throw CrashReportException('No reports in this test.'));

  /// What [findInspektorEndpoints] reports: no apps unless a test says so.
  List<InspektorEndpoint> inspektorEndpoints = const [];
  int inspektorScans = 0;

  /// How [openInspektorTunnel] answers; refuses when unset.
  Future<InspektorTunnel> Function(InspektorEndpoint endpoint)?
  onOpenInspektorTunnel;

  @override
  Future<List<InspektorEndpoint>> findInspektorEndpoints() async {
    inspektorScans++;
    return inspektorEndpoints;
  }

  @override
  Future<InspektorTunnel> openInspektorTunnel(InspektorEndpoint endpoint) =>
      onOpenInspektorTunnel?.call(endpoint) ??
      Future.error(StateError('No tunnel in this test.'));

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

  // ── iOS screen mirror ─────────────────────────────────────────────────────
  IosMirrorSupport iosMirrorSupport = const IosMirrorSupport(
    screenshots: true,
    input: true,
    pasteboard: true,
    rotation: true,
  );

  /// The next live capture; null fails the start the way denied camera
  /// access does.
  FakeIosScreenCapture? iosCapture = FakeIosScreenCapture();
  int iosCaptureStarts = 0;

  /// What [iosScreenshots] streams.
  final iosScreenshotFeed = StreamController<Uint8List>.broadcast();
  IosInterfaceOrientation iosOrientation = IosInterfaceOrientation.portrait;
  final List<FakeIosInputSession> iosInputs = [];
  Uint8List iosScreenshot = Uint8List.fromList([1, 2, 3]);

  FakeIosInputSession? get lastIosInput =>
      iosInputs.isEmpty ? null : iosInputs.last;

  @override
  Future<IosMirrorSupport> probeIosMirror() async => iosMirrorSupport;

  @override
  Future<IosScreenCaptureHandle> startIosScreenCapture() async {
    iosCaptureStarts++;
    final capture = iosCapture;
    if (capture == null) {
      throw const IosScreenCaptureException(
        'permission_denied',
        'Camera access is off.',
      );
    }
    return capture;
  }

  @override
  Stream<Uint8List> iosScreenshots() => iosScreenshotFeed.stream;

  @override
  Future<IosInputSession> startIosInput() async {
    final input = FakeIosInputSession();
    iosInputs.add(input);
    return input;
  }

  @override
  Future<IosInterfaceOrientation> iosInterfaceOrientation() async =>
      iosOrientation;

  @override
  Future<Uint8List> captureScreenshot() async => iosScreenshot;

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
  Map<String, String> labelsToReturn = {};

  /// Makes [fetchAppDetails] return null, as the real one does when the APK
  /// can't be pulled — as opposed to a pulled APK with no icon to extract.
  bool appPullFails = false;

  /// When set, [fetchAppDetails] waits on this before resolving — lets tests hold
  /// icon fetches in flight to observe concurrency/priority ordering.
  Completer<void>? iconGate;

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

  /// What [canControlApps] answers; Android never asks.
  bool appControl = false;
  int appControlProbes = 0;

  @override
  Future<bool> canControlApps() async {
    appControlProbes++;
    return appControl;
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
  Future<({Uint8List? icon, String? label})?> fetchAppDetails(
    String packageName,
  ) async {
    iconFetchRequests.add(packageName);
    final gate = iconGate;
    if (gate != null) await gate.future;
    if (appPullFails) return null;
    return (icon: iconToReturn, label: labelsToReturn[packageName]);
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

  /// When set, [startTerminalProcess] waits for it before the process exists
  /// — the window in which the real one is still starting the adb server.
  Completer<void>? terminalStartGate;

  @override
  Future<TerminalProcessSession?> startTerminalProcess(
    TerminalInvocation invocation, {
    bool Function()? isCancelled,
  }) async {
    terminalRequests.add(invocation);
    await terminalStartGate?.future;
    if (isCancelled?.call() ?? false) return null;
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

class FakeAdbTool() extends AdbTool {
  this : super(executablePath: '/usr/bin/true');

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

class FakeIdeviceInfoTool() extends IdeviceInfoTool {
  this : super(executablePath: '/usr/bin/true');
}

/// A [ScrcpyControl] wired to a loopback socket, so a test can read back the
/// control messages a controller wrote. `ScrcpyControl` speaks to a real
/// `Socket`, and faking one is more code (and less proof) than connecting two.
class FakeScrcpyControlChannel._(
  final ServerSocket _server,
  final Socket _peer,
  final ScrcpyControl control,
) {
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

/// A QuickTime-route capture whose frames a test delivers by hand.
class FakeIosScreenCapture implements IosScreenCaptureHandle {
  final _sizes = StreamController<Size>.broadcast();
  final _ended = Completer<String>();
  Size? _size;
  bool stopped = false;

  @override
  int get textureId => 7;

  @override
  Stream<Size> get sizes => _sizes.stream;

  @override
  Size? get size => _size;

  @override
  Future<String> get ended => _ended.future;

  /// A frame of [size] arrives: the first one, or a rotation.
  void frame(Size size) {
    _size = size;
    _sizes.add(size);
  }

  /// The capture stops by itself.
  void end(String reason) => _ended.complete(reason);

  @override
  Future<Uint8List?> snapshot() async => Uint8List.fromList([9]);

  /// The latest recording started from this capture.
  FakeScreenRecording? recording;

  @override
  Future<ScreenRecording> record() async => recording = FakeScreenRecording();

  @override
  Future<void> stop() async => stopped = true;
}

/// A recording that notes where it was saved, or that it was thrown away.
class FakeScreenRecording implements ScreenRecording {
  String? savedTo;
  bool cancelled = false;

  @override
  final DateTime startedAt = DateTime.now();

  @override
  Duration? get timeLimit => null;

  @override
  Future<void> save(String localPath) async => savedTo = localPath;

  @override
  Future<void> cancel() async => cancelled = true;
}

/// Records what the mirror sends to an iPhone.
class FakeIosInputSession implements IosInputSession {
  final List<(IosTouchPhase, double, double)> touches = [];
  final List<(int, bool)> keys = [];
  final List<(int, int, bool)> buttons = [];
  final List<String> pasteboard = [];
  final List<IosRotation> rotations = [];
  bool closed = false;

  /// Set to false to make the phone stop taking input.
  bool open = true;

  @override
  bool touch(IosTouchPhase phase, double x, double y) {
    if (open) touches.add((phase, x, y));
    return open;
  }

  @override
  bool key(int usage, {required bool down}) {
    if (open) keys.add((usage, down));
    return open;
  }

  @override
  bool button(int usagePage, int usage, {required bool down}) {
    if (open) buttons.add((usagePage, usage, down));
    return open;
  }

  @override
  Future<void> setPasteboardText(String text) async => pasteboard.add(text);

  @override
  Future<void> rotate(IosRotation rotation) async => rotations.add(rotation);

  @override
  Future<void> close() async {
    closed = true;
    open = false;
  }
}
