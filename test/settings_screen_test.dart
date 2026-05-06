import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logview/services/preferences_service.dart';
import 'package:logview/theme/app_theme.dart';
import 'package:logview/ui/settings/settings_screen.dart';
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
}
