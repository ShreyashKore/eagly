import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/features/mirror/services/capture_storage.dart';
import 'package:eagly/features/emulator_manager/services/android_sdk_picker.dart';
import 'package:eagly/features/mcp/mcp_server_controller.dart';
import 'package:eagly/features/mcp/mcp_token_store.dart';
import 'package:eagly/features/settings/settings_screen.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/session/device_session_manager.dart';
import 'package:eagly/utils/android_sdk_path.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  late FakeAdbTool adbTool;
  late DevicesRepository repository;
  late DeviceSessionManager manager;
  late McpServerController mcpServer;
  final mcpTokenDir = Directory.systemTemp.createTempSync('settings-mcp');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
    adbTool = FakeAdbTool();
    repository = DevicesRepository.forTesting(
      adbTool: adbTool,
      iosDeviceService: FakeIosDeviceService(),
    );
    manager = DeviceSessionManager(
      repository: repository,
      serviceFactory: FakeSessionService.new,
    );
    mcpServer = McpServerController(
      manager: manager,
      // Never the real app support folder.
      tokenStore: McpTokenStore(directory: () async => mcpTokenDir),
    );
  });

  tearDown(() async {
    mcpServer.dispose();
    manager.dispose();
    repository.dispose();
    await adbTool.disposeTool();
  });

  tearDownAll(() {
    if (mcpTokenDir.existsSync()) mcpTokenDir.deleteSync(recursive: true);
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
        home: SettingsScreen(mcpServer: mcpServer),
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
        home: SettingsScreen(mcpServer: mcpServer),
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
        home: SettingsScreen(mcpServer: mcpServer),
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
    // A path is a value, so it is set in the monospace face.
    expect(
      tester
          .widget<Text>(find.text(CaptureStorage.defaultDirectory()))
          .style
          ?.fontFamily,
      contains('JetBrains'),
    );
    expect(PreferencesService.captureAskEveryTime, isFalse);

    await tester.tap(askSwitch);
    await tester.pumpAndSettle();

    expect(PreferencesService.captureAskEveryTime, isTrue);
  });

  testWidgets("a tappable row's ink spans its card edge to edge", (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: SettingsScreen(mcpServer: mcpServer),
      ),
    );

    final tile = find.widgetWithText(SwitchListTile, 'Feature tips');
    final ink = find.descendant(of: tile, matching: find.byType(InkWell));
    final card = find.ancestor(of: tile, matching: find.byType(Card));

    expect(tester.getSize(ink.first).width, tester.getSize(card).width);
  });

  testWidgets('the max log lines field is sized for a number', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: SettingsScreen(mcpServer: mcpServer),
      ),
    );

    final row = find.ancestor(
      of: find.text('Max log lines'),
      matching: find.byType(Row),
    );
    final field = find.descendant(of: row, matching: find.byType(TextField));
    expect(tester.getSize(field).width, 120);
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
          home: Scaffold(body: SettingsScreen(mcpServer: mcpServer)),
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

  testWidgets('the MCP server section starts off and offers the connect '
      'command', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SettingsScreen(mcpServer: mcpServer)),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Add to Claude Code'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('MCP server'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(
      find.text(
        'claude mcp add --transport http eagly http://127.0.0.1:9311/mcp',
      ),
      findsOneWidget,
    );
    expect(find.text('Token'), findsNothing);
  });
}
