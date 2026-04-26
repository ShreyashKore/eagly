// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logview/data/log_column.dart';
import 'package:logview/data/log_entry.dart';
import 'package:logview/services/preferences_service.dart';
import 'package:logview/theme/app_theme.dart';
import 'package:logview/widgets/log_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  Future<void> pumpLogViewer(
    WidgetTester tester, {
    List<LogEntry>? logs,
    required bool wrapText,
    Map<String, double> columnWidths = const <String, double>{},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 400,
            child: LogViewer(
              logs:
                  logs ??
                  [
                    LogEntry(
                      timestamp: '04-20 10:00:00.000',
                      pid: '123',
                      tid: '456',
                      level: 'I',
                      tag: 'Tag',
                      message: 'short message',
                    ),
                  ],
              scrollController: ScrollController(),
              wrapText: wrapText,
              columnWidths: columnWidths,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Iterable<double?> messageColumnWidths(WidgetTester tester) {
    return tester
        .widgetList<SizedBox>(
          find.ancestor(
            of: find.text('Message'),
            matching: find.byType(SizedBox),
          ),
        )
        .map((box) => box.width);
  }

  testWidgets('uses 4000px minimum width when wrapText is disabled', (
    WidgetTester tester,
  ) async {
    await pumpLogViewer(tester, wrapText: false);

    expect(
      messageColumnWidths(tester),
      contains(LogViewer.defaultUnwrappedMessageWidth),
    );
  });

  testWidgets('uses a manually expanded message width when it exceeds 4000', (
    WidgetTester tester,
  ) async {
    const largerWidth = 5321.5;

    await pumpLogViewer(
      tester,
      wrapText: false,
      columnWidths: {LogColumn.message.name: largerWidth},
    );

    expect(messageColumnWidths(tester), contains(largerWidth));
  });

  testWidgets('grows beyond 4000 based on a built long message', (
    WidgetTester tester,
  ) async {
    await pumpLogViewer(
      tester,
      wrapText: false,
      logs: [
        LogEntry(
          timestamp: '04-20 10:00:00.000',
          pid: '123',
          tid: '456',
          level: 'I',
          tag: 'Tag',
          message: List.filled(1000, 'W').join(),
        ),
      ],
    );

    expect(
      messageColumnWidths(tester).whereType<double>().any(
        (width) => width > LogViewer.defaultUnwrappedMessageWidth,
      ),
      isTrue,
    );
  });
}
