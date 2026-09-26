import 'package:eagly/data/device.dart';
import 'package:eagly/features/logs/data/models/log_column.dart';
import 'package:eagly/features/logs/data/models/filter_condition.dart';
import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/data/models/log_filters.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/features/logs/data/models/log_tab_settings.dart';
import 'package:eagly/features/logs/log_controller.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:eagly/utils/log_entry_utils.dart';
import 'package:eagly/utils/text_search_pattern.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

/// Applies typed filter syntax: parse the text into a [LogFilters]
/// configuration, then apply it.
void applyTypedFilter(LogController log, String text) {
  log.applyFilters(
    LogFilters.parse(
      text,
      fallbackLevel: log.selectedLogLevel,
      isIosLogContext: log.isIosLogContext,
    ),
  );
}

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
    if (settings != null) {
      PreferencesService.logLinesLimit = settings.logLinesLimit;
    }
    device =
        withDevice ??
        Device('emulator-5554', 'device', platform: DevicePlatform.android);
    service = FakeSessionService(device);
    session = DeviceSessionController(device: device, service: service);
    return session!.logSessionManager.selectedTab!;
  }

  void disconnect() {
    session!.updateDevice(
      device.copyWith(connectionState: DeviceConnectionState.disconnected),
    );
  }

  void reconnect() {
    session!.updateDevice(
      device.copyWith(connectionState: DeviceConnectionState.connected),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
    // Keep automatic recovery fast and deterministic in tests.
    LogController.recoveryBackoff = const Duration(milliseconds: 10);
    LogController.maxPendingLogs = 10000;
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
    LogController.recoveryBackoff = const Duration(seconds: 2);
    LogController.watchdogInterval = const Duration(seconds: 10);
    LogController.streamStallThreshold = const Duration(seconds: 30);
    LogController.maxPendingLogs = 10000;
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

  test(
    'device disconnect interrupts live logging and preserves captured logs',
    () async {
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

      service.emit(testLogEntry(message: 'before disconnect'));
      await Future<void>.delayed(const Duration(milliseconds: 400));

      disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(log.liveLoggingInterrupted, isTrue);
      expect(log.logs.last.type, LogEntryType.error);
      expect(log.logs.last.message, contains('disconnected'));
      expect(
        log.logs.any((entry) => entry.message == 'before disconnect'),
        isTrue,
      );
    },
  );

  test(
    'reconnect resumes a running tab without clearing existing logs',
    () async {
      final log = createLog();

      await log.startLogcat();
      service.emit(testLogEntry(message: 'kept across reconnect'));
      await Future<void>.delayed(const Duration(milliseconds: 400));

      disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(log.liveLoggingInterrupted, isTrue);

      reconnect();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(log.liveLoggingInterrupted, isFalse);
      expect(log.isRunning, isTrue);
      expect(
        log.logs.any((entry) => entry.message == 'kept across reconnect'),
        isTrue,
      );
    },
  );

  test(
    'unexpected stream end auto-recovers when the device is responsive',
    () async {
      final log = createLog();

      await log.startLogcat();
      final startsBefore = service.startLogStreamCount;
      service.pingResult = true;

      await service.endStream();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(log.liveLoggingInterrupted, isFalse);
      expect(service.startLogStreamCount, greaterThan(startsBefore));
    },
  );

  test(
    'unexpected stream end shows the banner when the device is unresponsive',
    () async {
      final log = createLog();

      await log.startLogcat();
      service.pingResult = false;

      await service.endStream();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(log.liveLoggingInterrupted, isTrue);
      expect(log.isRecovering, isFalse);
      expect(log.logs.last.type, LogEntryType.error);
      // Tiered recovery escalates to an adb reconnect before giving up.
      expect(service.recoverCount, greaterThanOrEqualTo(1));
    },
  );

  test(
    'resumeLiveLogging restarts a dropped stream and clears the banner',
    () async {
      final log = createLog();

      await log.startLogcat();
      service.pingResult = false;
      await service.endStream();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(log.liveLoggingInterrupted, isTrue);

      service.pingResult = true;
      await log.resumeLiveLogging();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(log.liveLoggingInterrupted, isFalse);
      expect(log.isRunning, isTrue);
      expect(service.recoverCount, greaterThanOrEqualTo(1));
    },
  );

  test('opening a second live tab does not interrupt the first tab', () async {
    createLog();
    final manager = session!.logSessionManager;
    final firstTab = manager.tabs.first;

    await firstTab.startLogcat();
    expect(firstTab.isRunning, isTrue);
    expect(service.startLogStreamCount, 1);

    // A second live tab for the same device must start its own independent
    // stream — not tear down the first tab's stream and send it into the
    // recovery loop (the shared-session reconnect storm).
    manager.addLiveTab();
    final secondTab = manager.tabs.last;
    expect(secondTab, isNot(same(firstTab)));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Exactly one stream per tab; the first tab never re-attached (which a
    // recovery cycle would have caused).
    expect(service.startLogStreamCount, 2);
    expect(service.recoverCount, 0);
    expect(firstTab.isRunning, isTrue);
    expect(firstTab.liveLoggingInterrupted, isFalse);
    expect(firstTab.isRecovering, isFalse);
    expect(secondTab.isRunning, isTrue);
    expect(secondTab.liveLoggingInterrupted, isFalse);
  });

  test('submitLogLinesLimit rejects values below minimum threshold', () {
    final log = createLog();

    final submitted = log.submitLogLinesLimit(999);

    expect(submitted, isFalse);
    expect(log.logLinesLimit, PreferencesService.defaultLogLinesLimit);
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

    final submitted = log.submitLogLinesLimit(1000);

    expect(submitted, isTrue);
    expect(log.logLinesLimit, 1000);
    expect(log.logs, hasLength(1000));
    expect(log.logs.first.message, 'Message 5');
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

      log.applyFilters(
        LogFilters.fromFields(
          level: log.selectedLogLevel,
          message: 'signed in',
          package: 'example.auth',
          pidTid: '101/202',
          tag: 'auth',
        ),
      );

      expect(log.filteredLogs, hasLength(1));
      expect(log.filteredLogs.single.pid, '101');

      log.setSelectedLogLevel(LogLevel.warning);
      expect(log.filteredLogs, isEmpty);
    },
  );

  test('inline age filter keeps only entries within the max age', () {
    final log = createLog();

    String stamp(DateTime time) {
      String two(int v) => v.toString().padLeft(2, '0');
      final year = time.year.toString().padLeft(4, '0');
      final millis = time.millisecond.toString().padLeft(3, '0');
      return '$year-${two(time.month)}-${two(time.day)} '
          '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.$millis';
    }

    final now = DateTime.now();
    log.logs = [
      LogEntry(
        timestamp: stamp(now.subtract(const Duration(hours: 3))),
        pid: '101',
        tid: '202',
        level: 'I',
        tag: 'AuthService',
        message: 'Old entry',
      ),
      LogEntry(
        timestamp: stamp(now.subtract(const Duration(minutes: 5))),
        pid: '303',
        tid: '404',
        level: 'I',
        tag: 'AuthService',
        message: 'Recent entry',
      ),
    ];

    applyTypedFilter(log, 'age:1h');

    expect(log.filteredLogs, hasLength(1));
    expect(log.filteredLogs.single.message, 'Recent entry');
  });

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

      log.applyFilters(
        LogFilters.fromFields(level: log.selectedLogLevel, message: 'needle'),
      );
      expect(log.filteredLogs, isEmpty);

      log.clearFilter();
      log.applyFilters(
        LogFilters.fromFields(level: log.selectedLogLevel, tag: 'needle'),
      );
      expect(log.filteredLogs, hasLength(1));
    },
  );

  test(
    'applying filters stores recent values per field without duplicates',
    () async {
      final log = createLog();

      log.applyFilters(
        LogFilters.fromFields(
          level: log.selectedLogLevel,
          message: 'First message',
          package: 'com.example.app',
          pidTid: '123:456',
          tag: 'Auth',
        ),
      );

      log.applyFilters(
        LogFilters.fromFields(
          level: log.selectedLogLevel,
          message: 'second message',
          package: 'com.example.app',
          pidTid: '123:456',
          tag: 'auth',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(log.recentFilters.message, ['second message']);
      expect(log.recentFilters.package, ['com.example.app']);
      expect(log.recentFilters.pidTid, ['123:456']);
      expect(log.recentFilters.tag, ['auth']);
    },
  );

  test(
    'typed filter syntax applies package, tag, message, pid, and level filters',
    () {
      final log = createLog();

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

      applyTypedFilter(
        log,
        'package:com.example.auth tag:Auth pid:101/202 level:error "signed in"',
      );

      expect(log.selectedLogLevel, LogLevel.error);
      expect(log.filteredLogs, hasLength(1));
      expect(log.filteredLogs.single.level, 'E');
      // A bare word searches every field, so it is an "Any field" pill.
      expect(
        [
          for (final condition in log.filter.conditions)
            (condition.field, condition.operator, condition.value),
        ],
        [
          (
            FilterConditionField.packageName,
            FilterOperator.contains,
            'com.example.auth',
          ),
          (FilterConditionField.tag, FilterOperator.contains, 'Auth'),
          (FilterConditionField.pidTid, FilterOperator.contains, '101/202'),
          (FilterConditionField.anyField, FilterOperator.contains, 'signed in'),
        ],
      );
    },
  );

  test('typed filter syntax supports quoted values and repeated keys', () {
    final log = createLog();

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

    applyTypedFilter(
      log,
      'message:"background sync" message:worker tag:SyncWorker',
    );

    expect(log.filteredLogs, hasLength(1));
    expect(log.filteredLogs.single.message, contains('worker'));
    expect(log.recentFilters.message, isEmpty);
  });

  test('bare typed text matches the whole log entry, not only the message', () {
    final log = createLog();

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

    applyTypedFilter(log, 'AuthService');

    expect(log.filteredLogs, hasLength(1));
    expect(log.filteredLogs.single.tag, 'AuthService');

    applyTypedFilter(log, 'com.example.sync');

    expect(log.filteredLogs, hasLength(1));
    expect(log.filteredLogs.single.packageName, 'com.example.sync');
  });

  test(
    'streamed logs retain filtered matches longer while a filter is active',
    () async {
      final log = createLog(settings: testSettings(logLinesLimit: 3));

      log.applyFilters(
        LogFilters.fromFields(level: log.selectedLogLevel, message: 'keep'),
      );
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

      await Future<void>.delayed(const Duration(milliseconds: 400));

      final storedMessages = log.logs.map((entry) => entry.message).toList();
      expect(storedMessages, containsAll(['keep 1', 'keep 2']));
      expect(storedMessages, isNot(contains('drop 1')));
      expect(log.filteredLogs.map((entry) => entry.message), [
        'keep 1',
        'keep 2',
      ]);
    },
  );

  test(
    'a package filter keeps an unresolved-PID line once its package is learned',
    () async {
      final log = createLog(settings: testSettings(logLinesLimit: 3));

      applyTypedFilter(log, 'package:com.foo');
      await log.startLogcat();

      // Arrives before anything maps pid 500, so it's stored as non-matching.
      service.emit(testLogEntry(message: 'early', pid: '500'));
      await Future<void>.delayed(const Duration(milliseconds: 350));

      // Now pid 500 resolves, then enough unrelated lines to force eviction.
      service.emit(
        testLogEntry(message: 'late', pid: '500', packageName: 'com.foo'),
      );
      for (var index = 0; index < 10; index++) {
        service.emit(
          testLogEntry(message: 'other $index', pid: '${600 + index}'),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        log.logs.map((entry) => entry.message),
        containsAll(['early', 'late']),
        reason: 'the early line matches now, so it must not be evicted first',
      );
      expect(
        log.filteredLogs
            .where((entry) => !entry.isSpecialEntry)
            .map((entry) => entry.message),
        ['early', 'late'],
      );
    },
  );

  test(
    'an unresolved PID asks for a pid→package refresh only under a package filter',
    () async {
      final log = createLog();
      await log.startLogcat();

      service.emit(testLogEntry(message: 'unfiltered', pid: '500'));
      await Future<void>.delayed(Duration.zero);
      expect(service.pidRefreshRequests, 0);

      applyTypedFilter(log, 'package:com.foo');
      // Applying the filter asks once on its own; count lines from there.
      final base = service.pidRefreshRequests;
      service.emit(
        testLogEntry(message: 'resolved', pid: '501', packageName: 'com.bar'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        service.pidRefreshRequests,
        base,
        reason: 'it already has a package',
      );

      service.emit(testLogEntry(message: 'unresolved', pid: '502'));
      await Future<void>.delayed(Duration.zero);
      expect(service.pidRefreshRequests, base + 1);

      // Still unresolved after that ask: pid 502 doesn't ask again.
      service.emit(testLogEntry(message: 'still unresolved', pid: '502'));
      await Future<void>.delayed(Duration.zero);
      expect(service.pidRefreshRequests, base + 1);

      // pid 501 was learned from the resolved line above.
      service.emit(testLogEntry(message: 'learned', pid: '501'));
      await Future<void>.delayed(Duration.zero);
      expect(service.pidRefreshRequests, base + 1);
    },
  );

  test(
    'a pid→package refresh reveals and keeps lines that logged before it',
    () async {
      final log = createLog(settings: testSettings(logLinesLimit: 3));
      applyTypedFilter(log, 'package:com.foo');
      await log.startLogcat();

      service.emit(testLogEntry(message: 'early', pid: '500'));
      await Future<void>.delayed(const Duration(milliseconds: 350));
      List<String> visible() => log.filteredLogs
          .where((entry) => !entry.isSpecialEntry)
          .map((entry) => entry.message)
          .toList();
      expect(visible(), isEmpty);

      // The process goes quiet; only the refresh learns its package.
      var notified = 0;
      log.addListener(() => notified++);
      service.pushPidPackages({'500': 'com.foo', '600': 'com.bar'});
      await Future<void>.delayed(Duration.zero);
      expect(notified, greaterThan(0));
      expect(visible(), ['early']);

      for (var index = 0; index < 10; index++) {
        service.emit(
          testLogEntry(message: 'other $index', pid: '${700 + index}'),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(
        log.logs.map((entry) => entry.message),
        contains('early'),
        reason: 'the refresh re-flags it, so it is not evicted first',
      );
    },
  );

  test(
    'a settled package filter change asks for a pid→package refresh',
    () async {
      final log = createLog();
      applyTypedFilter(log, 'package:com.foo');
      expect(service.pidRefreshRequests, 0, reason: 'not capturing yet');

      await log.startLogcat();
      applyTypedFilter(log, 'package:com.foo level:error');
      expect(service.pidRefreshRequests, 0, reason: 'package terms unchanged');

      applyTypedFilter(log, 'package:com.bar');
      expect(service.pidRefreshRequests, 1);

      applyTypedFilter(log, 'tag:Foo');
      expect(service.pidRefreshRequests, 1, reason: 'no package terms');
    },
  );

  test('full pending queue flushes as a batch during a burst', () async {
    final log = createLog();
    LogController.maxPendingLogs = 2;

    await log.startLogcat();
    service.emit(testLogEntry(message: 'one'));
    service.emit(testLogEntry(message: 'two'));
    service.emit(testLogEntry(message: 'three'));
    await Future<void>.delayed(Duration.zero);

    // The first two entries are flushed together; the latest entry remains
    // queued for the normal periodic flush instead of triggering its own UI
    // update.
    expect(log.logs.map((entry) => entry.message), containsAll(['one', 'two']));
    expect(log.logs.any((entry) => entry.message == 'three'), isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(log.logs.map((entry) => entry.message), contains('three'));
  });

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

    log.setHiddenColumns({LogColumn.message.name});
    log.onInlineSearchOptionsChanged(
      TextSearchConfig(query: 'HiddenNeedle', caseSensitive: true),
    );

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

    log.onInlineSearchOptionsChanged(TextSearchConfig(wholeWord: true));
    expect(log.searchMatchIndices, [0]);

    log.onInlineSearchOptionsChanged(
      TextSearchConfig(wholeWord: false, regex: true),
    );
    log.openSearchBar(query: r'error\d+');
    expect(log.searchMatchIndices, [0, 1]);

    log.onInlineSearchOptionsChanged(TextSearchConfig(caseSensitive: true));
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

    log.onInlineSearchOptionsChanged(TextSearchConfig(regex: true));
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
    expect(log.inlineSearch.query, 'Selected needle');
    expect(log.appliedInlineSearch.query, 'Selected needle');
    expect(log.autoScroll, isFalse);
    expect(clipboard?.text, 'Selected needle');
  });

  test(
    'search navigation disables auto-scroll when moving between matches',
    () {
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
    },
  );

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

  test(
    'copyAllLogs copies formatted full log lines from cached logs',
    () async {
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
    },
  );

  test(
    'special entries are skipped by selection and copy operations',
    () async {
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
    },
  );

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

  test('setColumnWidths does not notify when the widths are unchanged', () {
    final log = createLog();
    log.setColumnWidths({LogColumn.tag.name: 120});

    var notifications = 0;
    log.addListener(() => notifications++);

    log.setColumnWidths({LogColumn.tag.name: 120});
    expect(notifications, 0);

    log.setColumnWidths({LogColumn.tag.name: 140});
    expect(notifications, 1);
    expect(log.columnWidths, {LogColumn.tag.name: 140});
  });

  test('setHiddenColumns does not notify when the columns are unchanged', () {
    final log = createLog();
    log.setHiddenColumns({LogColumn.pid.name});
    final revision = log.logViewerRevision;

    var notifications = 0;
    log.addListener(() => notifications++);

    log.setHiddenColumns({LogColumn.pid.name});
    expect(notifications, 0);
    expect(log.logViewerRevision, revision);

    log.setHiddenColumns({LogColumn.pid.name, LogColumn.tag.name});
    expect(notifications, 1);
    expect(log.logViewerRevision, revision + 1);
  });
}
