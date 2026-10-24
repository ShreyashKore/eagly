import 'package:eagly/data/device.dart';
import 'package:eagly/features/crash_reports/components/crash_report_detail.dart';
import 'package:eagly/features/crash_reports/data/crash_report.dart';
import 'package:eagly/features/crash_reports/utils.dart';
import 'package:eagly/presentation/components/code_view.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: child),
  );

  String shown(WidgetTester tester) =>
      tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!.text;

  group('CodeView', () {
    testWidgets('shows the text and opens find from the toolbar', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const CodeView(text: 'one\ntwo', noun: 'report')),
      );

      expect(shown(tester), 'one\ntwo');
      expect(find.text('Find in report'), findsNothing);

      await tester.tap(find.byTooltip('Find in report (Ctrl+F)'));
      await tester.pump();
      expect(find.text('Find in report'), findsOneWidget);

      await tester.tap(find.byTooltip('Close find (Esc)'));
      await tester.pump();
      expect(find.text('Find in report'), findsNothing);
    });

    testWidgets('opens find already searching for initialFind', (tester) async {
      await tester.pumpWidget(
        host(
          const CodeView(
            text: 'one two\ntwo three',
            noun: 'report',
            initialFind: 'two',
          ),
        ),
      );
      for (var i = 0; i < 5 && find.text('1 / 2').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }

      expect(find.text('Find in report'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('the current match is selected in its own colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const CodeView(text: 'one two\ntwo three', noun: 'report')),
      );
      final tokens = AppTheme.lightTheme.extension<EaglyTheme>()!;
      CodeEditorStyle style() =>
          tester.widget<CodeEditor>(find.byType(CodeEditor)).style!;

      await tester.tap(find.byTooltip('Find in report (Ctrl+F)'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'two');
      // re_editor searches off the frame it was asked on.
      for (var i = 0; i < 5 && find.text('1 / 2').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(find.text('1 / 2'), findsOneWidget);

      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
      expect(
        editor.controller!.selection,
        editor.findController!.currentMatchSelection,
      );
      expect(
        style().selectionColor!.toARGB32() & 0xFFFFFF,
        tokens.searchCurrentMatchColor.toARGB32() & 0xFFFFFF,
      );
      // Every match is painted see-through, so the current one shows.
      expect(style().highlightColor!.a, lessThan(1));

      await tester.tap(find.byTooltip('Close (Esc)'));
      await tester.pump();
      editor.controller!.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 0,
      );
      await tester.pump();
      expect(
        style().selectionColor!.toARGB32() & 0xFFFFFF,
        isNot(tokens.searchCurrentMatchColor.toARGB32() & 0xFFFFFF),
      );
    });

    testWidgets('copies copyText rather than what is shown', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        host(const CodeView(text: 'pretty', copyText: 'raw', noun: 'body')),
      );

      await tester.tap(find.byTooltip('Copy body'));
      await tester.pump();

      expect(copied, 'raw');
      expect(find.text('Copied body.'), findsOneWidget);
    });

    testWidgets('new text resets wrapping to the one asked for', (
      tester,
    ) async {
      Widget view(String text, {required bool wrap}) =>
          host(CodeView(text: text, wordWrap: wrap));
      bool? wraps() =>
          tester.widget<CodeEditor>(find.byType(CodeEditor)).wordWrap;

      await tester.pumpWidget(view('a', wrap: true));
      await tester.tap(find.byTooltip('Don\'t wrap lines'));
      await tester.pump();
      expect(wraps(), isFalse);

      await tester.pumpWidget(view('b', wrap: true));
      expect(shown(tester), 'b');
      expect(wraps(), isTrue);
    });
  });

  testWidgets('a highlighted snippet keeps its text', (tester) async {
    const code = 'val x = 1';
    await tester.pumpWidget(
      host(
        HighlightedCodeText(
          code: code,
          language: langKotlin,
          style: const TextStyle(color: Colors.black),
        ),
      ),
    );

    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.textSpan!.toPlainText(), code);
    // Highlighting split it into styled pieces.
    expect(text.textSpan!.children, isNotEmpty);
  });

  group('crash report', () {
    const ips =
        '{"app_name":"Runner","timestamp":"2026-10-01 10:00:00.00 +0000"}\n'
        '{"exception":{"type":"EXC_BAD_ACCESS"},"threads":[]}';

    test('an .ips report pretty-prints both its parts', () {
      expect(
        CrashReportUtils.prettyIps(ips),
        '{\n'
        '  "app_name": "Runner",\n'
        '  "timestamp": "2026-10-01 10:00:00.00 +0000"\n'
        '}\n'
        '{\n'
        '  "exception": {\n'
        '    "type": "EXC_BAD_ACCESS"\n'
        '  },\n'
        '  "threads": []\n'
        '}',
      );
    });

    test('a .crash report is not pretty-printed', () {
      expect(
        CrashReportUtils.prettyIps('Process: Runner [1]\nDate/Time: now'),
        isNull,
      );
    });

    Future<DeviceSessionController> showReport(
      WidgetTester tester,
      String body,
    ) async {
      final device = Device.ios('UDID', 'iPhone');
      final session = DeviceSessionController(
        device: device,
        service: FakeSessionService(device),
      );
      addTearDown(session.dispose);
      session.crashReportController
        ..selectedReport = CrashReport(
          fileName: 'Runner-2026-10-01.ips',
          filePath: '/tmp/Runner.ips',
          processName: 'Runner',
          timestamp: DateTime(2026, 10, 1),
          sizeBytes: body.length,
        )
        ..selectedReportBody = body;
      await tester.pumpWidget(
        host(CrashReportDetail(controller: session.crashReportController)),
      );
      await tester.pump();
      return session;
    }

    testWidgets('an .ips report shows pretty, and as written on request', (
      tester,
    ) async {
      await showReport(tester, ips);

      expect(find.text('Runner-2026-10-01.ips'), findsOneWidget);
      expect(shown(tester), CrashReportUtils.prettyIps(ips));

      await tester.tap(find.byTooltip('Show as written'));
      await tester.pump();
      expect(shown(tester), ips);
    });

    testWidgets('a .crash report shows as written, with no pretty toggle', (
      tester,
    ) async {
      const crash = 'Process: Runner [1]\nDate/Time: now';
      await showReport(tester, crash);

      expect(shown(tester), crash);
      expect(find.byTooltip('Pretty-print'), findsNothing);
      expect(find.byTooltip('Show as written'), findsNothing);
    });
  });
}
