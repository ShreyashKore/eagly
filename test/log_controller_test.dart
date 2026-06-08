import 'package:eagly/data/device.dart';
import 'package:eagly/data/log_column.dart';
import 'package:eagly/data/log_entry.dart';
import 'package:eagly/data/log_level.dart';
import 'package:eagly/data/log_tab_settings.dart';
import 'package:eagly/data/log_view_mode.dart';
import 'package:eagly/features/logs/log_controller.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:eagly/utils/log_entry_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSessionService service;
  late Device device;
  DeviceSessionController? session;
  String? clipboardText;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  LogController createLog({LogTabSettings? settings, Device? withDevice}) {
    device =
        withDevice ??
        Device('emulator-5554', 'device', platform: DevicePlatform.android);
    service = FakeSessionService(device);
    session = DeviceSessionController(
      device: device,
      service: service,
      initialLogSettings: settings ?? testSettings(),
    );
    return session!.logController;
  }

  void disconnect() {
    session!.updateDevice(
      device.copyWith(connectionState: DeviceConnectionState.disconnected),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
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
    session?.dispose();
    session = null;
  });

  test('activate starts log capture once for a connected device', () async {
    final log = createLog();

    session!.activate();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(log.isRunning, isTrue);
    expect(service.startLogStreamCount, 1);
    expect(log.logs.map((entry) => entry.type), [LogEntryType.started]);

    session!.activate(); // idempotent
    expect(service.startLogStreamCount, 1);
  });

  test('start pause resume and stop append special session entries', () async {
    final log = createLog();

    await log.startLogcat();
    expect(log.logs.map((entry) => entry.type), [LogEntryType.started]);

    log.togglePauseResume();
    expect(log.logs.last.type, LogEntryType.paused);
    expect(log.isPaused, isTrue);

    log.togglePauseResume();
    expect(log.logs.last.type, LogEntryType.resumed);
    expect(log.isPaused, isFalse);

    await log.stopLogcat();
    expect(log.logs.last.type, LogEntryType.stopped);
    expect(log.logcatState, LogcatState.stopped);
  });

  test('device disconnect stops capture and appends a stopped entry', () async {
    final log = createLog(
      withDevice: Device(
        'emulator-5554',
        'device',
        platform: DevicePlatform.android,
        brand: 'Google',
        model: 'Pixel 8',
      ),
    );

    await log.startLogcat();
    expect(log.isRunning, isTrue);

    disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(log.logcatState, LogcatState.stopped);
    expect(log.logs.last.type, LogEntryType.stopped);
    expect(
      log.logs.last.message,
      contains('Device disconnected; stopped capturing logs for'),
    );
  });

  test('submitLogLinesLimit rejects values below minimum threshold', () {
    final log = createLog();

    final submitted = log.submitLogLinesLimit('999');

    expect(submitted, isFalse);
    expect(log.logLinesLimit, 50000);
    expect(log.editingLogLinesLimit, isFalse);
  });

  test('submitLogLinesLimit trims existing logs to the new limit', () {
    final log = createLog();

    log.logs = List.generate(
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

    final submitted = log.submitLogLinesLimit('1000');

    expect(submitted, isTrue);
    expect(log.logLinesLimit, 1000);
    expect(log.logs, hasLength(1000));
    expect(log.logs.first.message, 'Message 5');
    expect(log.logLinesController.text, '1000');
  });

  test(
    'filteredLogs apply message, package, PID/TID, tag, and level filters',
    () {
      final log = createLog();

      log.logs = [
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

      log.onSearchChanged('signed in');
      log.onPackageFilterChanged('example.auth');
      log.onPidTidFilterChanged('101/202');
      log.onTagFilterChanged('auth');
      log.applyFiltersNow();

      expect(log.filteredLogs, hasLength(1));
      expect(log.filteredLogs.single.pid, '101');

      log.setSelectedLogLevel(LogLevel.warning);
      expect(log.filteredLogs, isEmpty);
    },
  );

  test(
    'message filter only matches the log message while tag filter is separate',
    () {
      final log = createLog();

      log.logs = [
        LogEntry(
          timestamp: '2026-04-26 10:00:00.000',
          pid: '123',
          tid: '456',
          level: 'I',
          tag: 'NeedleTag',
          message: 'Different message',
        ),
      ];

      log.onSearchChanged('needle');
      log.applyFiltersNow();
      expect(log.filteredLogs, isEmpty);

      log.clearFilter();
      log.onTagFilterChanged('needle');
      log.applyFiltersNow();
      expect(log.filteredLogs, hasLength(1));
    },
  );

  test(
    'applying filters stores recent values per field without duplicates',
    () async {
      final log = createLog();

      log.onSearchChanged('First message');
      log.onPackageFilterChanged('com.example.app');
      log.onPidTidFilterChanged('123:456');
      log.onTagFilterChanged('Auth');
      log.applyFiltersNow();

      log.onSearchChanged('second message');
      log.onPackageFilterChanged('com.example.app');
      log.onPidTidFilterChanged('123:456');
      log.onTagFilterChanged('auth');
      log.applyFiltersNow();

      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(log.recentMessageFilters, ['second message']);
      expect(log.recentPackageFilters, ['com.example.app']);
      expect(log.recentPidTidFilters, ['123:456']);
      expect(log.recentTagFilters, ['auth']);
    },
  );

  test(
    'inline filter syntax applies package, tag, message, pid, and level filters',
    () {
      final log = createLog(
        settings: testSettings(filterViewMode: LogFilterViewMode.inline),
      );

      log.logs = [
        LogEntry(
          timestamp: '2026-04-26 10:00:00.000',
          pid: '101',
          tid: '202',
          level: 'E',
          tag: 'AuthService',
          message: 'User signed in successfully',
          packageName: 'com.example.auth',
        ),
        LogEntry(
          timestamp: '2026-04-26 10:00:01.000',
          pid: '101',
          tid: '202',
          level: 'I',
          tag: 'AuthService',
          message: 'User signed in successfully',
          packageName: 'com.example.auth',
        ),
      ];

      log.onInlineFilterChanged(
        'package:com.example.auth tag:Auth pid:101/202 level:error "signed in"',
      );
      log.applyFiltersNow();

      expect(log.selectedLogLevel, LogLevel.error);
      expect(log.filteredLogs, hasLength(1));
      expect(log.filteredLogs.single.level, 'E');
      expect(log.filterController.text, 'signed in');
      expect(log.packageFilterController.text, 'com.example.auth');
      expect(log.tagFilterController.text, 'Auth');
      expect(log.pidTidFilterController.text, '101/202');
    },
  );

  test('inline filter syntax supports quoted values and repeated keys', () {
    final log = createLog(
      settings: testSettings(filterViewMode: LogFilterViewMode.inline),
    );

    log.logs = [
      LogEntry(
        timestamp: '2026-04-26 10:00:00.000',
        pid: '500',
        tid: '600',
        level: 'I',
        tag: 'SyncWorker',
        message: 'Background sync retry scheduled by worker',
        packageName: 'com.example.sync',
      ),
      LogEntry(
        timestamp: '2026-04-26 10:00:01.000',
        pid: '500',
        tid: '601',
        level: 'I',
        tag: 'SyncWorker',
        message: 'Background upload scheduled',
        packageName: 'com.example.sync',
      ),
    ];

    log.onInlineFilterChanged(
      'message:"background sync" message:worker tag:SyncWorker',
    );
    log.applyFiltersNow();

    expect(log.filteredLogs, hasLength(1));
    expect(log.filteredLogs.single.message, contains('worker'));
    expect(log.recentMessageFilters, isEmpty);
  });

  test('inline bare text matches the whole log entry, not only the message', () {
    final log = createLog(
      settings: testSettings(filterViewMode: LogFilterViewMode.inline),
    );

    log.logs = [
      LogEntry(
        timestamp: '2026-04-26 10:00:00.000',
        pid: '900',
        tid: '901',
        level: 'I',
        tag: 'AuthService',
        message: 'No matching message text here',
        packageName: 'com.example.auth',
      ),
      LogEntry(
        timestamp: '2026-04-26 10:00:01.000',
        pid: '902',
        tid: '903',
        level: 'I',
        tag: 'SyncService',
        message: 'No matching message text here either',
        packageName: 'com.example.sync',
      ),
    ];

    log.onInlineFilterChanged('AuthService');
    log.applyFiltersNow();

    expect(log.filteredLogs, hasLength(1));
    expect(log.filteredLogs.single.tag, 'AuthService');

    log.onInlineFilterChanged('com.example.sync');
    log.applyFiltersNow();

    expect(log.filteredLogs, hasLength(1));
    expect(log.filteredLogs.single.packageName, 'com.example.sync');
  });

  test('changing filter mode updates the active per-device setting', () {
    final log = createLog();

    log.setFilterViewMode(LogFilterViewMode.inline);
    expect(log.filterViewMode, LogFilterViewMode.inline);

    log.setFilterViewMode(LogFilterViewMode.classic);
    expect(log.filterViewMode, LogFilterViewMode.classic);
  });

  test(
    'streamed logs retain filtered matches longer while a filter is active',
    () async {
      final log = createLog(settings: testSettings(logLinesLimit: 3));

      log.onSearchChanged('keep');
      log.applyFiltersNow();
      await log.startLogcat();

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
        service.emit(
          testLogEntry(
            message: message,
            pid: '${index + 100}',
            tid: '${index + 200}',
            tag: 'Tag${index + 1}',
          ),
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));

      final storedMessages = log.logs.map((entry) => entry.message).toList();
      expect(storedMessages, containsAll(['keep 1', 'keep 2']));
      expect(storedMessages, isNot(contains('drop 1')));
      expect(log.filteredLogs.map((entry) => entry.message), [
        'keep 1',
        'keep 2',
      ]);
    },
  );

  test('searchMatchIndices ignore hidden columns when computing matches', () {
    final log = createLog();

    log.logs = [
      LogEntry(
        timestamp: '2026-04-26 10:00:00.000',
        pid: '123',
        tid: '456',
        level: 'I',
        tag: 'VisibleTag',
        message: 'HiddenNeedle',
      ),
    ];

    log.onInlineSearchChanged('HiddenNeedle');
    log.setHiddenColumns({LogColumn.message.name});
    log.setSearchCaseSensitive(true);

    expect(log.searchMatchIndices, isEmpty);
  });

  test('searchMatchIndices support whole-word and regex options', () {
    final log = createLog();

    log.logs = [
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

    log.openSearchBar(query: 'error');
    expect(log.searchMatchIndices, [0, 1]);

    log.setSearchWholeWord(true);
    expect(log.searchMatchIndices, [0]);

    log.setSearchWholeWord(false);
    log.setSearchRegex(true);
    log.openSearchBar(query: r'error\d+');
    expect(log.searchMatchIndices, [0, 1]);

    log.setSearchCaseSensitive(true);
    log.openSearchBar(query: r'ERROR');
    expect(log.searchMatchIndices, [0]);
  });

  test('invalid regex search is surfaced without producing matches', () {
    final log = createLog();

    log.logs = [
      LogEntry(
        timestamp: '2026-04-26 10:00:00.000',
        pid: '123',
        tid: '456',
        level: 'I',
        tag: 'Auth',
        message: 'error 42',
      ),
    ];

    log.setSearchRegex(true);
    log.openSearchBar(query: r'(');

    expect(log.inlineSearchHasError, isTrue);
    expect(log.searchMatchIndices, isEmpty);
  });

  test('activating search from selected text copies and prefills it', () async {
    final log = createLog();

    log.setSelectedSearchText('Selected needle');
    log.activateSearchFromSelection();
    await Future<void>.delayed(Duration.zero);

    final clipboard = await Clipboard.getData('text/plain');
    expect(log.searchBarVisible, isTrue);
    expect(log.inlineSearchQuery, 'Selected needle');
    expect(log.appliedInlineSearchQuery, 'Selected needle');
    expect(log.autoScroll, isFalse);
    expect(clipboard?.text, 'Selected needle');
  });

  test('search navigation disables auto-scroll when moving between matches', () {
    final log = createLog();

    log.logs = [
      testLogEntry(message: 'needle one'),
      testLogEntry(message: 'needle two'),
    ];

    log.openSearchBar(query: 'needle');
    expect(log.autoScroll, isFalse);

    log.toggleAutoScroll();
    expect(log.autoScroll, isTrue);

    log.onSearchNext();
    expect(log.searchCurrentMatch, 1);
    expect(log.autoScroll, isFalse);
  });

  test('filteredLogs keeps entries with unknown log levels', () {
    final log = createLog();
    log.setSelectedLogLevel(LogLevel.info);

    log.logs = [
      LogEntry(
        timestamp: '2026-04-26 10:00:00.000',
        pid: '123',
        tid: '456',
        level: 'panic',
        tag: 'VisibleTag',
        message: 'Unexpected log level should still be visible',
      ),
    ];

    expect(log.filteredLogs, hasLength(1));
  });

  test('copyAllLogs copies formatted full log lines from cached logs', () async {
    final log = createLog();
    log.logs = [
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

    final copiedCount = await log.copyAllLogs();
    final clipboard = await Clipboard.getData('text/plain');

    expect(copiedCount, 2);
    expect(
      clipboard?.text,
      '2026-04-26 10:00:00.000 com.example.auth 456 I Auth: Signed in\n'
      '2026-04-26 10:00:01.000 789 987 W Sync: Retry scheduled',
    );
  });

  test('special entries are skipped by selection and copy operations', () async {
    final log = createLog();
    log.logs = [
      testLogEntry(message: 'First message'),
      LogEntryUtils.buildLoggingState(
        type: LogEntryType.paused,
        message: 'Paused live logging for emulator-5554.',
        processName: 'emulator-5554',
      ),
      testLogEntry(message: 'Second message'),
    ];

    log.setRowSelectionMode(true);

    expect(log.beginRowSelectionGesture(1), isNull);
    expect(log.selectedRowIndices, isEmpty);

    expect(log.beginRowSelectionGesture(0), isTrue);
    log.selectRowRangeTo(2);
    expect(log.selectedRowIndices, {0, 2});

    log.setSelectedRows({0, 1, 2});
    expect(log.selectedRowIndices, {0, 2});

    final copiedCount = await log.copyFilteredRows([
      0,
      1,
      2,
    ], format: LogCopyFormat.messageOnly);
    final clipboard = await Clipboard.getData('text/plain');

    expect(copiedCount, 2);
    expect(clipboard?.text, 'First message\nSecond message');
  });

  test(
    'copyRowsForContextMenu copies selected rows when clicked row is selected',
    () async {
      final log = createLog();
      log.logs = [
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

      log.setRowSelectionMode(true);
      log.setRowSelected(0, true);
      log.setRowSelected(2, true);

      final copiedCount = await log.copyRowsForContextMenu(
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
    final log = createLog();
    log.logs = List.generate(
      3,
      (index) => testLogEntry(message: 'Message $index'),
    );
    log.setRowSelectionMode(true);
    log.setRowSelected(1, true);
    log.setRowSelected(2, true);

    log.setRowSelectionMode(false);

    expect(log.rowSelectionMode, isFalse);
    expect(log.selectedRowIndices, isEmpty);
  });

  test('shift selection selects an inclusive range from the anchor row', () {
    final log = createLog();
    log.logs = List.generate(
      5,
      (index) => testLogEntry(message: 'Message $index'),
    );
    log.setRowSelectionMode(true);

    final dragValue = log.beginRowSelectionGesture(1);
    log.beginRowSelectionGesture(4, shiftPressed: true);

    expect(dragValue, isTrue);
    expect(log.rowSelectionAnchorIndex, 1);
    expect(log.selectedRowIndices, {1, 2, 3, 4});
  });

  test('setSelectedRows replaces the current row selection in one update', () {
    final log = createLog();
    log.logs = List.generate(
      5,
      (index) => testLogEntry(message: 'Message $index'),
    );
    log.setRowSelectionMode(true);
    log.setRowSelected(0, true);
    log.setRowSelected(4, true);

    log.setSelectedRows({1, 2, 3});

    expect(log.selectedRowIndices, {1, 2, 3});
  });
}
