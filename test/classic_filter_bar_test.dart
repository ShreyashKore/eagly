import 'package:eagly/features/logs/data/models/log_filters.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/presentation/theme/log_level_presentation.dart';
import 'package:eagly/features/logs/presentation/components/classic_filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  ClassicFilterController buildController({
    List<String> recentPackageFilters = const ['com.example.auth'],
    List<String> knownPackageFilters = const [
      'com.example.auth',
      'io.sample.payments',
      'org.demo.camera.app',
    ],
    ValueChanged<LogFilters>? onStateChanged,
  }) {
    return ClassicFilterController(
      initialState: LogFilters.empty(LogLevel.verbose),
      isIos: false,
      onStateChanged: onStateChanged ?? (_) {},
      suggestions: LogFilterSuggestions(
        recentMessageFilters: () => const ['signed in'],
        recentPackageFilters: () => recentPackageFilters,
        knownPackageFilters: () => knownPackageFilters,
        recentPidTidFilters: () => const ['123/456'],
        recentTagFilters: () => const ['AuthService'],
      ),
    );
  }

  Future<void> pumpClassicFilterBar(
    WidgetTester tester, {
    required ClassicFilterController controller,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: ClassicFilterBar(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder editorField() => find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText != 'Filter message text…',
  );

  Future<void> addFilter(WidgetTester tester, String field) async {
    await tester.tap(find.widgetWithText(TextButton, 'Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(field).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a package pill suggests known values and applies a clicked one',
    (WidgetTester tester) async {
      LogFilters? emitted;
      final controller = buildController(
        onStateChanged: (state) => emitted = state,
      );
      addTearDown(controller.dispose);

      await pumpClassicFilterBar(tester, controller: controller);
      await addFilter(tester, 'Package');

      await tester.enterText(editorField(), 'payments');
      await tester.pumpAndSettle();

      expect(find.text('io.sample.payments'), findsOneWidget);
      expect(find.text('com.example.auth'), findsNothing);

      await tester.tap(find.text('io.sample.payments'));
      await tester.pumpAndSettle();

      expect(editorField(), findsNothing, reason: 'picking a value closes it');
      expect(
        find.text('Package contains io.sample.payments', findRichText: true),
        findsOneWidget,
      );
      final term = emitted!.packageTerms.single;
      expect(term.value, 'io.sample.payments');
      expect(term.mode, FilterMatchMode.contains);
      expect(term.negate, isFalse);
    },
  );

  testWidgets('a pill can be switched to regex and negated', (
    WidgetTester tester,
  ) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpClassicFilterBar(tester, controller: controller);
    await addFilter(tester, 'Tag');

    await tester.enterText(editorField(), '^Chat');
    await tester.pump();
    await tester.tap(find.text('Regex'));
    await tester.pump();
    await tester.tap(find.text('Hide matches'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.text('Tag does not match regex ^Chat', findRichText: true),
      findsOneWidget,
    );
    final term = emitted!.tagTerms.single;
    expect(term.value, '^Chat');
    expect(term.mode, FilterMatchMode.regex);
    expect(term.negate, isTrue);
    expect(
      LogFilters.compose(
        emitted!,
        defaultLevel: LogLevel.verbose,
        isIos: false,
      ),
      '-tag~:^Chat',
    );
  });

  testWidgets('closing a pill that never got a value drops it', (
    WidgetTester tester,
  ) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpClassicFilterBar(tester, controller: controller);
    await addFilter(tester, 'Message');
    expect(controller.conditions, hasLength(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(controller.conditions, isEmpty);
    expect(emitted, isNull);
  });

  testWidgets('changing the level keeps an open draft pill', (
    WidgetTester tester,
  ) async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await pumpClassicFilterBar(tester, controller: controller);
    await addFilter(tester, 'Package');

    controller.setLevel(LogLevel.error);
    await tester.pumpAndSettle();

    expect(editorField(), findsOneWidget);
    expect(controller.conditions.single.isDraft, isTrue);
  });

  testWidgets('an age preset applies at once', (WidgetTester tester) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpClassicFilterBar(tester, controller: controller);
    await addFilter(tester, 'Age');
    await tester.tap(find.text('15m'));
    await tester.pumpAndSettle();

    expect(emitted?.maxAge, const Duration(minutes: 15));
    expect(
      find.text('Age within last 15m', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('inline state splits into the quick field and pills', (
    WidgetTester tester,
  ) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpClassicFilterBar(tester, controller: controller);

    const inline =
        'age:5m package=:com.x pid:12 -tag~:^Chat message:hello '
        '-message:noise bare';
    controller.updateState(
      LogFilters.parse(
        inline,
        fallbackLevel: LogLevel.verbose,
        isIosLogContext: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.messageController.text, 'hello');
    for (final pill in [
      'Age within last 5m',
      'Package is com.x',
      'PID / TID contains 12',
      'Tag does not match regex ^Chat',
      'Message does not contain noise',
      'Any field contains bare',
    ]) {
      expect(find.text(pill, findRichText: true), findsOneWidget, reason: pill);
    }

    // Rebuilding the filter from the pills loses nothing.
    controller.applyNow();
    controller.removeCondition(controller.conditions.last.id);
    expect(
      LogFilters.compose(
        emitted!,
        defaultLevel: LogLevel.verbose,
        isIos: false,
      ),
      'age:5m package=:com.x pid:12 -tag~:^Chat message:hello -message:noise',
    );
  });

  testWidgets('classic level dropdown renders colored level labels', (
    WidgetTester tester,
  ) async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await pumpClassicFilterBar(tester, controller: controller);

    expect(find.byType(LogLevelLabel), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<LogLevel>));
    await tester.pumpAndSettle();

    expect(find.byType(LogLevelLabel), findsWidgets);
    expect(find.text('Fatal (F)'), findsWidgets);
  });
}
