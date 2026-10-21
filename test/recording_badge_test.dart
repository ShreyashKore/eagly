import 'package:eagly/features/mirror/components/recording_badge.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  const limit = Duration(minutes: 3);

  /// A badge for a recording that has run [elapsed] so far. The badge reads
  /// the wall clock, so each case sits half a second into its second.
  Future<void> pumpBadge(WidgetTester tester, Duration elapsed) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: RecordingBadge(
              startedAt: DateTime.now().subtract(
                elapsed + const Duration(milliseconds: 500),
              ),
              timeLimit: limit,
            ),
          ),
        ),
      ),
    );
  }

  Color? timeColor(WidgetTester tester, String time) =>
      tester.widget<Text>(find.text(time)).style?.color;

  testWidgets('shows the time recorded against the limit', (tester) async {
    await pumpBadge(tester, const Duration(seconds: 42));

    expect(find.text('0:42'), findsOneWidget);
    expect(find.text(' / 3:00'), findsOneWidget);
    expect(timeColor(tester, '0:42'), isNot(Colors.orange));
  });

  testWidgets('warns in the last seconds before the limit', (tester) async {
    await pumpBadge(tester, const Duration(minutes: 2, seconds: 50));

    expect(find.text('2:50'), findsOneWidget);
    expect(timeColor(tester, '2:50'), Colors.orange);
  });

  testWidgets('says when the limit has stopped the recording', (tester) async {
    await pumpBadge(tester, const Duration(minutes: 4));

    expect(find.text('3:00'), findsOneWidget);
    expect(find.textContaining('limit reached'), findsOneWidget);
  });

  testWidgets('lets clicks through to the mirror underneath', (tester) async {
    await pumpBadge(tester, const Duration(seconds: 5));

    expect(
      find.ancestor(
        of: find.text('0:05'),
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsOneWidget,
    );
  });
}
