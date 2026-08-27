import 'package:eagly/presentation/components/overflow_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tapped = <String>[];

  List<ToolbarAction> buildActions() => [
    for (final label in ['One', 'Two', 'Three', 'Four', 'Five'])
      ToolbarAction(
        icon: Icons.star,
        label: label,
        onPressed: () => tapped.add(label),
      ),
  ];

  Widget wrap({required double width, Widget? flexible, double flexMin = 0}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 48,
            child: OverflowToolbar(
              leading: const [Icon(Icons.arrow_back)],
              flexible: flexible,
              flexibleMinWidth: flexMin,
              trailing: const [Icon(Icons.close)],
              actions: buildActions(),
            ),
          ),
        ),
      ),
    );
  }

  setUp(tapped.clear);

  testWidgets('shows every action and no overflow button when they fit', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(width: 800));

    expect(find.byIcon(Icons.star).hitTestable(), findsNWidgets(5));
    expect(find.byIcon(Icons.more_horiz).hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapses the trailing actions into the overflow menu', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(width: 260));

    final visible = tester.widgetList(find.byIcon(Icons.star).hitTestable());
    expect(visible.length, lessThan(5));
    expect(find.byIcon(Icons.more_horiz).hitTestable(), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz).hitTestable());
    await tester.pumpAndSettle();

    // The hidden ones are in the menu, the visible ones are not.
    expect(find.text('Five'), findsOneWidget);
    expect(find.text('One'), findsNothing);

    await tester.tap(find.text('Five'));
    await tester.pumpAndSettle();
    expect(tapped, ['Five']);
  });

  testWidgets('collapses actions before shrinking the flexible child', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        width: 300,
        flexible: const TextField(key: Key('search')),
        flexMin: 160,
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('search'))).width,
      greaterThanOrEqualTo(160),
    );
    expect(find.byIcon(Icons.star).hitTestable(), findsNothing);
    expect(find.byIcon(Icons.more_horiz).hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back).hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.close).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the flexible child absorbs the leftover width', (tester) async {
    await tester.pumpWidget(
      wrap(
        width: 900,
        flexible: const TextField(key: Key('search')),
        flexMin: 160,
      ),
    );

    expect(find.byIcon(Icons.star).hitTestable(), findsNWidgets(5));
    expect(
      tester.getSize(find.byKey(const Key('search'))).width,
      greaterThan(160),
    );
  });

  testWidgets('never shows an empty overflow menu', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 60,
            height: 48,
            child: OverflowToolbar(
              actions: const [],
              flexible: const Text('A very long pane title indeed'),
              flexibleMinWidth: 56,
              trailing: [
                IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.more_horiz).hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden actions are not hit-testable', (tester) async {
    await tester.pumpWidget(wrap(width: 260));

    // The last action is collapsed: its button is still in the tree but must
    // not receive taps.
    await tester.tap(find.byIcon(Icons.star).last, warnIfMissed: false);
    await tester.pump();
    expect(tapped, isEmpty);
  });
}
