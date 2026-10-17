import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/features/mirror/services/capture_storage.dart';
import 'package:eagly/features/emulator_manager/services/android_sdk_picker.dart';
import 'package:eagly/features/settings/settings_screen.dart';
import 'package:eagly/utils/android_sdk_path.dart';
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
    expect(find.text('Default filter style'), findsNothing);
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

  group('Android SDK', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('settings-sdk');
      // Blanked so the row reflects the fixture rather than whatever SDK the
      // machine running the suite happens to have.
      AndroidSdkPath.environment = const {};
    });

    tearDown(() {
      AndroidSdkPicker.resetChooseDirectory();
      AndroidSdkPath.resetEnvironment();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    String createSdk({bool withEmulator = true}) {
      final root = '${tempDir.path}/sdk';
      Directory('$root/platform-tools').createSync(recursive: true);
      if (withEmulator) {
        final emulator = Directory('$root/emulator')
          ..createSync(recursive: true);
        File(
          '${emulator.path}/'
          '${Platform.isWindows ? 'emulator.exe' : 'emulator'}',
        ).createSync();
      }
      return root;
    }

    /// Returns the SDK row, so the buttons can be found *inside* it — the
    /// screen has several other "Change…" and "Reset" buttons.
    Future<Finder> pumpToSdkSection(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          // A Scaffold, because these actions report through a SnackBar.
          home: const Scaffold(body: SettingsScreen()),
        ),
      );
      final row = find.widgetWithText(ListTile, 'SDK location');
      await tester.dragUntilVisible(
        row,
        find.byType(ListView),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      return row;
    }

    testWidgets('says so when no SDK can be found', (tester) async {
      final row = await pumpToSdkSection(tester);

      expect(find.text('Android SDK'), findsOneWidget);
      expect(find.textContaining('Not found'), findsOneWidget);
      // Nothing to reset when nothing was ever overridden.
      final reset = tester.widget<TextButton>(
        find.descendant(
          of: row,
          matching: find.widgetWithText(TextButton, 'Reset'),
        ),
      );
      expect(reset.onPressed, isNull);
    });

    testWidgets('choosing a folder saves it and reports it', (tester) async {
      final root = createSdk();
      AndroidSdkPicker.chooseDirectory = ({String? initialDirectory}) async =>
          root;

      final row = await pumpToSdkSection(tester);
      await tester.tap(
        find.descendant(
          of: row,
          matching: find.widgetWithText(TextButton, 'Change…'),
        ),
      );
      await tester.pumpAndSettle();

      expect(PreferencesService.androidSdkPath, root);
      expect(find.textContaining('Emulator ready'), findsOneWidget);
      expect(
        find.widgetWithText(SnackBar, 'Using the Android SDK at $root.'),
        findsOneWidget,
      );
    });

    testWidgets('an SDK without the emulator package is flagged, not hidden', (
      tester,
    ) async {
      final root = createSdk(withEmulator: false);
      AndroidSdkPicker.chooseDirectory = ({String? initialDirectory}) async =>
          root;

      final row = await pumpToSdkSection(tester);
      await tester.tap(
        find.descendant(
          of: row,
          matching: find.widgetWithText(TextButton, 'Change…'),
        ),
      );
      await tester.pumpAndSettle();

      expect(PreferencesService.androidSdkPath, root);
      expect(find.textContaining('No emulator package'), findsOneWidget);
    });

    testWidgets('Reset forgets the override', (tester) async {
      final root = createSdk();
      await PreferencesService.setAndroidSdkPath(root);

      final row = await pumpToSdkSection(tester);
      expect(find.textContaining('Emulator ready'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: row,
          matching: find.widgetWithText(TextButton, 'Reset'),
        ),
      );
      await tester.pumpAndSettle();

      expect(PreferencesService.androidSdkPath, isNull);
      expect(find.textContaining('Not found'), findsOneWidget);
    });
  });
}
