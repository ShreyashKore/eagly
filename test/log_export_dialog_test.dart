import 'package:eagly/features/logs/presentation/components/log_export_dialog.dart';
import 'package:eagly/features/logs/services/log_file_service.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  /// Opens the dialog with the given counts; the returned future completes
  /// with what it was closed with.
  Future<Future<LogExportChoice?>> open(
    WidgetTester tester, {
    int all = 10,
    int filtered = 10,
    int selected = 0,
    List<String> hiddenColumnLabels = const [],
  }) async {
    late Future<LogExportChoice?> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showLogExportDialog(
              context,
              allCount: all,
              filteredCount: filtered,
              selectedCount: selected,
              hiddenColumnLabels: hiddenColumnLabels,
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

  RadioListTile<LogExportScope> scopeTile(WidgetTester tester, String label) =>
      tester.widget<RadioListTile<LogExportScope>>(
        find.widgetWithText(RadioListTile<LogExportScope>, label),
      );

  testWidgets('starts on the filtered view when a filter hides entries', (
    tester,
  ) async {
    final result = await open(tester, all: 10, filtered: 4);

    expect(scopeTile(tester, 'Selected rows').enabled, isFalse);
    expect(find.text('4 entries'), findsOneWidget);

    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();

    final choice = await result;
    expect(choice?.scope, LogExportScope.filtered);
    expect(choice?.format, LogExportFormat.androidStudio);
  });

  testWidgets('starts on the selection, and disables a no-op filter', (
    tester,
  ) async {
    final result = await open(tester, all: 10, filtered: 10, selected: 2);

    expect(scopeTile(tester, 'Matching the current filters').enabled, isFalse);
    expect(find.text('The filters hide nothing'), findsOneWidget);

    await tester.tap(find.text('Plain text'));
    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();

    final choice = await result;
    expect(choice?.scope, LogExportScope.selected);
    expect(choice?.format, LogExportFormat.plainText);
  });

  testWidgets('starts on the format used last time', (tester) async {
    PreferencesService.logExportFormat = LogExportFormat.plainText.name;
    final result = await open(tester);

    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();

    final choice = await result;
    expect(choice?.scope, LogExportScope.all);
    expect(choice?.format, LogExportFormat.plainText);
  });

  testWidgets('plain text offers to leave hidden columns out', (tester) async {
    final result = await open(tester, hiddenColumnLabels: ['Package', 'Tag']);
    const option = 'Only the columns shown in the viewer';

    // JSON always carries every field, so the option is plain text's only.
    expect(find.text(option), findsNothing);

    await tester.tap(find.text('Plain text'));
    await tester.pumpAndSettle();
    expect(find.text(option), findsOneWidget);
    expect(find.text('Leaves out Package, Tag'), findsOneWidget);

    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();
    expect((await result)?.visibleColumnsOnly, isTrue);
  });

  testWidgets('the visible-columns option can be turned off', (tester) async {
    PreferencesService.logExportFormat = LogExportFormat.plainText.name;
    final result = await open(tester, hiddenColumnLabels: ['Tag']);

    await tester.tap(find.text('Only the columns shown in the viewer'));
    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();
    expect((await result)?.visibleColumnsOnly, isFalse);
  });

  testWidgets('no hidden columns, no visible-columns option', (tester) async {
    PreferencesService.logExportFormat = LogExportFormat.plainText.name;
    await open(tester);

    expect(find.text('Only the columns shown in the viewer'), findsNothing);
  });
}
