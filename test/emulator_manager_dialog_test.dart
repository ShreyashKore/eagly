import 'package:eagly/data/device.dart';
import 'package:eagly/features/emulator_manager/components/emulator_tile.dart';
import 'package:eagly/features/emulator_manager/data/android_emulator.dart';
import 'package:eagly/features/emulator_manager/data/emulator_launch_options.dart';
import 'package:eagly/features/emulator_manager/emulator_manager_controller.dart';
import 'package:eagly/features/emulator_manager/emulator_manager_dialog.dart';
import 'package:eagly/features/emulator_manager/services/android_sdk_picker.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_manager.dart';
import 'package:eagly/utils/android_sdk_path.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/emulator_test_support.dart';
import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeEmulatorAdbTool adbTool;
  late FakeIosDeviceService iosDeviceService;
  late FakeEmulatorTool emulatorTool;
  late FakeAvdMetadataReader metadataReader;
  late FakeAvdManagerTool avdManager;
  late FakeSystemImageScanner imageScanner;
  late DevicesRepository repository;
  DeviceSessionManager? manager;
  EmulatorManagerController? controller;
  late AndroidSdkLocation sdk;
  final snackBars = <String>[];

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() {
    adbTool = FakeEmulatorAdbTool();
    iosDeviceService = FakeIosDeviceService();
    emulatorTool = FakeEmulatorTool();
    metadataReader = FakeAvdMetadataReader();
    avdManager = FakeAvdManagerTool();
    imageScanner = FakeSystemImageScanner();
    snackBars.clear();
    sdk = fakeReadySdk;
    repository = DevicesRepository.forTesting(
      adbTool: adbTool,
      iosDeviceService: iosDeviceService,
    );
    // Idle: these tests are about the UI, and a live poll would only add
    // pending timers to drain.
    EmulatorManagerController.pollInterval = const Duration(seconds: 30);
  });

  tearDown(() async {
    manager?.dispose();
    manager = null;
    controller = null;
    await adbTool.disposeTool();
    EmulatorManagerController.pollInterval = const Duration(seconds: 2);
    AndroidSdkPicker.resetChooseDirectory();
    AndroidSdkPath.resetEnvironment();
  });

  /// One frame, then past any route or menu transition.
  ///
  /// Explicit pumps, not `pumpAndSettle`: a tile showing "Starting…" and the
  /// loading state both animate forever, and the repository's own refresh
  /// timer keeps scheduling frames — so settling never happens.
  Future<void> pumpAction(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpDialog(
    WidgetTester tester, {
    Size windowSize = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = windowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    manager = DeviceSessionManager(
      repository: repository,
      serviceFactory: (device) => FakeSessionService(device),
    );

    // Pushed as a real route, not dropped into a Scaffold body: the dialog
    // closes itself once a launched emulator boots, and Navigator.pop needs
    // something to pop for that to be testable at all.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => EmulatorManagerDialog(
                  manager: manager!,
                  onShowSnackBar: snackBars.add,
                  createController: (onEmulatorReady) =>
                      controller = EmulatorManagerController(
                        devicesRepository: repository,
                        adbTool: adbTool,
                        metadataReader: metadataReader,
                        locateSdk: () => sdk,
                        createEmulatorTool: (_) => emulatorTool,
                        createAvdManagerTool: (_) => avdManager,
                        systemImageScanner: imageScanner,
                        onEmulatorReady: onEmulatorReady,
                      ),
                ),
              ),
              child: const Text('open emulators'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open emulators'));
    // start() is fired from initState and awaits the AVD list.
    await pumpAction(tester);
  }

  /// Tears the dialog down inside the test body, so the controller's poll is
  /// disposed before the framework's pending-timer check runs.
  Future<void> closeDialog(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    repository.dispose();
    manager?.dispose();
    manager = null;
    await tester.pump(EmulatorManagerController.pollInterval);
  }

  testWidgets('lists every AVD with its details and a Start button', (
    tester,
  ) async {
    emulatorTool.avdNames = ['Pixel_7a', 'Small_Phone'];
    metadataReader.emulators['Pixel_7a'] = const AndroidEmulator(
      name: 'Pixel_7a',
      displayName: 'Pixel 7a API 36',
      apiLevel: '36.1',
      tagDisplay: 'Google Play',
      abi: 'arm64-v8a',
      screenWidthPx: 1080,
      screenHeightPx: 2400,
      ramMb: 2048,
      hasPlayStore: true,
    );

    await pumpDialog(tester);

    expect(find.byType(EmulatorTile), findsNWidgets(2));
    expect(find.text('Pixel 7a API 36'), findsOneWidget);
    // Underscores read back as spaces when the AVD set no display name.
    expect(find.text('Small Phone'), findsOneWidget);
    expect(
      find.text('API 36.1 · Google Play · arm64-v8a · 1080 × 2400 · 2 GB'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Start'), findsNWidgets(2));
    expect(find.widgetWithText(OutlinedButton, 'Stop'), findsNothing);

    await closeDialog(tester);
  });

  testWidgets('Start launches the AVD and the tile switches to Starting', (
    tester,
  ) async {
    emulatorTool.avdNames = ['Small_Phone'];
    await pumpDialog(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await pumpAction(tester);

    expect(emulatorTool.launchRequests, [('Small_Phone', false, false)]);
    expect(find.text('Starting…'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start'), findsNothing);

    await closeDialog(tester);
  });

  testWidgets('a running AVD offers Stop, and Stop asks the console', (
    tester,
  ) async {
    emulatorTool.avdNames = ['Small_Phone'];
    adbTool.avdNames['emulator-5554'] = 'Small_Phone';
    adbTool.androidDevices = [Device.android('emulator-5554', 'device')];
    await repository.refreshDevices(force: true);

    await pumpDialog(tester);

    expect(find.text('emulator-5554'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Stop'));
    await pumpAction(tester);

    expect(adbTool.killRequests, ['emulator-5554']);
    expect(find.text('Stopping…'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('wiping data is confirmed first, and Cancel starts nothing', (
    tester,
  ) async {
    emulatorTool.avdNames = ['Small_Phone'];
    await pumpDialog(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await pumpAction(tester);
    await tester.tap(find.text('Wipe data and start'));
    await pumpAction(tester);

    expect(find.text('Wipe data and start?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await pumpAction(tester);

    expect(
      emulatorTool.launchRequests,
      isEmpty,
      reason: 'a factory reset the user backed out of must not happen',
    );

    await closeDialog(tester);
  });

  testWidgets('confirming the wipe launches with -wipe-data', (tester) async {
    emulatorTool.avdNames = ['Small_Phone'];
    await pumpDialog(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await pumpAction(tester);
    await tester.tap(find.text('Wipe data and start'));
    await pumpAction(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Wipe and start'));
    await pumpAction(tester);

    expect(emulatorTool.launchRequests, [('Small_Phone', false, true)]);

    await closeDialog(tester);
  });

  testWidgets('a cold boot passes the flag through', (tester) async {
    emulatorTool.avdNames = ['Small_Phone'];
    await pumpDialog(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await pumpAction(tester);
    await tester.tap(find.text('Cold boot'));
    await pumpAction(tester);

    expect(emulatorTool.launchRequests, [('Small_Phone', true, false)]);

    await closeDialog(tester);
  });

  testWidgets('a booted emulator opens its tab and closes the dialog', (
    tester,
  ) async {
    emulatorTool.avdNames = ['Small_Phone'];
    adbTool.avdNames['emulator-5556'] = 'Small_Phone';
    await pumpDialog(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await pumpAction(tester);

    // The emulator finishes booting.
    //
    // No explicit refreshDevices here, and awaiting one would deadlock: with
    // no devices yet, the manager's own start-up refresh is parked in a 500ms
    // retry that only a pump can advance, and refreshDevices would hand the
    // test that same parked future. Pumping past the retry lets it find this
    // device by itself.
    adbTool.androidDevices = [Device.android('emulator-5556', 'device')];
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(EmulatorManagerController.pollInterval);
    await pumpAction(tester);
    // Past the dialog's own dismissal transition.
    await tester.pump(const Duration(milliseconds: 400));

    expect(manager!.selectedId, 'emulator-5556');
    expect(snackBars.single, contains('is ready'));
    expect(find.byType(EmulatorTile), findsNothing);

    await closeDialog(tester);
  });

  testWidgets('an SDK with no emulator package says which SDK it means', (
    tester,
  ) async {
    sdk = const AndroidSdkLocation(
      status: AndroidSdkStatus.emulatorMissing,
      sdkPath: '/opt/android-sdk',
    );

    await pumpDialog(tester);

    expect(find.text('The emulator package is not installed'), findsOneWidget);
    expect(find.textContaining('/opt/android-sdk'), findsOneWidget);
    expect(find.byType(EmulatorTile), findsNothing);

    await closeDialog(tester);
  });

  testWidgets('no SDK at all is a state, not an error', (tester) async {
    sdk = const AndroidSdkLocation.missing();

    await pumpDialog(tester);

    expect(find.text('No Android SDK found'), findsOneWidget);
    expect(
      emulatorTool.listCallCount,
      0,
      reason: 'there is no emulator binary to ask',
    );

    await closeDialog(tester);
  });

  testWidgets('the missing-SDK state names every place that was searched', (
    tester,
  ) async {
    sdk = const AndroidSdkLocation.missing();
    // A path only wrong by one directory is the hard case, so the notice has
    // to say where Eagly actually looked rather than leave it to be guessed.
    AndroidSdkPath.environment = const {
      'HOME': '/home/tester',
      'ANDROID_HOME': '/opt/android-home',
      'ANDROID_SDK_ROOT': '/opt/android-sdk-root',
    };

    await pumpDialog(tester);

    expect(find.text('/opt/android-home'), findsOneWidget);
    expect(find.text('/opt/android-sdk-root'), findsOneWidget);
    expect(find.textContaining('/home/tester'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Locate SDK…'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('locating an SDK saves it and reloads the list', (tester) async {
    final root = Directory.systemTemp.createTempSync('dialog-sdk');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/platform-tools').createSync(recursive: true);

    sdk = const AndroidSdkLocation.missing();
    AndroidSdkPicker.chooseDirectory = ({String? initialDirectory}) async =>
        root.path;

    await pumpDialog(tester);
    expect(find.text('No Android SDK found'), findsOneWidget);

    // The controller re-locates on every refresh, so the dialog picks the new
    // path up with no plumbing between here and Settings.
    sdk = fakeReadySdk;
    emulatorTool.avdNames = ['Small_Phone'];
    await tester.tap(find.widgetWithText(FilledButton, 'Locate SDK…'));
    await pumpAction(tester);

    expect(PreferencesService.androidSdkPath, root.path);
    expect(snackBars.single, contains(root.path));
    expect(find.byType(EmulatorTile), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('an incomplete SDK still offers a way out', (tester) async {
    sdk = const AndroidSdkLocation(
      status: AndroidSdkStatus.emulatorMissing,
      sdkPath: '/opt/android-sdk',
    );

    await pumpDialog(tester);

    expect(
      find.widgetWithText(FilledButton, 'Use a different SDK…'),
      findsOneWidget,
    );

    await closeDialog(tester);
  });

  testWidgets('an SDK with no AVDs points at the Device Manager', (
    tester,
  ) async {
    await pumpDialog(tester);

    expect(find.text('No emulators yet'), findsOneWidget);
    expect(find.byType(EmulatorTile), findsNothing);

    await closeDialog(tester);
  });

  testWidgets('a failed launch is shown in the banner', (tester) async {
    emulatorTool.avdNames = ['Small_Phone'];
    emulatorTool.launchOutcome = const EmulatorLaunchOutcome.failure(
      'Could not start Small_Phone: No such file or directory',
    );
    await pumpDialog(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await pumpAction(tester);

    expect(find.textContaining('No such file or directory'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('the tiles survive a window too small for the dialog', (
    tester,
  ) async {
    emulatorTool.avdNames = ['Pixel_7a'];
    metadataReader.emulators['Pixel_7a'] = const AndroidEmulator(
      name: 'Pixel_7a',
      displayName: 'Pixel 7a API 36 Google Play Edition',
      apiLevel: '36.1',
      tagDisplay: 'Google Play',
      abi: 'arm64-v8a',
      screenWidthPx: 1080,
      screenHeightPx: 2400,
      ramMb: 2048,
    );

    // Smaller than the dialog asks for, so EaglyDialog clamps it and the tile
    // has to give: the name ellipsizes rather than painting overflow stripes.
    await pumpDialog(tester, windowSize: const Size(560, 460));

    expect(find.byType(EmulatorTile), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await closeDialog(tester);
  });

  // ── Creating and deleting ────────────────────────────────────────────────

  testWidgets('the create sheet offers the installed images', (tester) async {
    emulatorTool.avdNames = ['Small_Phone'];
    imageScanner.images = const [fakePlayStoreImage];
    avdManager.profiles = const [fakePixelProfile, fakeTvProfile];

    await pumpDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'New'));
    await pumpAction(tester);

    expect(find.text('New emulator'), findsOneWidget);
    expect(find.text('API 34 · Google Play · arm64-v8a'), findsOneWidget);
    // The TV profile belongs to another device class and is not offered for a
    // phone image — that pairing boots to a blank screen.
    expect(find.text('Pixel 7 · Google'), findsOneWidget);
    expect(find.text('Television (1080p) · Google'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await pumpAction(tester);
    await closeDialog(tester);
  });

  testWidgets('creating passes the name, image and profile through', (
    tester,
  ) async {
    imageScanner.images = const [fakePlayStoreImage];
    avdManager.profiles = const [fakePixelProfile];

    await pumpDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'New'));
    await pumpAction(tester);

    await tester.enterText(find.byType(TextField), 'Pixel_7_API_34');
    emulatorTool.avdNames = ['Pixel_7_API_34'];
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await pumpAction(tester);

    expect(avdManager.createRequests, [
      ('Pixel_7_API_34', fakePlayStoreImage.packagePath, 'pixel_7'),
    ]);
    expect(find.byType(EmulatorTile), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('a name with a space is caught in the sheet', (tester) async {
    imageScanner.images = const [fakePlayStoreImage];

    await pumpDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'New'));
    await pumpAction(tester);

    await tester.enterText(find.byType(TextField), 'Pixel 7');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await pumpAction(tester);

    expect(find.textContaining('no spaces'), findsOneWidget);
    expect(
      avdManager.createRequests,
      isEmpty,
      reason: 'a typo should not cost a JVM start',
    );
    // Still open, with the mistake shown in place rather than dismissed.
    expect(find.widgetWithText(FilledButton, 'Create'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await pumpAction(tester);
    await closeDialog(tester);
  });

  testWidgets('an SDK with no system images says so instead of pretending', (
    tester,
  ) async {
    emulatorTool.avdNames = ['Small_Phone'];

    await pumpDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'New'));
    await pumpAction(tester);

    expect(find.text('No system images installed'), findsOneWidget);
    final create = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create'),
    );
    expect(create.onPressed, isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await pumpAction(tester);
    await closeDialog(tester);
  });

  testWidgets('without cmdline-tools there is nothing to create with', (
    tester,
  ) async {
    sdk = const AndroidSdkLocation(
      status: AndroidSdkStatus.ready,
      sdkPath: '/fake/sdk',
      emulatorExecutable: '/fake/sdk/emulator/emulator',
    );
    emulatorTool.avdNames = ['Small_Phone'];

    await pumpDialog(tester);

    expect(
      find.widgetWithText(TextButton, 'New'),
      findsNothing,
      reason:
          'an action that can never work in this SDK is noise, not a '
          'disabled button',
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await pumpAction(tester);
    expect(find.text('Delete'), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await pumpAction(tester);
    await closeDialog(tester);
  });

  testWidgets('deleting is confirmed, and Cancel deletes nothing', (
    tester,
  ) async {
    emulatorTool.avdNames = ['Small_Phone'];

    await pumpDialog(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await pumpAction(tester);
    await tester.tap(find.text('Delete'));
    await pumpAction(tester);

    expect(find.text('Delete this emulator?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await pumpAction(tester);

    expect(avdManager.deleteRequests, isEmpty);
    expect(find.byType(EmulatorTile), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('confirming the delete removes it from the list', (tester) async {
    emulatorTool.avdNames = ['Small_Phone'];

    await pumpDialog(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await pumpAction(tester);
    await tester.tap(find.text('Delete'));
    await pumpAction(tester);

    emulatorTool.avdNames = [];
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await pumpAction(tester);

    expect(avdManager.deleteRequests, ['Small_Phone']);
    expect(find.byType(EmulatorTile), findsNothing);
    expect(find.text('No emulators yet'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('closing the dialog disposes the controller', (tester) async {
    emulatorTool.avdNames = ['Small_Phone'];
    await pumpDialog(tester);

    final live = controller!;
    expect(live.isPolling, isTrue);

    await closeDialog(tester);

    expect(
      live.isPolling,
      isFalse,
      reason: 'the poll loop must not outlive the dialog that owns it',
    );
  });
}
