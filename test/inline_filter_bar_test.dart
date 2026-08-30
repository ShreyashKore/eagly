import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:eagly/features/logs/data/models/log_filters.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/presentation/theme/log_level_presentation.dart';
import 'package:eagly/features/logs/presentation/components/inline_filter_bar.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  InlineFilterController buildController({
    String initialText = '',
    bool isIos = false,
    List<String> knownPackageFilters = const [
      'com.example.auth',
      'com.example.billing',
    ],
    ValueChanged<LogFilters>? onStateChanged,
  }) {
    return InlineFilterController(
      initialState: LogFilters.empty(LogLevel.verbose),
      isIos: isIos,
      initialText: initialText,
      onStateChanged: onStateChanged ?? (_) {},
      suggestions: LogFilterSuggestions(
        recentMessageFilters: () => const ['signed in'],
        recentPackageFilters: () => const ['com.example.auth'],
        knownPackageFilters: () => knownPackageFilters,
        recentPidTidFilters: () => const ['101/202'],
        recentTagFilters: () => const ['AuthService'],
      ),
    );
  }

  Future<void> pumpInlineFilterBar(
    WidgetTester tester, {
    required InlineFilterController controller,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: InlineFilterBar(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('suggests filter keys and inserts a colon automatically', (
    WidgetTester tester,
  ) async {
    final controller = buildController(initialText: 'lev');
    addTearDown(controller.dispose);

    await pumpInlineFilterBar(tester, controller: controller);

    controller.focusNode.requestFocus();
    controller.textController.selection = const TextSelection.collapsed(
      offset: 3,
    );
    await tester.pumpAndSettle();

    expect(find.text('level:'), findsOneWidget);

    await tester.tap(find.text('level:'));
    await tester.pumpAndSettle();

    expect(controller.textController.text, 'level:');
    expect(
      controller.textController.selection.baseOffset,
      controller.textController.text.length,
    );
  });

  testWidgets('shows a dedicated inline level dropdown and notifies changes', (
    WidgetTester tester,
  ) async {
    LogLevel? emittedLevel;
    final controller = buildController(
      onStateChanged: (state) => emittedLevel = state.level,
    );
    addTearDown(controller.dispose);

    await pumpInlineFilterBar(tester, controller: controller);

    expect(find.text('Level'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<LogLevel>), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<LogLevel>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Error (E)').last);
    await tester.pumpAndSettle();

    expect(controller.selectedLevel, LogLevel.error);
    expect(emittedLevel, LogLevel.error);
  });

  testWidgets(
    'keyboard selection inserts a key suggestion and opens value suggestions',
    (WidgetTester tester) async {
      final controller = buildController(initialText: 'lev');
      addTearDown(controller.dispose);

      await pumpInlineFilterBar(tester, controller: controller);

      controller.focusNode.requestFocus();
      controller.textController.selection = const TextSelection.collapsed(
        offset: 3,
      );
      await tester.pumpAndSettle();

      expect(find.text('level:'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controller.textController.text, 'level:');
      expect(find.text('level:error'), findsWidgets);
    },
  );

  testWidgets('clicking a key suggestion appends to existing filters', (
    WidgetTester tester,
  ) async {
    final controller = buildController(
      initialText: 'package:com.example.auth lev',
    );
    addTearDown(controller.dispose);

    await pumpInlineFilterBar(tester, controller: controller);

    controller.focusNode.requestFocus();
    controller.textController.selection = TextSelection.collapsed(
      offset: controller.textController.text.length,
    );
    await tester.pumpAndSettle();

    expect(find.text('level:'), findsOneWidget);

    await tester.tap(find.text('level:'));
    await tester.pumpAndSettle();

    expect(controller.textController.text, 'package:com.example.auth level:');
    expect(
      controller.textController.selection.baseOffset,
      controller.textController.text.length,
    );
  });

  testWidgets('suggests concrete level values after typing level colon', (
    WidgetTester tester,
  ) async {
    final controller = buildController(initialText: 'level:');
    addTearDown(controller.dispose);

    await pumpInlineFilterBar(tester, controller: controller);

    controller.focusNode.requestFocus();
    controller.textController.selection = TextSelection.collapsed(
      offset: controller.textController.text.length,
    );
    await tester.pumpAndSettle();

    expect(find.text('level:error'), findsWidgets);

    await tester.tap(find.text('level:error').first);
    await tester.pumpAndSettle();

    expect(controller.textController.text, 'level:error ');
  });

  testWidgets('level suggestions use colored level labels', (
    WidgetTester tester,
  ) async {
    final controller = buildController(initialText: 'level:');
    addTearDown(controller.dispose);

    await pumpInlineFilterBar(tester, controller: controller);

    controller.focusNode.requestFocus();
    controller.textController.selection = TextSelection.collapsed(
      offset: controller.textController.text.length,
    );
    await tester.pumpAndSettle();

    expect(find.byType(LogLevelLabel), findsWidgets);
    expect(find.text('level:fault'), findsWidgets);
  });

  testWidgets('clicking a package key can apply a package value suggestion', (
    WidgetTester tester,
  ) async {
    final controller = buildController(
      initialText: 'pack',
      knownPackageFilters: const ['com.example.auth', 'io.sample.payments'],
    );
    addTearDown(controller.dispose);

    await pumpInlineFilterBar(tester, controller: controller);

    controller.focusNode.requestFocus();
    controller.textController.selection = const TextSelection.collapsed(
      offset: 4,
    );
    await tester.pumpAndSettle();

    expect(find.text('package:'), findsWidgets);

    await tester.tap(find.text('package:').first);
    await tester.pumpAndSettle();

    expect(controller.textController.text, 'package:');
    expect(find.text('package:com.example.auth'), findsWidgets);

    await tester.tap(find.text('package:com.example.auth').first);
    await tester.pumpAndSettle();

    expect(controller.textController.text, 'package:com.example.auth ');
  });

  testWidgets('keyboard can select a narrowed value suggestion', (
    WidgetTester tester,
  ) async {
    final controller = buildController(initialText: 'level:err');
    addTearDown(controller.dispose);

    await pumpInlineFilterBar(tester, controller: controller);

    controller.focusNode.requestFocus();
    controller.textController.selection = TextSelection.collapsed(
      offset: controller.textController.text.length,
    );
    await tester.pumpAndSettle();

    expect(find.text('level:error'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.textController.text, 'level:error ');
  });

  testWidgets('clicking a value suggestion preserves earlier filters', (
    WidgetTester tester,
  ) async {
    final controller = buildController(
      initialText: 'package:com.example.auth level:',
    );
    addTearDown(controller.dispose);

    await pumpInlineFilterBar(tester, controller: controller);

    controller.focusNode.requestFocus();
    controller.textController.selection = TextSelection.collapsed(
      offset: controller.textController.text.length,
    );
    await tester.pumpAndSettle();

    expect(find.text('level:error'), findsWidgets);

    await tester.tap(find.text('level:error').first);
    await tester.pumpAndSettle();

    expect(
      controller.textController.text,
      'package:com.example.auth level:error ',
    );
    expect(
      controller.textController.selection.baseOffset,
      controller.textController.text.length,
    );
  });

  testWidgets(
    'package value suggestions include known packages and narrow as user types',
    (WidgetTester tester) async {
      final controller = buildController(
        initialText: 'package:',
        knownPackageFilters: const ['com.example.auth', 'io.sample.payments'],
      );
      addTearDown(controller.dispose);

      await pumpInlineFilterBar(tester, controller: controller);

      controller.focusNode.requestFocus();
      controller.textController.selection = TextSelection.collapsed(
        offset: controller.textController.text.length,
      );
      await tester.pumpAndSettle();

      expect(find.text('package:com.example.auth'), findsWidgets);
      expect(find.text('package:io.sample.payments'), findsWidgets);

      await tester.enterText(find.byType(TextField), 'package:payments');
      await tester.pumpAndSettle();

      expect(find.text('package:io.sample.payments'), findsWidgets);
      expect(find.text('package:com.example.auth'), findsNothing);

      // Flush the debounce scheduled by typing so no timer outlives the test.
      await tester.pump(const Duration(milliseconds: 350));
    },
  );

  testWidgets(
    'keyboard navigation scrolls suggestions to keep the highlighted item visible',
    (WidgetTester tester) async {
      final controller = buildController(
        initialText: 'package:',
        knownPackageFilters: List<String>.generate(
          18,
          (index) => 'com.example.feature.$index',
        ),
      );
      addTearDown(controller.dispose);

      await pumpInlineFilterBar(tester, controller: controller);

      controller.focusNode.requestFocus();
      controller.textController.selection = TextSelection.collapsed(
        offset: controller.textController.text.length,
      );
      await tester.pumpAndSettle();

      final scrollableFinder = find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.controller != null,
      );
      expect(scrollableFinder, findsWidgets);

      final scrollableStateBefore = tester.state<ScrollableState>(
        scrollableFinder.last,
      );
      final initialOffset = scrollableStateBefore.position.pixels;

      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 160));
      }
      await tester.pumpAndSettle();

      final scrollableStateAfter = tester.state<ScrollableState>(
        scrollableFinder.last,
      );
      expect(scrollableStateAfter.position.pixels, greaterThan(initialOffset));
    },
  );

  testWidgets('help content stays collapsed until the help icon is pressed', (
    WidgetTester tester,
  ) async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await pumpInlineFilterBar(tester, controller: controller);

    expect(find.byTooltip('Show filter help'), findsOneWidget);

    await tester.tap(find.byTooltip('Show filter help'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Hide filter help'), findsOneWidget);
    expect(find.byKey(const ValueKey('inline-filter-help')), findsOneWidget);
    expect(
      find.textContaining('Bare words search the whole log entry'),
      findsOneWidget,
    );
  });

  testWidgets(
    'controller builds highlighted spans for known key:value tokens',
    (WidgetTester tester) async {
      final controller = buildController(
        initialText: 'package:com.example.auth raw',
      );
      addTearDown(controller.dispose);

      await pumpInlineFilterBar(tester, controller: controller);

      final span = controller.textController.buildTextSpan(
        context: tester.element(find.byType(InlineFilterBar)),
        style: const TextStyle(fontSize: 12),
        withComposing: false,
      );

      expect(span.children, isNotNull);
      final highlightedSpan = span.children!.whereType<TextSpan>().firstWhere(
        (child) => child.children != null && child.children!.isNotEmpty,
      );
      expect(highlightedSpan.children!.first.toPlainText(), 'package:');
      expect(highlightedSpan.children!.last.toPlainText(), 'com.example.auth');
    },
  );
}
