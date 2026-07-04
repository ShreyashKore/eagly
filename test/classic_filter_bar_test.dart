import 'package:eagly/features/logs/data/models/log_filters.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/presentation/theme/log_level_presentation.dart';
import 'package:eagly/features/logs/presentation/components/classic_filter_bar.dart';
import 'package:flutter/material.dart';
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

  testWidgets('classic package field suggests known package values', (
    WidgetTester tester,
  ) async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await pumpClassicFilterBar(tester, controller: controller);

    await tester.enterText(find.byType(TextField).first, 'payments');
    await tester.pumpAndSettle();

    expect(find.text('io.sample.payments'), findsWidgets);
    expect(find.text('com.example.auth'), findsNothing);

    // Flush the debounce scheduled by typing so no timer outlives the test.
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('classic package field applies a clicked known package value', (
    WidgetTester tester,
  ) async {
    LogFilters? emitted;
    final controller = buildController(
      onStateChanged: (state) => emitted = state,
    );
    addTearDown(controller.dispose);

    await pumpClassicFilterBar(tester, controller: controller);

    await tester.enterText(find.byType(TextField).first, 'payments');
    await tester.pumpAndSettle();

    await tester.tap(find.text('io.sample.payments').first);
    await tester.pumpAndSettle();

    expect(controller.packageController.text, 'io.sample.payments');
    expect(emitted?.packageText, 'io.sample.payments');
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
