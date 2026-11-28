import 'package:eagly/features/home_screen/home_view.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdbTool adbTool;
  late FakeIosDeviceService iosDeviceService;
  late DevicesRepository repository;
  DeviceSessionManager? manager;
  var emulatorsOpened = 0;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() {
    adbTool = FakeAdbTool();
    iosDeviceService = FakeIosDeviceService();
    emulatorsOpened = 0;
    repository = DevicesRepository.forTesting(
      adbTool: adbTool,
      iosDeviceService: iosDeviceService,
    );
  });

  // The repository is disposed by closeHome inside each test body, so it is
  // deliberately not disposed again here.
  tearDown(() async {
    manager?.dispose();
    manager = null;
    await adbTool.disposeTool();
  });

  Future<void> pumpHome(WidgetTester tester, {required Size windowSize}) async {
    tester.view.physicalSize = windowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    manager = DeviceSessionManager(
      repository: repository,
      serviceFactory: (device) => FakeSessionService(device),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: HomeView(
            manager: manager!,
            onShowWireless: () {},
            onShowEmulators: () => emulatorsOpened++,
            onShowMessage: (_) {},
            onImportLog: () {},
            onOpenRecent: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Torn down inside the test body: the repository's periodic iOS refresh and
  /// its 500ms "no devices yet" retry are both still live, and the framework's
  /// pending-timer check runs before `tearDown` gets a turn.
  Future<void> closeHome(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    repository.dispose();
    manager?.dispose();
    manager = null;
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets('the Start list opens the emulator manager', (tester) async {
    await pumpHome(tester, windowSize: const Size(1280, 900));

    expect(find.text('Emulators'), findsOneWidget);
    await tester.tap(find.text('Emulators'));
    await tester.pump();

    expect(emulatorsOpened, 1);

    await closeHome(tester);
  });

  testWidgets('a narrow window stacks the columns without overflowing', (
    tester,
  ) async {
    // Too narrow for the Start column beside the devices: they stack, and
    // nothing paints overflow stripes.
    await pumpHome(tester, windowSize: const Size(560, 900));

    expect(find.text('Load devices'), findsNothing);
    expect(find.byTooltip('Load devices'), findsOneWidget);
    expect(find.text('Wireless pairing'), findsOneWidget);
    expect(find.text('Emulators'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await closeHome(tester);
  });

  testWidgets('the Start shortcuts work without clicking first', (
    tester,
  ) async {
    await pumpHome(tester, windowSize: const Size(1280, 900));

    // Tests run as Android, which takes Ctrl rather than ⌘.
    expect(find.text('Ctrl+E'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(emulatorsOpened, 1);

    await closeHome(tester);
  });

  testWidgets('the masthead hides the version while it is unknown', (
    tester,
  ) async {
    // Package info isn't loaded in tests, so there is no version to show,
    // and a "vUnknown" pill would be worse than none.
    await pumpHome(tester, windowSize: const Size(1280, 900));

    expect(find.text('Eagly'), findsOneWidget);
    expect(find.textContaining('vUnknown'), findsNothing);

    await closeHome(tester);
  });
}
