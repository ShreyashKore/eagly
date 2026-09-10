import 'package:eagly/data/device.dart';
import 'package:eagly/features/emulator_manager/data/android_emulator.dart';
import 'package:eagly/features/emulator_manager/data/emulator_entry.dart';
import 'package:eagly/features/emulator_manager/data/emulator_launch_options.dart';
import 'package:eagly/features/emulator_manager/emulator_manager_controller.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/utils/android_sdk_path.dart';
import 'package:flutter_test/flutter_test.dart';

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
  EmulatorManagerController? controller;

  AndroidSdkLocation sdk = fakeReadySdk;

  final readyDevices = <Device>[];

  EmulatorManagerController buildController() {
    return controller = EmulatorManagerController(
      devicesRepository: repository,
      adbTool: adbTool,
      metadataReader: metadataReader,
      locateSdk: () => sdk,
      createEmulatorTool: (_) => emulatorTool,
      createAvdManagerTool: (_) => avdManager,
      systemImageScanner: imageScanner,
      onEmulatorReady: (device) async => readyDevices.add(device),
    );
  }

  setUp(() {
    adbTool = FakeEmulatorAdbTool();
    iosDeviceService = FakeIosDeviceService();
    emulatorTool = FakeEmulatorTool();
    metadataReader = FakeAvdMetadataReader();
    avdManager = FakeAvdManagerTool();
    imageScanner = FakeSystemImageScanner();
    readyDevices.clear();
    sdk = fakeReadySdk;
    repository = DevicesRepository.forTesting(
      adbTool: adbTool,
      iosDeviceService: iosDeviceService,
    );
    // Fast enough that a test never waits on it, slow enough that the loop
    // still yields between ticks.
    EmulatorManagerController.pollInterval = const Duration(milliseconds: 1);
  });

  tearDown(() async {
    controller?.dispose();
    controller = null;
    repository.dispose();
    await adbTool.disposeTool();
    EmulatorManagerController.pollInterval = const Duration(seconds: 2);
    EmulatorManagerController.launchTimeout = const Duration(minutes: 3);
  });

  Future<void> setDevices(List<Device> devices) async {
    adbTool.androidDevices = devices;
    await repository.refreshDevices(force: true);
  }

  // ── Listing ──────────────────────────────────────────────────────────────

  test('refresh lists every AVD, ordered by the label the user sees', () async {
    emulatorTool.avdNames = ['zebra_avd', 'Pixel_7a', 'Small_Phone'];
    metadataReader.emulators['Pixel_7a'] = const AndroidEmulator(
      name: 'Pixel_7a',
      displayName: 'Pixel 7a API 36',
      apiLevel: '36.1',
      abi: 'arm64-v8a',
    );

    final controller = buildController();
    await controller.refresh();

    expect(
      controller.entries.map((entry) => entry.name),
      // "Pixel 7a API 36" < "Small Phone" < "zebra avd", case-insensitively —
      // the display name is what sorts, not the id.
      ['Pixel_7a', 'Small_Phone', 'zebra_avd'],
    );
    expect(
      controller.entries.every((entry) => entry.isStopped),
      isTrue,
      reason: 'nothing is running in this fixture',
    );
    expect(controller.entryFor('Pixel_7a')!.emulator.apiLevel, '36.1');
    expect(controller.isLoading, isFalse);
    expect(controller.error, isNull);
  });

  test('an SDK without the emulator package lists nothing and asks for '
      'nothing', () async {
    sdk = const AndroidSdkLocation(
      status: AndroidSdkStatus.emulatorMissing,
      sdkPath: '/fake/sdk',
    );

    final controller = buildController();
    await controller.refresh();

    expect(controller.isSdkReady, isFalse);
    expect(controller.canManageAvds, isFalse);
    expect(controller.entries, isEmpty);
    expect(
      emulatorTool.listCallCount,
      0,
      reason: 'there is no emulator binary to ask',
    );
  });

  test('an SDK without cmdline-tools can still list and launch', () async {
    sdk = const AndroidSdkLocation(
      status: AndroidSdkStatus.ready,
      sdkPath: '/fake/sdk',
      emulatorExecutable: '/fake/sdk/emulator/emulator',
    );
    emulatorTool.avdNames = ['Small_Phone'];

    final controller = buildController();
    await controller.refresh();

    expect(controller.isSdkReady, isTrue);
    expect(controller.canManageAvds, isFalse);
    expect(controller.entries, hasLength(1));
  });

  // ── Runtime state ────────────────────────────────────────────────────────

  test(
    'a running emulator is matched to its AVD through the console',
    () async {
      emulatorTool.avdNames = ['Pixel_7a', 'Small_Phone'];
      adbTool.avdNames['emulator-5554'] = 'Small_Phone';
      await setDevices([Device.android('emulator-5554', 'device')]);

      final controller = buildController();
      await controller.refresh();

      final running = controller.entryFor('Small_Phone')!;
      expect(running.runState, EmulatorRunState.running);
      expect(running.serial, 'emulator-5554');
      expect(controller.entryFor('Pixel_7a')!.isStopped, isTrue);
    },
  );

  test('a physical device is never asked for an AVD name', () async {
    emulatorTool.avdNames = ['Small_Phone'];
    await setDevices([
      Device.android('39041FDJH00ABC', 'device'),
      Device.android('192.168.0.10:5555', 'device'),
    ]);

    final controller = buildController();
    await controller.refresh();

    expect(adbTool.avdNameRequests, isEmpty);
    expect(controller.entryFor('Small_Phone')!.isStopped, isTrue);
  });

  test('the AVD name of a serial is resolved once and reused', () async {
    emulatorTool.avdNames = ['Small_Phone'];
    adbTool.avdNames['emulator-5554'] = 'Small_Phone';
    await setDevices([Device.android('emulator-5554', 'device')]);

    final controller = buildController();
    await controller.start();
    await _pump(const Duration(milliseconds: 40));

    expect(
      adbTool.avdNameRequests,
      ['emulator-5554'],
      reason:
          'a serial cannot change AVD while it is up, so one call is all '
          'the poll may cost',
    );
  });

  test(
    'a console that has not answered yet is retried on the next tick',
    () async {
      emulatorTool.avdNames = ['Small_Phone'];
      // No mapping registered: the console refuses, as it does mid-boot.
      await setDevices([Device.android('emulator-5554', 'device')]);

      final controller = buildController();
      await controller.start();
      await waitFor(() => adbTool.avdNameRequests.length >= 3);

      expect(controller.entryFor('Small_Phone')!.isStopped, isTrue);
    },
  );

  test(
    'a serial that goes away releases its AVD and its cached name',
    () async {
      emulatorTool.avdNames = ['Small_Phone'];
      adbTool.avdNames['emulator-5554'] = 'Small_Phone';
      await setDevices([Device.android('emulator-5554', 'device')]);

      final controller = buildController();
      await controller.start();
      expect(controller.entryFor('Small_Phone')!.isRunning, isTrue);

      await setDevices([]);
      await waitFor(() => controller.entryFor('Small_Phone')!.isStopped);

      expect(controller.entryFor('Small_Phone')!.serial, isNull);

      // The port is recycled, so the mapping must not have been kept.
      adbTool.avdNames['emulator-5554'] = 'Small_Phone';
      await setDevices([Device.android('emulator-5554', 'device')]);
      await waitFor(() => controller.entryFor('Small_Phone')!.isRunning);

      expect(adbTool.avdNameRequests, hasLength(2));
    },
  );

  // ── Launching ────────────────────────────────────────────────────────────

  test(
    'launch spawns the emulator and shows it starting, without a tab',
    () async {
      emulatorTool.avdNames = ['Small_Phone'];

      final controller = buildController();
      await controller.refresh();
      final started = await controller.launch(
        'Small_Phone',
        options: const EmulatorLaunchOptions(coldBoot: true),
      );

      expect(started, isTrue);
      expect(emulatorTool.launchRequests, [('Small_Phone', true, false)]);
      expect(
        controller.entryFor('Small_Phone')!.runState,
        EmulatorRunState.starting,
      );
      expect(controller.pendingLaunches, {'Small_Phone'});
      expect(readyDevices, isEmpty, reason: 'nothing has booted yet');
      expect(
        controller.isBusy,
        isFalse,
        reason:
            'the process is spawned; waiting for the boot must not block the '
            'dialog for the minutes that takes',
      );
    },
  );

  test(
    'a launched emulator hands its device over once it comes online',
    () async {
      emulatorTool.avdNames = ['Small_Phone'];
      adbTool.avdNames['emulator-5556'] = 'Small_Phone';

      final controller = buildController();
      await controller.start();
      await controller.launch('Small_Phone');

      await setDevices([Device.android('emulator-5556', 'device')]);
      await waitFor(() => readyDevices.isNotEmpty);

      expect(readyDevices.single.id, 'emulator-5556');
      expect(controller.entryFor('Small_Phone')!.isRunning, isTrue);
      expect(controller.pendingLaunches, isEmpty);
      expect(controller.message, contains('ready'));
    },
  );

  test('an emulator started outside eagly opens no tab', () async {
    emulatorTool.avdNames = ['Small_Phone'];
    adbTool.avdNames['emulator-5554'] = 'Small_Phone';

    final controller = buildController();
    await controller.start();

    await setDevices([Device.android('emulator-5554', 'device')]);
    await waitFor(() => controller.entryFor('Small_Phone')!.isRunning);
    await _pump(const Duration(milliseconds: 20));

    expect(
      readyDevices,
      isEmpty,
      reason: 'the user did not ask eagly to open it, so eagly does not',
    );
  });

  test('launching an AVD this SDK no longer has starts nothing', () async {
    emulatorTool.avdNames = ['Small_Phone'];

    final controller = buildController();
    await controller.refresh();
    final started = await controller.launch('Deleted_AVD');

    expect(started, isFalse);
    expect(controller.error, contains('Deleted_AVD'));
    expect(emulatorTool.launchRequests, isEmpty);
  });

  test('launching an AVD that is already up is refused', () async {
    emulatorTool.avdNames = ['Small_Phone'];
    adbTool.avdNames['emulator-5554'] = 'Small_Phone';
    await setDevices([Device.android('emulator-5554', 'device')]);

    final controller = buildController();
    await controller.refresh();
    final started = await controller.launch('Small_Phone');

    expect(started, isFalse);
    expect(controller.error, contains('already running'));
    expect(emulatorTool.launchRequests, isEmpty);
  });

  test('a launch the emulator binary rejects is reported', () async {
    emulatorTool.avdNames = ['Small_Phone'];
    emulatorTool.launchOutcome = const EmulatorLaunchOutcome.failure(
      'Could not start Small_Phone: No such file or directory',
    );

    final controller = buildController();
    await controller.refresh();
    final started = await controller.launch('Small_Phone');

    expect(started, isFalse);
    expect(controller.error, contains('No such file or directory'));
    expect(controller.pendingLaunches, isEmpty);
    expect(controller.entryFor('Small_Phone')!.isStopped, isTrue);
  });

  test('a launch that never boots gives up and says so', () async {
    EmulatorManagerController.launchTimeout = const Duration(milliseconds: 1);
    emulatorTool.avdNames = ['Small_Phone'];

    final controller = buildController();
    await controller.start();
    await controller.launch('Small_Phone');

    await waitFor(() => controller.error != null);

    expect(controller.error, contains('did not finish booting'));
    expect(controller.pendingLaunches, isEmpty);
    expect(controller.entryFor('Small_Phone')!.isStopped, isTrue);
    expect(readyDevices, isEmpty);
  });

  // ── Stopping ─────────────────────────────────────────────────────────────

  test('stop asks the emulator console to shut down', () async {
    emulatorTool.avdNames = ['Small_Phone'];
    adbTool.avdNames['emulator-5554'] = 'Small_Phone';
    await setDevices([Device.android('emulator-5554', 'device')]);

    final controller = buildController();
    await controller.start();
    final stopped = await controller.stopEmulator('Small_Phone');

    expect(stopped, isTrue);
    expect(adbTool.killRequests, ['emulator-5554']);
    expect(
      controller.entryFor('Small_Phone')!.runState,
      EmulatorRunState.stopping,
      reason:
          'the emulator exits on its own schedule; the tile says so until '
          'the serial actually goes away',
    );

    await setDevices([]);
    await waitFor(() => controller.entryFor('Small_Phone')!.isStopped);
  });

  test('a stop that fails puts the AVD back to running', () async {
    emulatorTool.avdNames = ['Small_Phone'];
    adbTool.avdNames['emulator-5554'] = 'Small_Phone';
    adbTool.killResult = DeviceCommandResult.failure(error: 'device offline');
    await setDevices([Device.android('emulator-5554', 'device')]);

    final controller = buildController();
    await controller.refresh();
    final stopped = await controller.stopEmulator('Small_Phone');

    expect(stopped, isFalse);
    expect(controller.error, 'device offline');
    expect(controller.entryFor('Small_Phone')!.isRunning, isTrue);
  });

  test('stopping an AVD that is not running is refused', () async {
    emulatorTool.avdNames = ['Small_Phone'];

    final controller = buildController();
    await controller.refresh();
    final stopped = await controller.stopEmulator('Small_Phone');

    expect(stopped, isFalse);
    expect(controller.error, contains('not running'));
    expect(adbTool.killRequests, isEmpty);
  });

  // ── Creating and deleting ────────────────────────────────────────────────

  test('the create sheet gets the installed images and the profiles', () async {
    imageScanner.images = const [fakePlayStoreImage];
    avdManager.profiles = const [fakePixelProfile, fakeTvProfile];

    final controller = buildController();
    await controller.refresh();
    await controller.loadCreationOptions();

    expect(imageScanner.scanRequests, ['/fake/sdk']);
    expect(controller.systemImages, [fakePlayStoreImage]);
    expect(controller.deviceProfiles, hasLength(2));
    expect(controller.hasLoadedCreationOptions, isTrue);
  });

  test('the options are loaded once, not on every open', () async {
    imageScanner.images = const [fakePlayStoreImage];

    final controller = buildController();
    await controller.refresh();
    await controller.loadCreationOptions();
    await controller.loadCreationOptions();
    await controller.loadCreationOptions();

    expect(
      avdManager.listProfilesCallCount,
      1,
      reason: 'each avdmanager call costs a JVM start of about 1.5s',
    );
    expect(imageScanner.scanRequests, hasLength(1));
  });

  test('force re-reads them, for an SDK that changed underneath', () async {
    final controller = buildController();
    await controller.refresh();
    await controller.loadCreationOptions();
    await controller.loadCreationOptions(force: true);

    expect(avdManager.listProfilesCallCount, 2);
  });

  test('an SDK without cmdline-tools still loads its images', () async {
    sdk = const AndroidSdkLocation(
      status: AndroidSdkStatus.ready,
      sdkPath: '/fake/sdk',
      emulatorExecutable: '/fake/sdk/emulator/emulator',
    );
    imageScanner.images = const [fakePlayStoreImage];

    final controller = buildController();
    await controller.refresh();
    await controller.loadCreationOptions();

    expect(controller.systemImages, [fakePlayStoreImage]);
    expect(controller.deviceProfiles, isEmpty);
    expect(avdManager.listProfilesCallCount, 0);
  });

  test('create passes the image and profile through, then reloads', () async {
    emulatorTool.avdNames = [];

    final controller = buildController();
    await controller.refresh();

    emulatorTool.avdNames = ['Pixel_7_API_34'];
    final created = await controller.createEmulator(
      name: 'Pixel_7_API_34',
      packagePath: fakePlayStoreImage.packagePath,
      deviceProfileId: 'pixel_7',
    );

    expect(created, isTrue);
    expect(avdManager.createRequests, [
      ('Pixel_7_API_34', fakePlayStoreImage.packagePath, 'pixel_7'),
    ]);
    expect(
      controller.entryFor('Pixel_7_API_34')?.isStopped,
      isTrue,
      reason: 'creating is not launching, and the list has to show it',
    );
  });

  test('a name is trimmed and checked before the JVM starts', () async {
    final controller = buildController();
    await controller.refresh();

    final created = await controller.createEmulator(
      name: 'has spaces',
      packagePath: fakePlayStoreImage.packagePath,
    );

    expect(created, isFalse);
    expect(controller.error, contains('no spaces'));
    expect(avdManager.createRequests, isEmpty);
  });

  test('a name already taken is refused', () async {
    emulatorTool.avdNames = ['Small_Phone'];

    final controller = buildController();
    await controller.refresh();
    final created = await controller.createEmulator(
      name: '  Small_Phone  ',
      packagePath: fakePlayStoreImage.packagePath,
    );

    expect(created, isFalse);
    expect(controller.error, contains('already exists'));
    expect(avdManager.createRequests, isEmpty);
  });

  test('a create that avdmanager rejects is reported', () async {
    avdManager.createResult = DeviceCommandResult.failure(
      error: 'Package path is not valid.',
    );

    final controller = buildController();
    await controller.refresh();
    final created = await controller.createEmulator(
      name: 'Broken',
      packagePath: 'system-images;android-99;google_apis;arm64-v8a',
    );

    expect(created, isFalse);
    expect(controller.error, 'Package path is not valid.');
  });

  test('creating without cmdline-tools says what is missing', () async {
    sdk = const AndroidSdkLocation(
      status: AndroidSdkStatus.ready,
      sdkPath: '/fake/sdk',
      emulatorExecutable: '/fake/sdk/emulator/emulator',
    );

    final controller = buildController();
    await controller.refresh();
    final created = await controller.createEmulator(
      name: 'Nope',
      packagePath: fakePlayStoreImage.packagePath,
    );

    expect(created, isFalse);
    expect(controller.canManageAvds, isFalse);
    expect(controller.error, contains('cmdline-tools'));
  });

  test('delete removes the AVD and reloads the list', () async {
    emulatorTool.avdNames = ['Small_Phone'];

    final controller = buildController();
    await controller.refresh();

    emulatorTool.avdNames = [];
    final deleted = await controller.deleteEmulator('Small_Phone');

    expect(deleted, isTrue);
    expect(avdManager.deleteRequests, ['Small_Phone']);
    expect(controller.entries, isEmpty);
  });

  test('a running AVD is never deleted out from under itself', () async {
    emulatorTool.avdNames = ['Small_Phone'];
    adbTool.avdNames['emulator-5554'] = 'Small_Phone';
    await setDevices([Device.android('emulator-5554', 'device')]);

    final controller = buildController();
    await controller.refresh();
    final deleted = await controller.deleteEmulator('Small_Phone');

    expect(deleted, isFalse);
    expect(controller.error, contains('Stop Small Phone'));
    expect(
      avdManager.deleteRequests,
      isEmpty,
      reason:
          'pulling the disk images out from under a live emulator leaves '
          'neither a working AVD nor a clean absence',
    );
  });

  test('deleting an AVD that is already gone is reported', () async {
    final controller = buildController();
    await controller.refresh();

    final deleted = await controller.deleteEmulator('Ghost');

    expect(deleted, isFalse);
    expect(avdManager.deleteRequests, isEmpty);
  });

  // ── The poll itself ──────────────────────────────────────────────────────

  test('a quiet poll never wakes the UI', () async {
    emulatorTool.avdNames = ['Small_Phone'];
    adbTool.avdNames['emulator-5554'] = 'Small_Phone';
    await setDevices([Device.android('emulator-5554', 'device')]);

    final controller = buildController();
    await controller.start();
    await _pump(const Duration(milliseconds: 20));

    var notifications = 0;
    controller.addListener(() => notifications++);
    await _pump(const Duration(milliseconds: 60));

    expect(
      notifications,
      0,
      reason:
          'a 2 s unconditional rebuild pulls the ground out from under any '
          'text field the dialog has open',
    );
  });

  test('dispose stops a poll parked in its delay', () async {
    emulatorTool.avdNames = ['Small_Phone'];
    // Never answers, so every tick costs one visible call.
    await setDevices([Device.android('emulator-5554', 'device')]);

    // Not shadowed: tearDown must not dispose this one a second time.
    buildController();
    await controller!.start();
    await waitFor(() => adbTool.avdNameRequests.length >= 3);

    final disposed = controller!;
    disposed.dispose();
    controller = null;
    final settled = adbTool.avdNameRequests.length;
    await _pump(const Duration(milliseconds: 40));

    expect(
      adbTool.avdNameRequests,
      hasLength(settled),
      reason:
          'a loop parked in Future.delayed cannot be interrupted, so it '
          'has to check the generation on waking',
    );
    expect(disposed.isPolling, isFalse);
  });
}

Future<void> _pump(Duration duration) => Future<void>.delayed(duration);
