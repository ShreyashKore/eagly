import 'dart:async';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/logs/data/models/log_column.dart';
import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/features/logs/data/models/log_tab_settings.dart';
import 'package:eagly/features/logs/presentation/models/log_view_mode.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/features/flutter_scrcpy/flutter_scrcpy.dart';
import 'package:eagly/services/device_session_repository.dart';
import 'package:eagly/services/tools/adb_tool.dart';
import 'package:eagly/services/tools/idevice_id_tool.dart';
import 'package:eagly/services/tools/idevice_info_tool.dart';

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

  /// Simulates the underlying tool/pipe dying so the live stream completes.
  Future<void> endStream() async {
    final controller = _activeStream;
    _activeStream = null;
    await controller?.close();
  }

  @override
  Future<void> stopActiveLogStream() async {
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
      control: null,
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

  @override
  Future<void> dispose() async {
    await _activeStream?.close();
    _activeStream = null;
    await super.dispose();
  }
}

class FakeAdbTool extends AdbTool {
  FakeAdbTool() : super(executablePath: '/usr/bin/true');

  List<Device> androidDevices = const [];
  final StreamController<List<Device>> _watchController =
      StreamController<List<Device>>.broadcast();

  @override
  Future<List<Device>> getDevices() async => List.of(androidDevices);

  @override
  Stream<List<Device>> watchDeviceChanges() => _watchController.stream;

  Future<void> disposeTool() async {
    await _watchController.close();
  }
}

class FakeIdeviceIdTool extends IdeviceIdTool {
  FakeIdeviceIdTool() : super(executablePath: '/usr/bin/true');

  @override
  Future<List<String>> getDeviceIds() async => const [];
}

class FakeIdeviceInfoTool extends IdeviceInfoTool {
  FakeIdeviceInfoTool() : super(executablePath: '/usr/bin/true');
}
