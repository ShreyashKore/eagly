import 'package:eagly/command_palette/command_palette_dialog.dart';
import 'package:eagly/command_palette/command_palette_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPalette(
    WidgetTester tester, {
    required List<CommandPaletteItem> Function() itemsBuilder,
    Listenable? listenable,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showCommandPalette(
              context: context,
              itemsBuilder: itemsBuilder,
              listenable: listenable ?? ChangeNotifier(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists commands grouped by category', (tester) async {
    await pumpPalette(
      tester,
      itemsBuilder: () => [
        CommandPaletteItem(
          id: 'a',
          label: 'Reload Devices',
          category: 'App',
          icon: Icons.refresh,
          run: () {},
        ),
        CommandPaletteItem(
          id: 'b',
          label: 'Logs',
          category: 'Navigate',
          icon: Icons.article,
          run: () {},
        ),
      ],
    );

    expect(find.text('Reload Devices'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('APP'), findsOneWidget);
    expect(find.text('NAVIGATE'), findsOneWidget);
  });

  testWidgets('typing filters the list down to matching commands', (
    tester,
  ) async {
    await pumpPalette(
      tester,
      itemsBuilder: () => [
        CommandPaletteItem(
          id: 'a',
          label: 'Reload Devices',
          category: 'App',
          icon: Icons.refresh,
          run: () {},
        ),
        CommandPaletteItem(
          id: 'b',
          label: 'Clear Logs',
          category: 'Capture',
          icon: Icons.clear,
          run: () {},
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'clear');
    await tester.pumpAndSettle();

    expect(find.text('Clear Logs'), findsOneWidget);
    expect(find.text('Reload Devices'), findsNothing);
  });

  testWidgets('fuzzy-matches non-contiguous characters in order', (
    tester,
  ) async {
    await pumpPalette(
      tester,
      itemsBuilder: () => [
        CommandPaletteItem(
          id: 'a',
          label: 'Reload Devices',
          category: 'App',
          icon: Icons.refresh,
          run: () {},
        ),
        CommandPaletteItem(
          id: 'b',
          label: 'Clear Logs',
          category: 'Capture',
          icon: Icons.clear,
          run: () {},
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'rlddv');
    await tester.pumpAndSettle();

    expect(find.text('Reload Devices'), findsOneWidget);
    expect(find.text('Clear Logs'), findsNothing);
  });

  testWidgets('ranks a label match above a category-only match', (
    tester,
  ) async {
    await pumpPalette(
      tester,
      itemsBuilder: () => [
        // Only matches "app" via its category, not its label.
        CommandPaletteItem(
          id: 'a',
          label: 'Clear Logs',
          category: 'App',
          icon: Icons.clear,
          run: () {},
        ),
        // Matches "app" directly on its label — should outrank the above.
        CommandPaletteItem(
          id: 'b',
          label: 'Apps',
          category: 'Navigate',
          icon: Icons.apps,
          run: () {},
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'app');
    await tester.pumpAndSettle();

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(labels.indexOf('Apps'), lessThan(labels.indexOf('Clear Logs')));
  });

  testWidgets('shows a message when nothing matches', (tester) async {
    await pumpPalette(
      tester,
      itemsBuilder: () => [
        CommandPaletteItem(
          id: 'a',
          label: 'Reload Devices',
          category: 'App',
          icon: Icons.refresh,
          run: () {},
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'zzz-no-match');
    await tester.pumpAndSettle();

    expect(find.text('No matching commands.'), findsOneWidget);
  });

  testWidgets('clicking an item runs it and closes the palette', (
    tester,
  ) async {
    var ran = false;
    await pumpPalette(
      tester,
      itemsBuilder: () => [
        CommandPaletteItem(
          id: 'a',
          label: 'Reload Devices',
          category: 'App',
          icon: Icons.refresh,
          run: () => ran = true,
        ),
      ],
    );

    await tester.tap(find.text('Reload Devices'));
    await tester.pumpAndSettle();

    expect(ran, isTrue);
    expect(find.text('Reload Devices'), findsNothing);
  });

  testWidgets('arrow keys move the selection and enter runs it', (
    tester,
  ) async {
    String? runId;
    await pumpPalette(
      tester,
      itemsBuilder: () => [
        CommandPaletteItem(
          id: 'a',
          label: 'First Command',
          category: 'App',
          icon: Icons.looks_one,
          run: () => runId = 'a',
        ),
        CommandPaletteItem(
          id: 'b',
          label: 'Second Command',
          category: 'App',
          icon: Icons.looks_two,
          run: () => runId = 'b',
        ),
      ],
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(runId, 'b');
  });

  testWidgets('escape closes the palette without running anything', (
    tester,
  ) async {
    var ran = false;
    await pumpPalette(
      tester,
      itemsBuilder: () => [
        CommandPaletteItem(
          id: 'a',
          label: 'Reload Devices',
          category: 'App',
          icon: Icons.refresh,
          run: () => ran = true,
        ),
      ],
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(ran, isFalse);
    expect(find.text('Reload Devices'), findsNothing);
  });

  testWidgets('rebuilds items when the listenable notifies', (tester) async {
    final notifier = ChangeNotifier();
    var label = 'Start Capture';
    await pumpPalette(
      tester,
      listenable: notifier,
      itemsBuilder: () => [
        CommandPaletteItem(
          id: 'a',
          label: label,
          category: 'Capture',
          icon: Icons.play_arrow,
          run: () {},
        ),
      ],
    );

    expect(find.text('Start Capture'), findsOneWidget);

    label = 'Pause Capture';
    notifier.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('Pause Capture'), findsOneWidget);
    expect(find.text('Start Capture'), findsNothing);
  });
}
