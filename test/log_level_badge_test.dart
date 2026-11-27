import 'dart:math' as math;

import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/presentation/components/log_viewer.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WCAG 2.x contrast ratio of [foreground] composited over [background].
double _contrast(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background);
  final a = fg.computeLuminance();
  final b = background.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

const _levels = ['V', 'D', 'I', 'W', 'E'];

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  for (final (name, themeOf) in [
    ('light', () => AppTheme.lightTheme),
    ('dark', () => AppTheme.darkTheme),
  ]) {
    // testWidgets, not test: building the theme starts google_fonts loads
    // (see test/text_emphasis_test.dart).
    testWidgets('$name: every level letter reads on its own badge tint', (
      _,
    ) async {
      final theme = themeOf();
      final tokens = theme.extension<EaglyTheme>()!;
      // Log rows sit on the pane's surfaceContainer (FeaturePane).
      final row = theme.colorScheme.surfaceContainer;
      for (final level in _levels) {
        final color = tokens.logLevelColor(level);
        final fill = Color.alphaBlend(tokens.logBadgeFill(color), row);
        expect(_contrast(color, fill), greaterThan(4.5), reason: level);
        // The same colour carries the message, on the bare row.
        expect(_contrast(color, row), greaterThan(4.5), reason: level);
      }
    });
  }

  testWidgets('the badge is a tint with the letter in the level colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 300,
            child: LogViewer(
              logs: [
                LogEntry(
                  timestamp: '04-20 10:00:00.000',
                  pid: '1',
                  tid: '2',
                  level: 'W',
                  tag: 'Tag',
                  message: 'careful',
                ),
              ],
              scrollController: ScrollController(),
              wrapText: false,
            ),
          ),
        ),
      ),
    );

    final tokens = AppTheme.darkTheme.extension<EaglyTheme>()!;
    final warning = tokens.logLevelColor('W');
    final badge = tester.widget<Container>(
      find.byKey(const ValueKey('log-level-badge')),
    );
    final decoration = badge.decoration! as BoxDecoration;
    expect(decoration.color, tokens.logBadgeFill(warning));
    expect(decoration.color!.a, lessThan(0.3));

    final letter = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const ValueKey('log-level-badge')),
        matching: find.byType(RichText),
      ),
    );
    expect(letter.text.style?.color, warning);
    expect(letter.text.style?.fontWeight, FontWeight.w700);
  });
}
