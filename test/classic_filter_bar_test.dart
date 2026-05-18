import 'package:eagly/data/log_level.dart';
import 'package:eagly/theme/app_theme.dart';
import 'package:eagly/theme/log_level_presentation.dart';
import 'package:eagly/ui/log_tab_view/components/classic_filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpClassicFilterBar(
    WidgetTester tester, {
    required TextEditingController packageController,
    required FocusNode packageFocusNode,
    required ValueChanged<String> onPackageFilterSelected,
    List<String> recentPackageFilters = const ['com.example.auth'],
    List<String> knownPackageFilters = const [
      'com.example.auth',
      'io.sample.payments',
      'org.demo.camera.app',
    ],
  }) async {
    final messageController = TextEditingController();
    final messageFocusNode = FocusNode();
    final pidTidController = TextEditingController();
    final pidTidFocusNode = FocusNode();
    final tagController = TextEditingController();
    final tagFocusNode = FocusNode();

    addTearDown(messageController.dispose);
    addTearDown(messageFocusNode.dispose);
    addTearDown(pidTidController.dispose);
    addTearDown(pidTidFocusNode.dispose);
    addTearDown(tagController.dispose);
    addTearDown(tagFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: ClassicFilterBar(
              messageController: messageController,
              messageFocusNode: messageFocusNode,
              onMessageFilterChanged: (_) {},
              onMessageFilterSelected: (_) {},
              recentMessageFilters: const ['signed in'],
              packageController: packageController,
              packageFocusNode: packageFocusNode,
              onPackageFilterChanged: (_) {},
              onPackageFilterSelected: onPackageFilterSelected,
              recentPackageFilters: recentPackageFilters,
              knownPackageFilters: knownPackageFilters,
              pidTidController: pidTidController,
              pidTidFocusNode: pidTidFocusNode,
              onPidTidFilterChanged: (_) {},
              onPidTidFilterSelected: (_) {},
              recentPidTidFilters: const ['123/456'],
              tagController: tagController,
              tagFocusNode: tagFocusNode,
              onTagFilterChanged: (_) {},
              onTagFilterSelected: (_) {},
              recentTagFilters: const ['AuthService'],
              onSubmitFilters: () {},
              selectedLogLevel: LogLevel.verbose,
              onLogLevelChanged: (_) {},
              isIos: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('classic package field suggests known package values', (
    WidgetTester tester,
  ) async {
    final packageController = TextEditingController();
    final packageFocusNode = FocusNode();
    addTearDown(packageController.dispose);
    addTearDown(packageFocusNode.dispose);

    await pumpClassicFilterBar(
      tester,
      packageController: packageController,
      packageFocusNode: packageFocusNode,
      onPackageFilterSelected: (_) {},
    );

    await tester.enterText(find.byType(TextField).first, 'payments');
    await tester.pumpAndSettle();

    expect(find.text('io.sample.payments'), findsWidgets);
    expect(find.text('com.example.auth'), findsNothing);
  });

  testWidgets('classic package field applies a clicked known package value', (
    WidgetTester tester,
  ) async {
    final packageController = TextEditingController();
    final packageFocusNode = FocusNode();
    String? selectedValue;
    addTearDown(packageController.dispose);
    addTearDown(packageFocusNode.dispose);

    await pumpClassicFilterBar(
      tester,
      packageController: packageController,
      packageFocusNode: packageFocusNode,
      onPackageFilterSelected: (value) => selectedValue = value,
    );

    await tester.enterText(find.byType(TextField).first, 'payments');
    await tester.pumpAndSettle();

    await tester.tap(find.text('io.sample.payments').first);
    await tester.pumpAndSettle();

    expect(packageController.text, 'io.sample.payments');
    expect(selectedValue, 'io.sample.payments');
  });

  testWidgets('classic level dropdown renders colored level labels', (
    WidgetTester tester,
  ) async {
    final packageController = TextEditingController();
    final packageFocusNode = FocusNode();
    addTearDown(packageController.dispose);
    addTearDown(packageFocusNode.dispose);

    await pumpClassicFilterBar(
      tester,
      packageController: packageController,
      packageFocusNode: packageFocusNode,
      onPackageFilterSelected: (_) {},
    );

    expect(find.byType(LogLevelLabel), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<LogLevel>));
    await tester.pumpAndSettle();

    expect(find.byType(LogLevelLabel), findsWidgets);
    expect(find.text('Fatal (F)'), findsWidgets);
  });
}
