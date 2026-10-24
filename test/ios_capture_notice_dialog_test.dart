import 'package:eagly/features/mirror/components/ios_capture_notice_dialog.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  Future<Future<bool?>> open(WidgetTester tester) async {
    late Future<bool?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showDialog<bool>(
              context: context,
              builder: (_) => const IosCaptureNoticeDialog(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('starting with the box ticked stops asking', (tester) async {
    final result = await open(tester);
    expect(find.textContaining("only the iPhone's screen"), findsOneWidget);

    await tester.ensureVisible(find.text("Don't show this again"));
    await tester.tap(find.text("Don't show this again"));
    await tester.pump();
    await tester.tap(find.text('Start mirror'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(PreferencesService.skipIosCaptureNotice, isTrue);
  });

  testWidgets('cancelling keeps asking, even with the box ticked', (
    tester,
  ) async {
    final result = await open(tester);

    await tester.ensureVisible(find.text("Don't show this again"));
    await tester.tap(find.text("Don't show this again"));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
    expect(PreferencesService.skipIosCaptureNotice, isFalse);
  });
}
