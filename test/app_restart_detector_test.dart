import 'package:eagly/data/device.dart';
import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/presentation/components/log_viewer.dart';
import 'package:eagly/features/logs/services/app_restart_detector.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

const _systemServer = '1500';
const _notes = 'com.example.notes';

/// An ActivityManager line from system_server.
LogEntry am(String message) => testLogEntry(
  message: message,
  pid: _systemServer,
  tag: 'ActivityManager',
  packageName: 'system_server',
);

/// A line of the notes app; [resolved] says whether Eagly knew the pid's
/// package when it arrived (a fresh process's first lines usually don't).
LogEntry app(String pid, String message, {bool resolved = true}) =>
    testLogEntry(
      message: message,
      pid: pid,
      tag: 'Notes',
      packageName: resolved ? _notes : null,
    );

LogEntry other(String message) => testLogEntry(
  message: message,
  pid: '2200',
  tag: 'Gms',
  packageName: 'com.google.android.gms',
);

const _start4188 =
    'Start proc 4188:com.example.notes/u0a190 for top-activity '
    '{com.example.notes/com.example.notes.MainActivity}';
const _died4121 = 'Process com.example.notes (pid 4121) has died: fg  TOP';

/// Each entry as its message, a marker as `<message>`.
List<String> read(List<LogEntry> entries) => [
  for (final entry in entries)
    entry.type == LogEntryType.restarted ? '<${entry.message}>' : entry.message,
];

List<String> annotate(List<LogEntry> entries) =>
    read(AppRestartDetector().annotate(entries));

