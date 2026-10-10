import 'package:eagly/presentation/components/combo_field.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _options = [
  ComboOption(
    value: 'android.permission.CAMERA',
    label: 'Camera',
    description: 'android.permission.CAMERA',
  ),
  ComboOption(
    value: 'android.permission.RECORD_AUDIO',
    label: 'Microphone',
    description: 'android.permission.RECORD_AUDIO',
  ),
  ComboOption(
    value: 'android.permission.ACCESS_FINE_LOCATION',
    label: 'Location (precise)',
    description: 'android.permission.ACCESS_FINE_LOCATION',
  ),
  ComboOption(
    value: 'android.permission.READ_CONTACTS',
    label: 'Contacts (read)',
    description: 'android.permission.READ_CONTACTS',
  ),
];

void main() {
  group('ComboField.filter', () {
    List<String> labels(String query) => [
      for (final o in ComboField.filter(_options, query)) o.label,
    ];

    test('an empty query lists everything in order', () {
      expect(labels(''), _options.map((o) => o.label));
    });

    test('label prefixes rank above word starts and substrings', () {
      // "co": Contacts starts with it; CAMERA / READ_CONTACTS' values have a
      // word starting with it only for READ_CONTACTS, which is the same
      // option — so Contacts is first and Location's "(precise)" is absent.
      expect(labels('co').first, 'Contacts (read)');
      expect(labels('audio'), ['Microphone']);
      expect(labels('record'), ['Microphone']);
      expect(labels('fine_loc'), ['Location (precise)']);
    });

    test('falls back to a fuzzy match on the label', () {
      expect(labels('mcrph'), ['Microphone']);
    });

    test('nothing matching yields an empty list', () {
      expect(labels('zzzz'), isEmpty);
    });
  });

  group('ComboField', () {
    late TextEditingController controller;
    late List<String> submitted;
    late List<String> changes;

    setUp(() {
      controller = TextEditingController();
      submitted = [];
      changes = [];
    });
    tearDown(() => controller.dispose());

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ComboField(
              controller: controller,
              options: _options,
              onChanged: changes.add,
              onSubmitted: submitted.add,
            ),
          ),
        ),
      ),
    );

    testWidgets('typing filters the list and Enter picks the top match', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'mic');
      await tester.pump();
      expect(find.text('Microphone'), findsOneWidget);
      expect(find.text('Camera'), findsNothing);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(controller.text, 'android.permission.RECORD_AUDIO');
      expect(changes.last, 'android.permission.RECORD_AUDIO');
      expect(find.text('Microphone'), findsNothing, reason: 'list closed');
      expect(submitted, isEmpty, reason: 'Enter picked, it did not submit');

      // With the list closed, Enter submits.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, ['android.permission.RECORD_AUDIO']);
    });

    testWidgets('arrow keys move the highlight; Esc closes the list', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.text('Camera'), findsOneWidget, reason: 'opens on click');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(controller.text, 'android.permission.ACCESS_FINE_LOCATION');

      // ↓ reopens; ↑ from the first entry wraps to the last.
      controller.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.text('Camera'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(controller.text, 'android.permission.READ_CONTACTS');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.text('Camera'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Camera'), findsNothing);
      expect(controller.text, 'android.permission.READ_CONTACTS');
    });

    testWidgets('the arrow button lists every option whatever was typed', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'mic');
      await tester.pump();
      await tester.tap(find.byTooltip('Hide suggestions'));
      await tester.pump();
      expect(find.text('Microphone'), findsNothing);

      await tester.tap(find.byTooltip('Show all suggestions'));
      await tester.pump();
      for (final option in _options) {
        expect(find.text(option.label), findsOneWidget);
      }
      await tester.tap(find.text('Camera'));
      await tester.pump();
      expect(controller.text, 'android.permission.CAMERA');
    });

    testWidgets('free text is kept when nothing matches', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'com.custom.PERM');
      await tester.pump();
      expect(find.byType(ListView), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, ['com.custom.PERM']);
    });
  });
}
