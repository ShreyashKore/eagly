import 'package:eagly/features/logs/presentation/components/log_row.dart';
import 'package:eagly/features/logs/presentation/components/log_viewer.dart';
import 'package:eagly/features/logs/services/log_display_list.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  testWidgets('a folded run shows its count and unfolds from the chip', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final entries = [
      testLogEntry(message: 'first'),
      for (var i = 0; i < 4; i++)
        testLogEntry(
          message: 'again',
          level: 'W',
          timestamp: '2026-04-26 10:00:0$i.500',
        ),
      testLogEntry(message: 'last'),
    ];
    final rows = LogDisplayList()..sync(entries);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => LogViewer(
              logs: rows.entries,
              repeatAt: rows.repeatAt,
              onToggleRepeat: (row) => setState(() => rows.toggleRepeat(row)),
              scrollController: scrollController,
              wrapText: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final chip = find.byKey(const ValueKey('log-repeat-chip'));
    expect(find.byType(LogRow), findsNWidgets(3));
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.textContaining('×4 over 3.0 s')),
      findsOneWidget,
    );

    // Tinted with the row's level colour, like the badge.
    final theme = AppTheme.darkTheme.extension<EaglyTheme>()!;
    final box = tester.widget<Container>(
      find.descendant(of: chip, matching: find.byType(Container)).first,
    );
    expect(
      (box.decoration! as BoxDecoration).color,
      theme.logBadgeFill(theme.warningColor),
    );

    await tester.tap(chip);
    await tester.pump();
    expect(find.byType(LogRow), findsNWidgets(6));
    expect(chip, findsOneWidget, reason: 'the first row folds it back');
    expect(find.byIcon(Icons.unfold_less_rounded), findsOneWidget);

    await tester.tap(chip);
    await tester.pump();
    expect(find.byType(LogRow), findsNWidgets(3));
  });
}
