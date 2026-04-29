import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logview/ui/log_tab_view/log_tab_controller.dart';
import 'package:logview/data/device.dart';
import 'package:logview/data/log_column.dart';
import 'package:logview/data/log_entry.dart';
import 'package:logview/data/log_tab_settings.dart';
import 'package:logview/services/device_repository.dart';
import 'package:logview/services/device_session_service.dart';
import 'package:logview/services/tools/adb_tool.dart';
import 'package:logview/services/tools/idevice_id_tool.dart';
import 'package:logview/services/tools/idevice_info_tool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeControllerSessionService sessionService;
  late _FakeControllerAdbTool adbTool;
  late _FakeControllerIdeviceIdTool ideviceIdTool;
  late _FakeControllerIdeviceInfoTool ideviceInfoTool;
  late DeviceRepository repository;
  LogTabController? controller;

  LogTabController createController() {
    return LogTabController(
      id: 'tab-1',
      initialTitle: 'Tab 1',
      initialSettings: _initialSettings(),
      deviceRepository: repository,
      deviceSessionService: sessionService,
    );
  }

  setUp(() {
    sessionService = _FakeControllerSessionService();
    adbTool = _FakeControllerAdbTool();
    ideviceIdTool = _FakeControllerIdeviceIdTool();
    ideviceInfoTool = _FakeControllerIdeviceInfoTool();
    repository = DeviceRepository.forTesting(
      adbTool: adbTool,
      ideviceIdTool: ideviceIdTool,
      ideviceInfoTool: ideviceInfoTool,
    );
  });

  tearDown(() {
    controller?.dispose();
    repository.dispose();
    adbTool.dispose();
    sessionService.dispose();
  });

  test(
    'bootstrapInitialLoad auto-selects a single connected device and starts logs',
    () async {
      adbTool.androidDevices = [
        Device('emulator-5554', 'device', platform: DevicePlatform.android),
      ];
      controller = createController();

      await controller!.bootstrapInitialLoad();

      expect(controller!.selectedDevice?.id, 'emulator-5554');
      expect(controller!.showGetStarted, isFalse);
      expect(controller!.isRunning, isTrue);
      expect(sessionService.startedLogStreamDeviceIds, ['emulator-5554']);
    },
  );

  test('submitLogLinesLimit rejects values below minimum threshold', () {
    controller = createController();

    final submitted = controller!.submitLogLinesLimit('999');

    expect(submitted, isFalse);
    expect(controller!.logLinesLimit, 50000);
    expect(controller!.editingLogLinesLimit, isFalse);
  });

  test('submitLogLinesLimit trims existing logs to the new limit', () {
    controller = createController();

    controller!.logs = List.generate(
      1005,
      (index) => LogEntry(
        timestamp: '2026-04-26 10:00:${index.toString().padLeft(2, '0')}.000',
        pid: '$index',
        tid: '$index',
        level: 'I',
        tag: 'Tag$index',
        message: 'Message $index',
      ),
    );

    final submitted = controller!.submitLogLinesLimit('1000');

    expect(submitted, isTrue);
    expect(controller!.logLinesLimit, 1000);
    expect(controller!.logs, hasLength(1000));
    expect(controller!.logs.first.message, 'Message 5');
    expect(controller!.logLinesController.text, '1000');
  });

  test('searchMatchIndices ignore hidden columns when computing matches', () {
    controller = createController();

    controller!.logs = [
      LogEntry(
        timestamp: '2026-04-26 10:00:00.000',
        pid: '123',
        tid: '456',
        level: 'I',
        tag: 'VisibleTag',
        message: 'HiddenNeedle',
      ),
    ];

    controller!.onInlineSearchChanged('HiddenNeedle');
    controller!.setHiddenColumns({LogColumn.message.name});
    controller!.setSearchCaseSensitive(true);

    expect(controller!.searchMatchIndices, isEmpty);
  });
}

LogTabSettings _initialSettings() {
  return LogTabSettings(
    wrapText: false,
    autoScroll: true,
    selectedLogLevel: 'V',
    logLinesLimit: 50000,
    hiddenColumns: const {},
    columnWidths: {
      for (final column in LogColumn.values) column.name: column.defaultWidth,
    },
  );
}

class _FakeControllerSessionService extends DeviceSessionService {
  _FakeControllerSessionService()
    : super(adbPath: '/usr/bin/true', ideviceSyslogPath: '/usr/bin/true');

  List<String> startedLogStreamDeviceIds = [];

  @override
  Stream<LogEntry> startLogStream(Device device) {
    startedLogStreamDeviceIds = [...startedLogStreamDeviceIds, device.id];
    return const Stream<LogEntry>.empty();
  }

  @override
  Future<void> stopActiveLogStream() async {}
}

class _FakeControllerAdbTool extends AdbTool {
  _FakeControllerAdbTool() : super(executablePath: '/usr/bin/true');

  List<Device> androidDevices = const [];
  final StreamController<List<Device>> _watchController =
      StreamController<List<Device>>.broadcast();

  @override
  Future<List<Device>> getDevices() async => List.of(androidDevices);

  @override
  Stream<List<Device>> watchDeviceChanges() => _watchController.stream;

  Future<void> dispose() async {
    await _watchController.close();
  }
}

class _FakeControllerIdeviceIdTool extends IdeviceIdTool {
  _FakeControllerIdeviceIdTool() : super(executablePath: '/usr/bin/true');

  @override
  Future<List<String>> getDeviceIds() async => const [];
}

class _FakeControllerIdeviceInfoTool extends IdeviceInfoTool {
  _FakeControllerIdeviceInfoTool() : super(executablePath: '/usr/bin/true');
}
