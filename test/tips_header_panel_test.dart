import 'package:eagly/features/tips/tip.dart';
import 'package:eagly/features/tips/tips_controller.dart';
import 'package:eagly/features/tips/tips_header_panel.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tips = [
  Tip(
    id: 'a',
    icon: Icons.view_column_outlined,
    title: 'Hide columns you don\'t use',
    detail: 'Right-click any column header to hide or show columns.',
    actionHint: 'Right-click a column header',
  ),
];

Widget _host(TipsController controller) {
  // The header only reserves room for tips on a reasonably wide window, so the
  // pump surface must exceed the panel's minimum-width threshold.
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: Row(children: [TipsHeaderPanel(controller: controller)]),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  useWideWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('renders the current tip title inline', (tester) async {
    useWideWindow(tester);
    final controller = TipsController(tips: _tips);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));

    expect(find.text('Hide columns you don\'t use'), findsOneWidget);
  });

  testWidgets('hides on a narrow window', (tester) async {
    tester.view.physicalSize = const Size(700, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = TipsController(tips: _tips);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));

    expect(find.text('Hide columns you don\'t use'), findsNothing);
  });

  testWidgets('close button hides it for the session', (tester) async {
    useWideWindow(tester);
    final controller = TipsController(tips: _tips);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));
    await tester.tap(find.byTooltip('Hide tip'));
    await tester.pumpAndSettle();

    expect(find.text('Hide columns you don\'t use'), findsNothing);
    expect(controller.visible, isFalse);
  });

  testWidgets('tapping the body opens the detail dialog', (tester) async {
    useWideWindow(tester);
    final controller = TipsController(tips: _tips);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));
    await tester.tap(find.text('Hide columns you don\'t use'));
    await tester.pumpAndSettle();

    expect(
      find.text('Right-click any column header to hide or show columns.'),
      findsOneWidget,
    );
    expect(find.text('Right-click a column header'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('three-dot menu can turn tips off behind a confirmation', (
    tester,
  ) async {
    useWideWindow(tester);
    final controller = TipsController(tips: _tips);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));

    // Open the ⋮ menu.
    await tester.tap(find.byTooltip('Tip options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off tips…'));
    await tester.pumpAndSettle();

    // The confirmation guard appears; nothing has changed yet.
    expect(find.text('Turn off tips?'), findsOneWidget);
    expect(controller.enabled, isTrue);

    // Confirm.
    await tester.tap(find.widgetWithText(FilledButton, 'Turn off'));
    await tester.pumpAndSettle();

    expect(controller.enabled, isFalse);
    expect(find.text('Hide columns you don\'t use'), findsNothing);
    expect(PreferencesService.tipsEnabled, isFalse);
  });

  testWidgets('cancelling the confirmation keeps tips on', (tester) async {
    useWideWindow(tester);
    final controller = TipsController(tips: _tips);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));

    await tester.tap(find.byTooltip('Tip options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off tips…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(controller.enabled, isTrue);
    expect(find.text('Hide columns you don\'t use'), findsOneWidget);
  });
}