void main() {
  test('marks the restart before the new process\'s first line', () {
    final detector = AppRestartDetector();
    final entries = detector.annotate([
      app('4121', 'onCreate'),
      am(_died4121),
      other('sync'),
      am(_start4188),
      other('sync again'),
      app('4188', 'onCreate', resolved: false),
      app('4188', 'onResume', resolved: false),
    ]);

    expect(read(entries), [
      'onCreate',
      _died4121,
      'sync',
      _start4188,
      'sync again',
      '<com.example.notes restarted · pid 4121 → 4188>',
      'onCreate',
      'onResume',
    ]);
    final marker = entries[5];
    expect(marker.packageName, _notes);
    expect(marker.pid, '4188');
    expect(marker.timestamp, entries[6].timestamp);
  });

  test('reads the Android 12 to 15 start reasons', () {
    for (final reason in [
      'top-activity {com.example.notes/com.example.notes.MainActivity}',
      'pre-top-activity {com.example.notes/com.example.notes.MainActivity}',
      'service {com.example.notes/com.example.notes.SyncService}',
      'broadcast {com.example.notes/com.example.notes.BootReceiver}',
      'content provider {com.example.notes/com.example.notes.Provider}',
    ]) {
      expect(
        annotate([
          app('4121', 'before'),
          am('Start proc 4188:com.example.notes/u0a190 for $reason'),
          app('4188', 'after', resolved: false),
        ]),
        contains('<com.example.notes restarted · pid 4121 → 4188>'),
        reason: reason,
      );
    }
  });

  test('reads the older start format', () {
    expect(
      annotate([
        app('4121', 'before'),
        am(
          'Start proc com.example.notes for activity '
          'com.example.notes/.MainActivity: pid=4188 uid=10190 gids={50190}',
        ),
        app('4188', 'after', resolved: false),
      ]),
      contains('<com.example.notes restarted · pid 4121 → 4188>'),
    );
  });

  test('marks nothing for a process that never logged before', () {
    expect(
      annotate([
        other('sync'),
        am(
          'Start proc 5012:com.google.android.gms.persistent/u0a120 for '
          'service {com.google.android.gms/com.google.android.gms.Service}',
        ),
        testLogEntry(message: 'persistent up', pid: '5012', tag: 'Gms'),
        am(_start4188),
        app('4188', 'first launch', resolved: false),
      ]).where((line) => line.startsWith('<')),
      isEmpty,
    );
  });

  test('marks a restart once, however often it is announced', () {
    final lines = annotate([
      app('4121', 'before'),
      am(_start4188),
      am(_start4188),
      app('4188', 'one', resolved: false),
      am(_start4188),
      app('4188', 'two'),
      app('4188', 'three'),
    ]);
    expect(lines.where((line) => line.startsWith('<')), hasLength(1));
  });

  test('a dead process\'s late lines do not mark it again', () {
    final lines = annotate([
      app('4121', 'before'),
      am(_died4121),
      am(_start4188),
      app('4188', 'up', resolved: false),
      app('4121', 'late stderr'),
      app('4188', 'still up'),
    ]);
    expect(lines.where((line) => line.startsWith('<')), hasLength(1));
  });

  test('a second restart is marked from the second pid', () {
    final lines = annotate([
      app('4121', 'one'),
      am(_start4188),
      app('4188', 'two', resolved: false),
      am(
        'Killing 4188:com.example.notes/u0a190 (adj 0): stop com.example.notes',
      ),
      am(
        'Start proc 4301:com.example.notes/u0a190 for top-activity '
        '{com.example.notes/com.example.notes.MainActivity}',
      ),
      app('4301', 'three', resolved: false),
    ]);
    expect(lines.where((line) => line.startsWith('<')), [
      '<com.example.notes restarted · pid 4121 → 4188>',
      '<com.example.notes restarted · pid 4188 → 4301>',
    ]);
  });

  test('a line ahead of its Start proc puts the marker at that line', () {
    expect(
      annotate([
        app('4121', 'before'),
        app('4188', 'early', resolved: false),
        am(_start4188),
        app('4188', 'after'),
      ]),
      [
        'before',
        'early',
        '<com.example.notes restarted · pid 4121 → 4188>',
        _start4188,
        'after',
      ],
    );
  });

  test('without a Start proc, a death and a new pid still mark it', () {
    expect(
      annotate([
        app('4121', 'before'),
        am(_died4121),
        app('4188', 'unresolved', resolved: false),
        app('4188', 'resolved'),
      ]),
      [
        'before',
        _died4121,
        'unresolved',
        '<com.example.notes restarted · pid 4121 → 4188>',
        'resolved',
      ],
    );
  });

  test('a death ties unresolved lines to their process', () {
    expect(
      annotate([
        app('4121', 'unresolved', resolved: false),
        am(_died4121),
        am(_start4188),
        app('4188', 'after', resolved: false),
      ]),
      contains('<com.example.notes restarted · pid 4121 → 4188>'),
    );
  });

  test('uses the pid index for lines that came without a package', () {
    final detector = AppRestartDetector(
      packageForPid: (pid) => pid == '4121' ? _notes : null,
    );
    expect(
      read(
        detector.annotate([
          app('4121', 'before', resolved: false),
          am(_start4188),
          app('4188', 'after', resolved: false),
        ]),
      ),
      contains('<com.example.notes restarted · pid 4121 → 4188>'),
    );
  });

  test('a restart while paused is marked at the first line after', () {
    final detector = AppRestartDetector();
    expect(detector.observe(app('4121', 'before')), isNull);
    detector
      ..observeSignalsOnly(am(_died4121))
      ..observeSignalsOnly(am(_start4188))
      ..observeSignalsOnly(app('4188', 'dropped', resolved: false));
    expect(
      detector.observe(app('4188', 'after resume'))?.message,
      'com.example.notes restarted · pid 4121 → 4188',
    );
  });

  test('ignores iOS lines and forgets on reset', () {
    LogEntry ios(String pid, String message) => LogEntry(
      platform: DevicePlatform.ios,
      timestamp: '2026-04-26 10:00:00.000',
      pid: pid,
      tid: '0',
      level: 'default',
      tag: 'ActivityManager',
      message: message,
      packageName: _notes,
    );
    expect(
      annotate([ios('4121', 'a'), ios('1', _start4188), ios('4188', 'b')]),
      ['a', _start4188, 'b'],
    );

    final detector = AppRestartDetector()..observe(app('4121', 'before'));
    detector
      ..reset()
      ..observe(am(_start4188));
    expect(detector.observe(app('4188', 'after')), isNull);
  });

  testWidgets('the divider leads with the app that restarted', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final logs = AppRestartDetector().annotate([
      app('4121', 'before'),
      am(_start4188),
      app('4188', 'after', resolved: false),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: LogViewer(
            logs: logs,
            scrollController: scrollController,
            wrapText: false,
          ),
        ),
      ),
    );
    await tester.pump();

    final divider = find.byKey(const ValueKey('special-log-row'));
    expect(divider, findsOneWidget);
    expect(
      find.descendant(
        of: divider,
        matching: find.byIcon(Icons.refresh_rounded),
      ),
      findsOneWidget,
    );
    for (final text in [_notes, 'restarted · pid 4121 → 4188']) {
      expect(
        find.descendant(
          of: divider,
          matching: find.text(text, findRichText: true),
        ),
        findsOneWidget,
        reason: text,
      );
    }
  });
}
