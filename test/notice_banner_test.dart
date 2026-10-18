import 'package:eagly/presentation/components/notice_banner.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpAt(
    WidgetTester tester,
    double width, {
    double textScale = 1,
    String message =
        'Pixel 8 disconnected. Reconnect it, then restart logging or open a '
        'new tab.',
  }) async {
    // The default 800px test surface would clamp the wider cases.
    await tester.binding.setSurfaceSize(Size(width + 100, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: NoticeBanner(
                edgeToEdge: true,
                icon: Icons.usb_off_rounded,
                title: 'Live logging stopped',
                message: message,
                actions: [
                  NoticeButton(
                    primary: true,
                    icon: Icons.restart_alt_rounded,
                    label: 'Restart logging',
                    onPressed: () {},
                  ),
                  NoticeButton(
                    icon: Icons.add,
                    label: 'New tab',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a notice whose text fits keeps its actions beside it', (
    tester,
  ) async {
    await pumpAt(tester, 900, message: 'Pixel 8 disconnected.');
    final message = tester.getRect(find.text('Pixel 8 disconnected.'));
    final button = tester.getRect(find.text('Restart logging'));
    expect(button.left, greaterThan(message.right));
    expect(button.top, lessThan(message.bottom));
  });

  testWidgets('text too long to sit beside the actions keeps the full row', (
    tester,
  ) async {
    await pumpAt(tester, 900);
    final message = tester.getRect(find.textContaining('Reconnect it'));
    final restart = tester.getRect(find.text('Restart logging'));
    // The text is never squeezed into a column to make room: the actions
    // move under it and it gets the row's width.
    expect(restart.top, greaterThan(message.bottom));
    expect(message.width, greaterThan(900 * 0.75));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow notice wraps its actions under the text', (
    tester,
  ) async {
    await pumpAt(tester, 480);
    final message = tester.getRect(find.textContaining('Reconnect it'));
    final restart = tester.getRect(find.text('Restart logging'));
    final newTab = tester.getRect(find.text('New tab'));
    expect(restart.top, greaterThan(message.bottom));
    // Both buttons fit on one line under the text, aligned with it.
    expect(newTab.top, restart.top);
    expect(
      tester.getRect(find.byType(FilledButton)).left,
      closeTo(message.left, 0.01),
    );
    // The text gets the row's full width instead of a thin column beside
    // the buttons, which is what kept the old notice tall.
    expect(message.width, greaterThan(480 * 0.75));
    expect(tester.takeException(), isNull);
  });

  // Whether the actions fit beside the text depends on the text and buttons
  // themselves, not on a fixed window width.
  for (final (width, scale) in [(640.0, 1.0), (900.0, 1.6)]) {
    testWidgets('actions wrap under the text when they would squeeze it '
        '(${width.toInt()}px, ${scale}x)', (tester) async {
      await pumpAt(tester, width, textScale: scale);
      final message = tester.getRect(find.textContaining('Reconnect it'));
      final restart = tester.getRect(find.text('Restart logging'));
      expect(restart.top, greaterThan(message.bottom));
      expect(tester.takeException(), isNull);
    });
  }
}
