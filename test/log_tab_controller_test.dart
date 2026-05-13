import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logview/data/device.dart';
import 'package:logview/data/log_column.dart';
import 'package:logview/data/log_entry.dart';
import 'package:logview/data/log_level.dart';
import 'package:logview/data/log_tab_settings.dart';
import 'package:logview/services/device_repository.dart';
import 'package:logview/services/device_session_service.dart';
import 'package:logview/services/tools/adb_tool.dart';
import 'package:logview/services/tools/idevice_id_tool.dart';
import 'package:logview/services/tools/idevice_info_tool.dart';
import 'package:logview/ui/log_tab_view/log_tab_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeControllerSessionService sessionService;
  late _FakeControllerAdbTool adbTool;
  late _FakeControllerIdeviceIdTool ideviceIdTool;
  late _FakeControllerIdeviceInfoTool ideviceInfoTool;
  late DeviceRepository repository;
  LogTabController? controller;
  String? clipboardText;

  LogTabController createController({LogTabSettings? settings}) {
    return LogTabController(
      id: 'tab-1',
      initialTitle: 'Tab 1',
      initialSettings: settings ?? _initialSettings(),
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

    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
          switch (methodCall.method) {
            case 'Clipboard.setData':
              final arguments = Map<String, dynamic>.from(
                methodCall.arguments as Map<dynamic, dynamic>,
              );
              clipboardText = arguments['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': clipboardText};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
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

  test('start pause resume and stop append special session entries', () async {
    adbTool.androidDevices = [
      Device('emulator-5554', 'device', platform: DevicePlatform.android),
    ];
    controller = createController();

    await controller!.bootstrapInitialLoad();

    expect(controller!.logs.map((log) => log.type), [LogEntryType.started]);

    controller!.togglePauseResume();
    expect(controller!.logs.last.type, LogEntryType.paused);
    expect(controller!.isPaused, isTrue);

    controller!.togglePauseResume();
    expect(controller!.logs.last.type, LogEntryType.resumed);
    expect(controller!.isPaused, isFalse);

    await controller!.stopLogcat();
    expect(controller!.logs.last.type, LogEntryType.stopped);
    expect(controller!.logcatState, LogcatState.stopped);
  });

  test('selected device disconnect appends a stopped session entry', () async {
    adbTool.androidDevices = [
      Device(
        'emulator-5554',
        'device',
        platform: DevicePlatform.android,
        brand: 'Google',
        model: 'Pixel 8',
      ),
    ];
    controller = createController();

    await controller!.bootstrapInitialLoad();
    expect(controller!.isRunning, isTrue);

    adbTool.androidDevices = const [];
    await repository.refreshDevices(force: true);
    await Future<void>.delayed(Duration.zero);

    expect(controller!.logcatState, LogcatState.stopped);
    expect(controller!.selectedDevice?.isDisconnected, isTrue);
    expect(controller!.logs.last.type, LogEntryType.stopped);
    expect(
      controller!.logs.last.message,
      contains('Device disconnected; stopped capturing logs for'),
    );
  });

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

  test(
    'filteredLogs apply message, package, PID/TID, tag, and level filters',
    () {
      controller = createController();

      controller!.logs = [
        LogEntry(
          timestamp: '2026-04-26 10:00:00.000',
          pid: '101',
          tid: '202',
          level: 'I',
          tag: 'AuthService',
          message: 'User signed in successfully',
          packageName: 'com.example.auth',
        ),
        LogEntry(
          timestamp: '2026-04-26 10:00:01.000',
          pid: '303',
          tid: '404',
          level: 'D',
          tag: 'Network',
          message: 'User signed in successfully',
          packageName: 'com.example.network',
        ),
        LogEntry(
          timestamp: '2026-04-26 10:00:02.000',
          pid: '505',
          tid: '606',
          level: 'W',
          tag: 'AuthService',
          message: 'Background sync retry scheduled',
          packageName: 'com.example.auth',
        ),
      ];

      controller!.onSearchChanged('signed in');
      controller!.onPackageFilterChanged('example.auth');
      controller!.onPidTidFilterChanged('101/202');
      controller!.onTagFilterChanged('auth');
      controller!.applyFiltersNow();

      expect(controller!.filteredLogs, hasLength(1));
      expect(controller!.filteredLogs.single.pid, '101');

      controller!.setSelectedLogLevel(LogLevel.warning);
      expect(controller!.filteredLogs, isEmpty);
    },
  );

  test(
    'message filter only matches the log message while tag filter is separate',
    () {
      controller = createController();

      controller!.logs = [
        LogEntry(
          timestamp: '2026-04-26 10:00:00.000',
          pid: '123',
          tid: '456',
          level: 'I',
          tag: 'NeedleTag',
          message: 'Different message',
        ),
      ];

      controller!.onSearchChanged('needle');
      controller!.applyFiltersNow();
      expect(controller!.filteredLogs, isEmpty);

      controller!.clearFilter();
      controller!.onTagFilterChanged('needle');
      controller!.applyFiltersNow();
      expect(controller!.filteredLogs, hasLength(1));
    },
  );

  test(
    'applying filters stores recent values per field without duplicates',
    () async {
      controller = createController();

      controller!.onSearchChanged('First message');
      controller!.onPackageFilterChanged('com.example.app');
      controller!.onPidTidFilterChanged('123:456');
      controller!.onTagFilterChanged('Auth');
      controller!.applyFiltersNow();

      controller!.onSearchChanged('second message');
      controller!.onPackageFilterChanged('com.example.app');
      controller!.onPidTidFilterChanged('123:456');
      controller!.onTagFilterChanged('auth');
      controller!.applyFiltersNow();

      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(controller!.recentMessageFilters, ['second message']);
      expect(controller!.recentPackageFilters, ['com.example.app']);
      expect(controller!.recentPidTidFilters, ['123:456']);
      expect(controller!.recentTagFilters, ['auth']);
    },
  );

  test(
    'streamed logs retain filtered matches longer while a filter is active',
    () async {
      adbTool.androidDevices = [
        Device('emulator-5554', 'device', platform: DevicePlatform.android),
      ];
      controller = createController(
        settings: _initialSettings(logLinesLimit: 3),
      );

      controller!.onSearchChanged('keep');
      controller!.applyFiltersNow();
      await controller!.bootstrapInitialLoad();

      for (final (index, message) in [
        'keep 1',
        'drop 1',
        'drop 2',
        'keep 2',
        'drop 3',
        'drop 4',
        'drop 5',
        'drop 6',
      ].indexed) {
        sessionService.emit(
          _testLogEntry(
            message: message,
            pid: '${index + 100}',
            tid: '${index + 200}',
            tag: 'Tag${index + 1}',
          ),
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));

      final storedMessages = controller!.logs
          .map((log) => log.message)
          .toList();
      expect(storedMessages, containsAll(['keep 1', 'keep 2']));
      expect(storedMessages, isNot(contains('drop 1')));
      expect(controller!.filteredLogs.map((log) => log.message), [
        'keep 1',
        'keep 2',
      ]);
    },
  );

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

  test('searchMatchIndices support whole-word and regex options', () {
    controller = createController();

    controller!.logs = [
      LogEntry(
        timestamp: '2026-04-26 10:00:00.000',
        pid: '123',
        tid: '456',
        level: 'I',
        tag: 'Auth',
        message: 'error error42 ERROR',
      ),
      LogEntry(
        timestamp: '2026-04-26 10:00:01.000',
        pid: '124',
        tid: '457',
        level: 'I',
        tag: 'Auth',
        message: 'only error42 here',
      ),
    ];

    controller!.openSearchBar(query: 'error');
    expect(controller!.searchMatchIndices, [0, 1]);

    controller!.setSearchWholeWord(true);
    expect(controller!.searchMatchIndices, [0]);

    controller!.setSearchWholeWord(false);
    controller!.setSearchRegex(true);
    controller!.openSearchBar(query: r'error\d+');
    expect(controller!.searchMatchIndices, [0, 1]);

    controller!.setSearchCaseSensitive(true);
    controller!.openSearchBar(query: r'ERROR');
    expect(controller!.searchMatchIndices, [0]);
  });

  test('invalid regex search is surfaced without producing matches', () {
    controller = createController();

    controller!.logs = [
      LogEntry(
        timestamp: '2026-04-26 10:00:00.000',
        pid: '123',
        tid: '456',
        level: 'I',
        tag: 'Auth',
        message: 'error 42',
      ),
    ];

    controller!.setSearchRegex(true);
    controller!.openSearchBar(query: r'(');

    expect(controller!.inlineSearchHasError, isTrue);
    expect(controller!.searchMatchIndices, isEmpty);
  });

  test('activating search from selected text copies and prefills it', () async {
    controller = createController();

    controller!.setSelectedSearchText('Selected needle');
    controller!.activateSearchFromSelection();
    await Future<void>.delayed(Duration.zero);

    final clipboard = await Clipboard.getData('text/plain');
    expect(controller!.searchBarVisible, isTrue);
    expect(controller!.inlineSearchQuery, 'Selected needle');
    expect(controller!.appliedInlineSearchQuery, 'Selected needle');
    expect(controller!.autoScroll, isFalse);
    expect(clipboard?.text, 'Selected needle');
  });

  test('search navigation disables auto-scroll when moving between matches', () {
    controller = createController();

    controller!.logs = [
      _testLogEntry(message: 'needle one'),
      _testLogEntry(message: 'needle two'),
    ];

    controller!.openSearchBar(query: 'needle');
    expect(controller!.autoScroll, isFalse);

    controller!.toggleAutoScroll();
    expect(controller!.autoScroll, isTrue);

    controller!.onSearchNext();
    expect(controller!.searchCurrentMatch, 1);
    expect(controller!.autoScroll, isFalse);
  });

  test('filteredLogs keeps entries with unknown log levels', () {
    controller = createController();
    controller!.setSelectedLogLevel(LogLevel.info);

    controller!.logs = [
      LogEntry(
        timestamp: '2026-04-26 10:00:00.000',
        pid: '123',
        tid: '456',
        level: 'panic',
        tag: 'VisibleTag',
        message: 'Unexpected log level should still be visible',
      ),
    ];

    expect(controller!.filteredLogs, hasLength(1));
  });

  test(
    'copyAllLogs copies formatted full log lines from cached logs',
    () async {
      controller = createController();
      controller!.logs = [
        LogEntry(
          timestamp: '2026-04-26 10:00:00.000',
          pid: '123',
          tid: '456',
          level: 'I',
          tag: 'Auth',
          message: 'Signed in',
          packageName: 'com.example.auth',
        ),
        LogEntry(
          timestamp: '2026-04-26 10:00:01.000',
          pid: '789',
          tid: '987',
          level: 'W',
          tag: 'Sync',
          message: 'Retry scheduled',
        ),
      ];

      final copiedCount = await controller!.copyAllLogs();
      final clipboard = await Clipboard.getData('text/plain');

      expect(copiedCount, 2);
      expect(
        clipboard?.text,
        '2026-04-26 10:00:00.000 com.example.auth 456 I Auth: Signed in\n'
        '2026-04-26 10:00:01.000 789 987 W Sync: Retry scheduled',
      );
    },
  );

  test('special entries are skipped by selection and copy operations', () async {
    controller = createController();
    controller!.logs = [
      _testLogEntry(message: 'First message'),
      LogEntry.loggingState(
        type: LogEntryType.paused,
        message: 'Paused live logging for emulator-5554.',
        processName: 'emulator-5554',
      ),
      _testLogEntry(message: 'Second message'),
    ];

    controller!.setRowSelectionMode(true);

    expect(controller!.beginRowSelectionGesture(1), isNull);
    expect(controller!.selectedRowIndices, isEmpty);

    expect(controller!.beginRowSelectionGesture(0), isTrue);
    controller!.selectRowRangeTo(2);
    expect(controller!.selectedRowIndices, {0, 2});

    controller!.setSelectedRows({0, 1, 2});
    expect(controller!.selectedRowIndices, {0, 2});

    final copiedCount = await controller!.copyFilteredRows(
      [0, 1, 2],
      format: LogCopyFormat.messageOnly,
    );
    final clipboard = await Clipboard.getData('text/plain');

    expect(copiedCount, 2);
    expect(clipboard?.text, 'First message\nSecond message');
  });

  test('beginRowSelectionGesture auto-enables row selection mode', () {
    controller = createController();
    controller!.logs = List.generate(
      3,
      (index) => _testLogEntry(message: 'Message $index'),
    );

    expect(controller!.rowSelectionMode, isFalse);

    final shouldSelect = controller!.beginRowSelectionGesture(1);

    expect(shouldSelect, isTrue);
    expect(controller!.rowSelectionMode, isTrue);
    expect(controller!.selectedRowIndices, {1});

    final shouldDeselect = controller!.beginRowSelectionGesture(1);

    expect(shouldDeselect, isFalse);
    expect(controller!.selectedRowIndices, isEmpty);
    expect(controller!.rowSelectionMode, isFalse);
  });

  test(
    'copyRowsForContextMenu copies selected rows when clicked row is selected',
    () async {
      controller = createController();
      controller!.logs = [
        LogEntry(
          timestamp: '2026-04-26 10:00:00.000',
          pid: '101',
          tid: '201',
          level: 'I',
          tag: 'Auth',
          message: 'First message',
        ),
        LogEntry(
          timestamp: '2026-04-26 10:00:01.000',
          pid: '102',
          tid: '202',
          level: 'I',
          tag: 'Auth',
          message: 'Second message',
        ),
        LogEntry(
          timestamp: '2026-04-26 10:00:02.000',
          pid: '103',
          tid: '203',
          level: 'I',
          tag: 'Auth',
          message: 'Third message',
        ),
      ];

      controller!.setRowSelectionMode(true);
      controller!.setRowSelected(0, true);
      controller!.setRowSelected(2, true);

      final copiedCount = await controller!.copyRowsForContextMenu(
        clickedFilteredIndex: 2,
        format: LogCopyFormat.timestampAndMessage,
      );
      final clipboard = await Clipboard.getData('text/plain');

      expect(copiedCount, 2);
      expect(
        clipboard?.text,
        '2026-04-26 10:00:00.000 First message\n'
        '2026-04-26 10:00:02.000 Third message',
      );
    },
  );

  test('disabling row selection mode clears selected rows', () {
    controller = createController();
    controller!.logs = List.generate(
      3,
      (index) => _testLogEntry(message: 'Message $index'),
    );
    controller!.setRowSelectionMode(true);
    controller!.setRowSelected(1, true);
    controller!.setRowSelected(2, true);

    controller!.setRowSelectionMode(false);

    expect(controller!.rowSelectionMode, isFalse);
    expect(controller!.selectedRowIndices, isEmpty);
  });

  test('shift selection selects an inclusive range from the anchor row', () {
    controller = createController();
    controller!.logs = List.generate(
      5,
      (index) => _testLogEntry(message: 'Message $index'),
    );
    controller!.setRowSelectionMode(true);

    final dragValue = controller!.beginRowSelectionGesture(1);
    controller!.beginRowSelectionGesture(4, shiftPressed: true);

    expect(dragValue, isTrue);
    expect(controller!.rowSelectionAnchorIndex, 1);
    expect(controller!.selectedRowIndices, {1, 2, 3, 4});
  });

  test('shift selection without an anchor selects only the clicked row', () {
    controller = createController();
    controller!.logs = List.generate(
      5,
      (index) => _testLogEntry(message: 'Message $index'),
    );
    controller!.setRowSelectionMode(true);

    controller!.beginRowSelectionGesture(3, shiftPressed: true);

    expect(controller!.rowSelectionAnchorIndex, 3);
    expect(controller!.selectedRowIndices, {3});
  });

  test('setSelectedRows replaces the current row selection in one update', () {
    controller = createController();
    controller!.logs = List.generate(
      5,
      (index) => _testLogEntry(message: 'Message $index'),
    );
    controller!.setRowSelectionMode(true);
    controller!.setRowSelected(0, true);
    controller!.setRowSelected(4, true);

    controller!.setSelectedRows({1, 2, 3});

    expect(controller!.selectedRowIndices, {1, 2, 3});
  });
}

LogTabSettings _initialSettings({int logLinesLimit = 50000}) {
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

class _FakeControllerSessionService extends DeviceSessionService {
  _FakeControllerSessionService()
    : super(adbPath: '/usr/bin/true', ideviceSyslogPath: '/usr/bin/true');

  List<String> startedLogStreamDeviceIds = [];
  final StreamController<LogEntry> _logController =
      StreamController<LogEntry>.broadcast();

  @override
  Stream<LogEntry> startLogStream(Device device) {
    startedLogStreamDeviceIds = [...startedLogStreamDeviceIds, device.id];
    return _logController.stream;
  }

  void emit(LogEntry entry) {
    _logController.add(entry);
  }

  @override
  Future<void> stopActiveLogStream() async {}

  @override
  Future<void> dispose() async {
    await _logController.close();
    await super.dispose();
  }
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

LogEntry _testLogEntry({
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
