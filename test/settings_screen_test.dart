import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/features/mirror/services/capture_storage.dart';
import 'package:eagly/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  test('theme mode defaults to dark when no preference is stored', () {
    expect(PreferencesService.themeMode, ThemeMode.dark);
    expect(PreferencesService.themeModeListenable.value, ThemeMode.dark);
  });

  testWidgets('settings screen persists theme mode changes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: PreferencesService.themeMode,
        home: const SettingsScreen(),
      ),
    );

    expect(find.byType(ToggleButtons), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(ToggleButtons),
        matching: find.text('Auto'),
      ),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(PreferencesService.themeMode, ThemeMode.system);
    expect(PreferencesService.themeModeListenable.value, ThemeMode.system);
    expect(prefs.getString('themeMode'), ThemeMode.system.name);
  });

  testWidgets('settings screen shows a single default log level setting', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: PreferencesService.themeMode,
        home: const SettingsScreen(),
      ),
    );

    expect(find.text('Default log level'), findsOneWidget);
    expect(find.text('Default filter style'), findsOneWidget);
    expect(find.text('Classic'), findsWidgets);
    expect(find.text('Inline'), findsWidgets);
    expect(find.text('Default log level (Android)'), findsNothing);
    expect(find.text('Default log level (iOS)'), findsNothing);
  });

  testWidgets('settings screen exposes the capture folder and save mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const SettingsScreen(),
      ),
    );

    final list = find.byType(ListView);
    final askSwitch = find.widgetWithText(
      SwitchListTile,
      'Ask where to save each time',
    );
    await tester.dragUntilVisible(askSwitch, list, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(find.text('Screenshots & recordings'), findsOneWidget);
    expect(find.text(CaptureStorage.defaultDirectory()), findsOneWidget);
    expect(PreferencesService.captureAskEveryTime, isFalse);

    await tester.tap(askSwitch);
    await tester.pumpAndSettle();

    expect(PreferencesService.captureAskEveryTime, isTrue);
  });
}
