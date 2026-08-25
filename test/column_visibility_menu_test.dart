import 'package:eagly/features/logs/data/models/log_column.dart';
import 'package:eagly/features/logs/presentation/components/column_visibility_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final columns = LogColumn.values.where((c) => !c.isExpandable).toList();

  /// Mounts the menu the way [LogViewer] does — as the single item of a popup.
  Future<List<Set<String>>> pumpMenu(
    WidgetTester tester, {
    Set<String> hidden = const <String>{},
  }) async {
    final changes = <Set<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMenu<void>(
                context: context,
                position: RelativeRect.fill,
                items: [
                  PopupMenuItem<void>(
                    padding: EdgeInsets.zero,
                    child: ColumnVisibilityMenu(
                      columns: columns,
                      hiddenColumns: hidden,
                      isIos: false,
                      onChanged: changes.add,
                    ),
                  ),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return changes;
  }

  bool checkboxFor(WidgetTester tester, LogColumn column) {
    final row = find.ancestor(
      of: find.text(column.labelFor()),
      matching: find.byType(Row),
    );
    return tester
        .widget<Checkbox>(
          find.descendant(of: row, matching: find.byType(Checkbox)),
        )
        .value!;
  }

  testWidgets('stays open and updates in place across several toggles', (
    tester,
  ) async {
    final changes = await pumpMenu(tester);
    expect(checkboxFor(tester, LogColumn.tag), isTrue);

    await tester.tap(find.text(LogColumn.tag.labelFor()));
    await tester.pumpAndSettle();

    // Menu still mounted, and the tapped row now reads as hidden.
    expect(find.byType(ColumnVisibilityMenu), findsOneWidget);
    expect(checkboxFor(tester, LogColumn.tag), isFalse);
    expect(changes.single, {LogColumn.tag.name});

    await tester.tap(find.text(LogColumn.pid.labelFor()));
    await tester.pumpAndSettle();

    expect(find.byType(ColumnVisibilityMenu), findsOneWidget);
    expect(changes.last, {LogColumn.tag.name, LogColumn.pid.name});

    // Toggling back un-hides without closing.
    await tester.tap(find.text(LogColumn.tag.labelFor()));
    await tester.pumpAndSettle();

    expect(find.byType(ColumnVisibilityMenu), findsOneWidget);
    expect(checkboxFor(tester, LogColumn.tag), isTrue);
    expect(changes.last, {LogColumn.pid.name});
  });

  testWidgets('renders initially hidden columns unchecked', (tester) async {
    await pumpMenu(tester, hidden: {LogColumn.timestamp.name});
    expect(checkboxFor(tester, LogColumn.timestamp), isFalse);
    expect(checkboxFor(tester, LogColumn.level), isTrue);
  });
}
