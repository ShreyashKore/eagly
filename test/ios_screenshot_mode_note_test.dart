import 'package:eagly/constants/app_constants.dart';
import 'package:eagly/features/mirror/components/ios_screenshot_mode_note.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    required bool suggestIos27,
  }) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: IosScreenshotModeNote(
            suggestIos27: suggestIos27,
            openUrl: opened.add,
          ),
        ),
      ),
    );
    return opened;
  }

  testWidgets('on Windows and Linux it points at iOS 27', (tester) async {
    await pump(tester, suggestIos27: true);

    expect(find.text('Screenshots, not live video'), findsOneWidget);
    expect(find.textContaining('iOS 27'), findsOneWidget);
  });

  testWidgets('on a Mac it leaves iOS 27 out', (tester) async {
    await pump(tester, suggestIos27: false);

    expect(find.textContaining('iOS 27'), findsNothing);
  });

  testWidgets('Read more opens the README section', (tester) async {
    final opened = await pump(tester, suggestIos27: true);

    await tester.tap(find.text('Read more'));

    expect(opened, [AppConstants.iosScreenshotMirrorUrl]);
  });
}
