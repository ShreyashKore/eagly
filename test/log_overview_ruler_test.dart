import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/presentation/components/log_overview_ruler.dart';
import 'package:eagly/features/logs/presentation/components/log_viewer.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

List<LogEntry> _logs(String levels) => [
  for (var i = 0; i < levels.length; i++)
    testLogEntry(message: 'line $i', level: levels[i]),
];

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  group('computeOverviewMarks', () {
    test('a line covers every row of its share when rows outnumber lines', () {
      final marks = computeOverviewMarks(
        logs: _logs('IEIW'),
        searchMatches: const [],
        rows: 8,
      );
      expect(marks, [
        0, 0, //
        OverviewMark.error, OverviewMark.error,
        0, 0,
        OverviewMark.warning, OverviewMark.warning,
      ]);
    });

    test('a row keeps the worst of the lines it covers', () {
      // 12 lines on 3 rows: four lines a row.
      final marks = computeOverviewMarks(
        logs: _logs(
          'IIWI'
          'IEIW'
          'DDVI',
        ),
        searchMatches: const [],
        rows: 3,
      );
      expect(marks[0], OverviewMark.warning);
      // An error and a warning share row 1; both bits are kept and the
      // painter draws the error.
      expect(marks[1] & OverviewMark.error, OverviewMark.error);
      expect(marks[2], 0);
    });

    test('search matches carry their own bit', () {
      final marks = computeOverviewMarks(
        logs: _logs('IIIE'),
        searchMatches: const [0, 3, 99],
        rows: 4,
      );
      expect(marks, [
        OverviewMark.searchMatch,
        0,
        0,
        OverviewMark.error | OverviewMark.searchMatch,
      ]);
    });

    test('reads iOS and long-form level names', () {
      final logs = [
        testLogEntry(message: 'a', level: 'Fault'),
        testLogEntry(message: 'b', level: 'Default'),
        testLogEntry(message: 'c', level: 'warning'),
      ];
      expect(computeOverviewMarks(logs: logs, searchMatches: [], rows: 3), [
        OverviewMark.error,
        0,
        OverviewMark.warning,
      ]);
    });

    test('100k lines bucket quickly', () {
      final logs = [
        for (var i = 0; i < 100000; i++)
          testLogEntry(
            message: 'line $i',
            level: i % 997 == 0 ? 'E' : (i % 101 == 0 ? 'W' : 'I'),
          ),
      ];
      final watch = Stopwatch()..start();
      final marks = computeOverviewMarks(
        logs: logs,
        searchMatches: [for (var i = 0; i < 100000; i += 500) i],
        rows: 900,
      );
      watch.stop();
      expect(marks.where((m) => m & OverviewMark.error != 0), isNotEmpty);
      // Generous for a loaded CI machine; it runs in a few ms.
      expect(watch.elapsedMilliseconds, lessThan(200));
    });

    test('nothing to bucket', () {
      expect(
        computeOverviewMarks(logs: const [], searchMatches: [], rows: 10),
        everyElement(0),
      );
      expect(
        computeOverviewMarks(logs: _logs('E'), searchMatches: [], rows: 0),
        isEmpty,
      );
    });
  });

  group('in the viewer', () {
    Future<ScrollController> pump(
      WidgetTester tester,
      List<LogEntry> logs, {
      List<int> matches = const [],
    }) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: LogViewer(
                logs: logs,
                scrollController: scrollController,
                wrapText: false,
                searchMatchIndices: matches,
              ),
            ),
          ),
        ),
      );
      return scrollController;
    }

    final ruler = find.byKey(const ValueKey('log-overview-ruler'));

    testWidgets('is hidden with nothing to mark', (tester) async {
      await pump(tester, _logs('IIDV'));
      expect(ruler, findsNothing);
      await pump(tester, const []);
      expect(ruler, findsNothing);
    });

    testWidgets('shows for errors, warnings or search matches', (tester) async {
      await pump(tester, _logs('IIEI'));
      expect(ruler, findsOneWidget);
      expect(tester.getSize(ruler).width, LogOverviewRuler.width);

      await pump(tester, _logs('IIII'), matches: const [2]);
      // Throttled: the update lands within the refresh interval.
      await tester.pump(LogOverviewRuler.refreshInterval);
      expect(ruler, findsOneWidget);
    });

    testWidgets('a click jumps the list to that point of the log', (
      tester,
    ) async {
      final logs = [
        for (var i = 0; i < 2000; i++)
          testLogEntry(message: 'line $i', level: i == 1500 ? 'E' : 'I'),
      ];
      final scrollController = await pump(tester, logs);
      // Messages are rich text, ending in the row terminator.
      Finder line(String text) => find.textContaining(text, findRichText: true);
      expect(scrollController.offset, 0);
      expect(line('line 0'), findsOneWidget);

      final rect = tester.getRect(ruler);
      await tester.tapAt(Offset(rect.center.dx, rect.top + rect.height * 0.75));
      await tester.pump();
      await tester.pump();

      expect(line('line 1500'), findsOneWidget);
      expect(line('line 0'), findsNothing);
    });
  });
}
