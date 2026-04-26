import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logview/controllers/log_tab_controller.dart';
import 'package:logview/data/device.dart';
import 'package:logview/data/log_column.dart';
import 'package:logview/data/log_entry.dart';
import 'package:logview/data/log_tab_settings.dart';
import 'package:logview/services/device_bridge_service.dart';
import 'package:logview/services/device_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeControllerBridgeService bridgeService;
  late DeviceRepository repository;
  LogTabController? controller;

  LogTabController createController() {
    return LogTabController(
      id: 'tab-1',
      initialTitle: 'Tab 1',
      initialSettings: _initialSettings(),
      deviceRepository: repository,
      deviceBridgeService: bridgeService,
    );
  }

  setUp(() {
    bridgeService = _FakeControllerBridgeService();
    repository = DeviceRepository.forTesting(
      deviceBridgeService: bridgeService,
    );
  });

  tearDown(() {
    controller?.dispose();
    repository.dispose();
    bridgeService.dispose();
  });

  test(
    'bootstrapInitialLoad auto-selects a single connected device and starts logs',
    () async {
      bridgeService.androidDevices = [
        Device('emulator-5554', 'device', platform: DevicePlatform.android),
      ];
      controller = createController();

      await controller!.bootstrapInitialLoad();

      expect(controller!.selectedDevice?.id, 'emulator-5554');
      expect(controller!.showGetStarted, isFalse);
      expect(controller!.isRunning, isTrue);
      expect(bridgeService.startedLogStreamDeviceIds, ['emulator-5554']);
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

class _FakeControllerBridgeService extends DeviceBridgeService {
  _FakeControllerBridgeService()
    : super(
        adbPath: '/usr/bin/true',
        ideviceIdPath: '/usr/bin/true',
        ideviceInfoPath: '/usr/bin/true',
        ideviceSyslogPath: '/usr/bin/true',
      );

  List<Device> androidDevices = const [];
  List<String> startedLogStreamDeviceIds = [];
  final StreamController<String> _watchController =
      StreamController<String>.broadcast();

  @override
  Future<List<Device>> getAndroidDevices() async => List.of(androidDevices);

  @override
  Future<List<String>> getIosDeviceIds() async => const [];

  @override
  Stream<String> watchAndroidDeviceChanges() => _watchController.stream;

  @override
  Stream<LogEntry> startLogStream(Device device) {
    startedLogStreamDeviceIds = [...startedLogStreamDeviceIds, device.id];
    return const Stream<LogEntry>.empty();
  }

  @override
  Future<void> stopActiveLogStream() async {}

  @override
  Future<void> dispose() async {
    await _watchController.close();
  }
}
