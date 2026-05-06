import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logview/theme/app_theme.dart';
import 'package:logview/ui/log_tab_view/components/inline_filter_bar.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpInlineFilterBar(
    WidgetTester tester, {
    required InlineFilterTextController controller,
    required FocusNode focusNode,
  }) async {
    void onSuggestionApplied(
      String text, {
      TextSelection selection = const TextSelection.collapsed(offset: -1),
      bool applyImmediately = false,
    }) {
      controller.value = TextEditingValue(text: text, selection: selection);
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 700,
            child: InlineFilterBar(
              controller: controller,
              focusNode: focusNode,
              onChanged: (_) {},
              onSubmitted: () {},
              onSuggestionApplied: onSuggestionApplied,
              recentMessageFilters: const ['signed in'],
              recentPackageFilters: const ['com.example.auth'],
              recentPidTidFilters: const ['101/202'],
              recentTagFilters: const ['AuthService'],
              isIos: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('suggests filter keys and inserts a colon automatically', (
    WidgetTester tester,
  ) async {
    final controller = InlineFilterTextController(text: 'lev');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await pumpInlineFilterBar(
      tester,
      controller: controller,
      focusNode: focusNode,
    );

    focusNode.requestFocus();
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pumpAndSettle();

    expect(find.text('level:'), findsOneWidget);

    await tester.tap(find.text('level:'));
    await tester.pumpAndSettle();

    expect(controller.text, 'level:');
    expect(controller.selection.baseOffset, controller.text.length);
  });

  testWidgets('clicking a key suggestion appends to existing filters', (
    WidgetTester tester,
  ) async {
    final controller = InlineFilterTextController(
      text: 'package:com.example.auth lev',
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await pumpInlineFilterBar(
      tester,
      controller: controller,
      focusNode: focusNode,
    );

    focusNode.requestFocus();
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    await tester.pumpAndSettle();

    expect(find.text('level:'), findsOneWidget);

    await tester.tap(find.text('level:'));
    await tester.pumpAndSettle();

    expect(controller.text, 'package:com.example.auth level:');
    expect(controller.selection.baseOffset, controller.text.length);
  });

  testWidgets('suggests concrete level values after typing level colon', (
    WidgetTester tester,
  ) async {
    final controller = InlineFilterTextController(text: 'level:');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await pumpInlineFilterBar(
      tester,
      controller: controller,
      focusNode: focusNode,
    );

    focusNode.requestFocus();
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    await tester.pumpAndSettle();

    expect(find.text('level:error'), findsOneWidget);

    await tester.tap(find.text('level:error'));
    await tester.pumpAndSettle();

    expect(controller.text, 'level:error ');
  });

  testWidgets('clicking a value suggestion preserves earlier filters', (
    WidgetTester tester,
  ) async {
    final controller = InlineFilterTextController(
      text: 'package:com.example.auth level:',
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await pumpInlineFilterBar(
      tester,
      controller: controller,
      focusNode: focusNode,
    );

    focusNode.requestFocus();
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    await tester.pumpAndSettle();

    expect(find.text('level:error'), findsOneWidget);

    await tester.tap(find.text('level:error'));
    await tester.pumpAndSettle();

    expect(controller.text, 'package:com.example.auth level:error ');
    expect(controller.selection.baseOffset, controller.text.length);
  });

  testWidgets('help content stays collapsed until the help icon is pressed', (
    WidgetTester tester,
  ) async {
    final controller = InlineFilterTextController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await pumpInlineFilterBar(
      tester,
      controller: controller,
      focusNode: focusNode,
    );

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
      final controller = InlineFilterTextController(
        text: 'package:com.example.auth raw',
      );
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await pumpInlineFilterBar(
        tester,
        controller: controller,
        focusNode: focusNode,
      );

      final span = controller.buildTextSpan(
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
