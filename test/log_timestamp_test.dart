import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/presentation/components/log_viewer.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/utils/log_timestamp.dart';
import 'package:flutter/material.dart';
import 'package:eagly/utils/text_search_pattern.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  group('LogTimestampParts', () {
    String joined(LogTimestampParts p) =>
        '${p.datePrefix}${p.time}${p.fraction}${p.suffix}';

    test('splits an Android logcat timestamp', () {
      final parts = LogTimestampParts.tryParse('10-18 01:49:18.312')!;
      expect(parts.datePrefix, '10-18 ');
      expect(parts.time, '01:49:18');
      expect(parts.fraction, '.312');
      expect(parts.year, isNull);
      expect(parts.dateLabel(currentYear: 2026), 'Oct 18');
    });

    test('splits an iOS / imported timestamp, with its year', () {
      final parts = LogTimestampParts.tryParse('2025-01-02 23:04:05.006')!;
      expect(parts.datePrefix, '2025-01-02 ');
      expect(parts.time, '23:04:05');
      expect(parts.fraction, '.006');
      expect(parts.dateLabel(currentYear: 2025), 'Jan 2');
      expect(parts.dateLabel(currentYear: 2026), 'Jan 2, 2025');
    });

    test('takes ISO separators, zones and a bare time of day', () {
      expect(
        joined(LogTimestampParts.tryParse('2026-03-04T05:06:07,890Z')!),
        '2026-03-04T05:06:07,890Z',
      );
      final bare = LogTimestampParts.tryParse('05:06:07')!;
      expect(bare.datePrefix, '');
      expect(bare.fraction, '');
      expect(bare.hasDate, isFalse);
      expect(bare.dateLabel(), isNull);
    });

    test('the parts always join back into the original', () {
      for (final raw in [
        '10-18 01:49:18.312',
        '2026-10-18 01:49:18.312',
        '2026-10-18 01:49:18',
        '2026-10-18T01:49:18.312+05:30',
      ]) {
        expect(joined(LogTimestampParts.tryParse(raw)!), raw);
      }
    });

    test('leaves anything else alone', () {
      for (final raw in [
        '',
        'yesterday',
        '13-40 01:49:18.312',
        '1700000000.123',
        '10-18 01:49',
        '10-18 01:49:18.312 extra',
      ]) {
        expect(LogTimestampParts.tryParse(raw), isNull, reason: raw);
      }
    });
  });

  group('timestamp column', () {
    LogEntry entry(String timestamp, [String message = 'hello']) => LogEntry(
      timestamp: timestamp,
      pid: '1',
      tid: '2',
      level: 'I',
      tag: 'Tag',
      message: message,
    );

    String? selectedText;

    Future<void> pump(WidgetTester tester, List<LogEntry> logs) async {
      selectedText = null;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 300,
              child: LogViewer(
                logs: logs,
                scrollController: ScrollController(),
                wrapText: false,
                onSelectedTextChanged: (text) => selectedText = text,
              ),
            ),
          ),
        ),
      );
      // The header's date lands a frame after the rows are measured.
      await tester.pump();
    }

    /// The spans of the row's timestamp cell, separators included.
    List<TextSpan> timestampSpans(WidgetTester tester, String timestamp) {
      final cell = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((w) => w.text.toPlainText().startsWith(timestamp));
      // Text.rich wraps the cell's span in one carrying the default style.
      final root = (cell.text as TextSpan).children!.single as TextSpan;
      return root.children!.cast<TextSpan>();
    }

    testWidgets('rows show the time, the date moves to the header', (
      tester,
    ) async {
      await pump(tester, [entry('10-18 01:49:18.312')]);

      final spans = timestampSpans(tester, '10-18 01:49:18.312');
      expect(spans.map((s) => s.text).toList(), [
        '10-18 ',
        '01:49:18',
        '.312',
        ' ', // the cell separator
      ]);
      // The date is still there for a selection, just drawn at zero size.
      expect(spans[0].style?.fontSize, 0);
      expect(spans[1].style?.fontSize, isNot(0));
      final tokens = AppTheme.darkTheme.extension<EaglyTheme>()!;
      expect(spans[1].style?.color, tokens.tertiaryTextColor);
      expect(spans[2].style?.color, tokens.timestampFractionColor);

      expect(find.text('Time · Oct 18'), findsOneWidget);
    });

    testWidgets('the header follows the date of the top visible row', (
      tester,
    ) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      String second(int i) => '$i'.padLeft(2, '0');
      final logs = [
        for (var i = 0; i < 60; i++) entry('10-18 23:59:${second(i)}.000'),
        for (var i = 0; i < 60; i++) entry('10-19 00:00:${second(i)}.000'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: LogViewer(
                logs: logs,
                scrollController: scrollController,
                wrapText: false,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Time · Oct 18'), findsOneWidget);

      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      // New rows report in a frame's post-frame pass and are measured in
      // the next one; the header rebuilds in the frame after that.
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(find.text('Time · Oct 19'), findsOneWidget);
    });

    testWidgets('copying a selection keeps the whole timestamp', (
      tester,
    ) async {
      await pump(tester, [entry('10-18 01:49:18.312', 'copied message')]);

      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      region.selectAll(SelectionChangedCause.keyboard);
      await tester.pump();

      expect(selectedText, contains('10-18 01:49:18.312 '));
      expect(selectedText, contains('copied message'));
    });

    testWidgets('an iOS timestamp names its year only when it is not this '
        'one', (tester) async {
      final lastYear = DateTime.now().year - 1;
      await pump(tester, [entry('$lastYear-01-02 03:04:05.678')]);
      expect(find.text('Time · Jan 2, $lastYear'), findsOneWidget);
      final spans = timestampSpans(tester, '$lastYear-01-02 03:04:05.678');
      expect(spans[1].text, '03:04:05');
    });

    testWidgets('a timestamp that does not parse is shown as it is', (
      tester,
    ) async {
      await pump(tester, [entry('sometime')]);
      expect(timestampSpans(tester, 'sometime').first.text, 'sometime');
      expect(find.text('Timestamp'), findsOneWidget);
    });

    testWidgets('search still matches the hidden date', (tester) async {
      final logs = [entry('10-18 01:49:18.312')];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: LogViewer(
              logs: logs,
              scrollController: ScrollController(),
              wrapText: false,
              search: const TextSearchConfig(query: '18 01:49'),
            ),
          ),
        ),
      );
      final spans = timestampSpans(tester, '10-18 01:49:18.312');
      expect(spans.map((s) => s.text).join(), '10-18 01:49:18.312 ');
      // The match runs from the hidden date into the shown time; the shown
      // half is highlighted.
      final highlighted = spans.where((s) => s.style?.backgroundColor != null);
      expect(highlighted.map((s) => s.text), contains('01:49'));
    });
  });
}
