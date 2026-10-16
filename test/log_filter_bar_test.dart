import 'package:eagly/features/logs/data/models/log_filters.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/presentation/components/package_icon.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/presentation/theme/log_level_presentation.dart';
import 'package:eagly/features/logs/presentation/components/log_filter_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  LogFilterController buildController({
    List<String> recentPackageFilters = const ['com.example.auth'],
    List<String> knownPackageFilters = const [
      'com.example.auth',
      'io.sample.payments',
      'org.demo.camera.app',
    ],
    ValueChanged<LogFilters>? onStateChanged,
    bool isIos = false,
  }) {
    return LogFilterController(
      initialState: LogFilters.empty(LogLevel.verbose),
      isIos: isIos,
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

  Future<void> pumpFilterBar(
    WidgetTester tester, {
    required LogFilterController controller,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [LogFilterBar(controller: controller)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder fieldWithHint(String hint) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == hint,
  );
  final editorField = fieldWithHint('Type a value…');

  /// A menu row, or a filter chip by the sentence it reads as ("Tag does not
  /// contain Chatty") — chips show it split over a label and a value line.
  Finder pill(String text) => find.byWidgetPredicate(
    (widget) =>
        (widget is RichText && widget.text.toPlainText() == text) ||
        (widget is Semantics && widget.properties.label == text),
  );

  /// The bar's type-to-filter field.
  final filterField = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.groupId != EditableText,
  );

  Future<void> openFilterMenu(WidgetTester tester) async {
    await tester.tap(filterField);
    await tester.pumpAndSettle();
  }

  Future<void> addField(WidgetTester tester, String field) async {
    await openFilterMenu(tester);
    await tester.tap(find.text(field));
    await tester.pumpAndSettle();
  }

  // The control draws the border; the field inside must not add the theme's
  // enabled / focused border or fill as a second box.
  void expectBareDecoration(WidgetTester tester, Finder field) {
    final decoration = tester
        .widget<InputDecorator>(
          find.descendant(of: field, matching: find.byType(InputDecorator)),
        )
        .decoration;
    expect(decoration.filled, isFalse);
    expect(decoration.border, InputBorder.none);
    expect(decoration.enabledBorder, InputBorder.none);
    expect(decoration.focusedBorder, InputBorder.none);
  }

  String composed(LogFilters filters) =>
      LogFilters.compose(filters, defaultLevel: LogLevel.verbose, isIos: false);

  testWidgets('typing in the Filter menu offers known values as filters', (
    WidgetTester tester,
  ) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    await openFilterMenu(tester);
    await tester.enterText(filterField, 'payments');
    await tester.pumpAndSettle();

    expect(pill('Message contains payments'), findsOneWidget);
    final suggestion = pill('Package contains io.sample.payments');
    expect(suggestion, findsOneWidget);
    expect(pill('Package contains com.example.auth'), findsNothing);

    await tester.tap(suggestion);
    await tester.pumpAndSettle();

    expect(
      pill('Message contains payments'),
      findsNothing,
      reason: 'picking closes the menu',
    );
    expect(pill('Package contains io.sample.payments'), findsOneWidget);
    final term = emitted!.packageTerms.single;
    expect(term.value, 'io.sample.payments');
    expect(term.mode, FilterMatchMode.contains);
    expect(term.negate, isFalse);
  });

  testWidgets('package suggestions lead with an app icon on Android only', (
    WidgetTester tester,
  ) async {
    for (final isIos in [false, true]) {
      final controller = buildController(isIos: isIos);
      final reason = isIos ? 'iOS' : 'Android';

      await pumpFilterBar(tester, controller: controller);
      await openFilterMenu(tester);
      await tester.enterText(filterField, 'package:');
      await tester.pumpAndSettle();
      expect(pill('Package contains io.sample.payments'), findsOneWidget);
      expect(
        find.byType(PackageIcon),
        isIos ? findsNothing : findsNWidgets(3),
        reason: reason,
      );

      // Plain text: only the package rows among the suggestions get one.
      await tester.enterText(filterField, 'auth');
      await tester.pumpAndSettle();
      expect(
        pill('${isIos ? 'Category' : 'Tag'} contains AuthService'),
        findsOneWidget,
      );
      expect(
        find.byType(PackageIcon),
        isIos ? findsNothing : findsOneWidget,
        reason: reason,
      );

      // A package pill's editor lists the same values.
      await tester.enterText(filterField, '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Package'));
      await tester.pumpAndSettle();
      expect(editorField, findsOneWidget);
      expect(find.text('org.demo.camera.app'), findsOneWidget);
      expect(
        find.byType(PackageIcon),
        isIos ? findsNothing : findsNWidgets(3),
        reason: reason,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  testWidgets('Enter in the Filter menu adds the highlighted filter', (
    WidgetTester tester,
  ) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    await openFilterMenu(tester);
    await tester.enterText(filterField, 'timeout');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Message is first, so one ↓ lands on Package.
    expect(pill('Package contains timeout'), findsOneWidget);
    expect(emitted!.packageTerms.single.value, 'timeout');
  });

  testWidgets('the focused filter field draws no inner border', (
    WidgetTester tester,
  ) async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    await openFilterMenu(tester);

    expect(controller.inputFocusNode.hasFocus, isTrue);
    expectBareDecoration(tester, filterField);
  });

  testWidgets('typed key:value tokens become pills without the menu', (
    WidgetTester tester,
  ) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    await openFilterMenu(tester);

    // A space after a complete token commits it and clears the field.
    await tester.enterText(filterField, 'tag:Auth ');
    await tester.pumpAndSettle();
    expect(pill('Tag contains Auth'), findsOneWidget);
    expect(tester.widget<TextField>(filterField).controller!.text, isEmpty);

    // ↵ commits the highlighted row: exactly the typed filter.
    await tester.enterText(filterField, '-message~:^noise');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(pill('Message does not match regex ^noise'), findsOneWidget);

    await tester.enterText(filterField, 'level:e');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(composed(emitted!), 'level:error tag:Auth -message~:^noise');
    expect(controller.inputFocusNode.hasFocus, isTrue, reason: 'keep typing');
  });

  testWidgets('a chip floats its field and operator over the value', (
    WidgetTester tester,
  ) async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    controller.applyTyped('-tag:Chatty');
    await tester.pumpAndSettle();

    final label = find.text('Tag · excludes', findRichText: true);
    final value = find.text('Chatty');
    expect(label, findsOneWidget);
    expect(value, findsOneWidget);
    expect(
      tester.getBottomLeft(label).dy,
      lessThanOrEqualTo(tester.getTopLeft(value).dy),
      reason: 'the label line sits above the value',
    );
    expect(pill('Tag does not contain Chatty'), findsOneWidget);
  });

  testWidgets('pasted filter text applies as one row', (
    WidgetTester tester,
  ) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    await openFilterMenu(tester);
    await tester.enterText(filterField, 'package=:com.x -tag:Chatty crash');
    await tester.pumpAndSettle();

    await tester.tap(pill('Add 3 filters  package=:com.x -tag:Chatty crash'));
    await tester.pumpAndSettle();

    expect(pill('Package is com.x'), findsOneWidget);
    expect(pill('Tag does not contain Chatty'), findsOneWidget);
    expect(pill('Any field contains crash'), findsOneWidget);
    expect(composed(emitted!), 'package=:com.x -tag:Chatty crash');
  });

  testWidgets('typing part of a key offers to complete it', (
    WidgetTester tester,
  ) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    await openFilterMenu(tester);
    await tester.enterText(filterField, 'ta');
    await tester.pumpAndSettle();

    await tester.tap(pill('tag:  filter by Tag'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(filterField).controller!.text, 'tag:');

    // With the key typed, the field's known values are offered.
    await tester.tap(pill('Tag contains AuthService'));
    await tester.pumpAndSettle();
    expect(composed(emitted!), 'tag:AuthService');
  });

  testWidgets('↓ and ↑ move from a pill editor into its suggestions', (
    WidgetTester tester,
  ) async {
    final controller = buildController(
      knownPackageFilters: const [
        'com.example.auth',
        'com.example.billing',
        'io.sample.payments',
      ],
    );
    addTearDown(controller.dispose);
    final highlight = find.byIcon(Icons.keyboard_return);

    await pumpFilterBar(tester, controller: controller);
    await addField(tester, 'Package');
    await tester.enterText(editorField, 'example');
    await tester.pump();
    expect(highlight, findsNothing, reason: '↵ still takes the typed value');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(highlight, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      tester.widget<TextField>(editorField).focusNode!.hasFocus,
      isTrue,
      reason: 'the caret stays in the field',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(editorField, findsNothing, reason: 'picking closes the editor');
    expect(controller.conditions.single.value, 'com.example.billing');

    // ↑ wraps to the last suggestion, and Esc returns to the typed value
    // without closing the editor.
    await addField(tester, 'Package');
    await tester.enterText(editorField, 'example');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(editorField, findsOneWidget);
    expect(highlight, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.conditions.map((c) => c.value), [
      'com.example.billing',
      'com.example.auth',
    ]);

    // Tab still moves the focus, and takes the highlight with it.
    await addField(tester, 'Package');
    await tester.enterText(editorField, 'example');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tester.widget<TextField>(editorField).focusNode!.hasFocus, isFalse);
    expect(highlight, findsNothing);
    await tester.pump(controller.debounce); // Let the typed value apply.
  });

  testWidgets('Backspace in the empty field marks, then removes, a pill', (
    WidgetTester tester,
  ) async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    controller.applyTyped('tag:Auth pid:12');
    await openFilterMenu(tester);
    expect(controller.conditions, hasLength(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(controller.conditions, hasLength(2), reason: 'first press marks');

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(pill('PID / TID contains 12'), findsNothing);
    expect(pill('Tag contains Auth'), findsOneWidget);
  });

  testWidgets('a pill can be switched to a negated regex', (
    WidgetTester tester,
  ) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    await addField(tester, 'Tag');

    expect(editorField, findsOneWidget, reason: 'a new pill opens its editor');
    await tester.enterText(editorField, '^Chat');
    await tester.pump();
    await tester.tap(find.text('contains'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('does not match regex'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(pill('Tag does not match regex ^Chat'), findsOneWidget);
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

    await pumpFilterBar(tester, controller: controller);
    await addField(tester, 'Message');
    expect(controller.conditions, hasLength(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(controller.conditions, isEmpty);
    expect(emitted, isNull);
  });

  // Tooltips lay out through OverlayPortal.overlayChildLayoutBuilder, which
  // asserts under a CompositedTransformFollower — the red error box that
  // flashed when the pointer crossed "Delete filter" while typing.
  testWidgets('tooltips inside an open pill editor show without errors', (
    WidgetTester tester,
  ) async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    await addField(tester, 'Message');
    await tester.enterText(editorField, 'auth');
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byTooltip('Delete filter')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Delete filter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // The right-click menu sits in the root overlay; choosing Paste in it used
  // to count as a click outside the pill editor and close it.
  testWidgets('pasting from the right-click menu keeps the pill editor open', (
    WidgetTester tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.getData' => {'text': 'AuthService'},
        'Clipboard.hasStrings' => {'value': true},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = buildController();
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    await addField(tester, 'Message');
    await tester.tap(editorField, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();

    expect(editorField, findsOneWidget);
    expect(
      tester.widget<TextField>(editorField).controller!.text,
      'AuthService',
    );
    await tester.pump(const Duration(seconds: 1)); // Let the value debounce.
  });

  testWidgets('changing the level keeps an open draft pill', (
    WidgetTester tester,
  ) async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    await addField(tester, 'Package');

    controller.setLevel(LogLevel.error);
    await tester.pumpAndSettle();

    expect(editorField, findsOneWidget);
    expect(controller.conditions.single.isDraft, isTrue);
  });

  testWidgets('an age preset applies at once', (WidgetTester tester) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    await addField(tester, 'Age');
    await tester.tap(find.text('15m'));
    await tester.pumpAndSettle();

    expect(emitted?.maxAge, const Duration(minutes: 15));
    expect(pill('Age within last 15m'), findsOneWidget);
  });

  testWidgets('the Level button picks the minimum level', (
    WidgetTester tester,
  ) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);
    await tester.tap(find.text('Level'));
    await tester.pumpAndSettle();

    expect(find.byType(LogLevelLabel), findsWidgets);
    await tester.tap(find.text('Error (E)'));
    await tester.pumpAndSettle();

    expect(emitted?.level, LogLevel.error);
    expect(find.text('Error (E)'), findsNothing, reason: 'menu closed');
  });

  testWidgets('inline state splits into one pill per term', (
    WidgetTester tester,
  ) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpFilterBar(tester, controller: controller);

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

    for (final text in [
      'Age within last 5m',
      'Package is com.x',
      'PID / TID contains 12',
      'Tag does not match regex ^Chat',
      'Message contains hello',
      'Message does not contain noise',
      'Any field contains bare',
    ]) {
      expect(pill(text), findsOneWidget, reason: text);
    }

    // Rebuilding the filter from the pills loses nothing.
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
}
