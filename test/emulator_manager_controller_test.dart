import 'dart:async';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/emulator_manager/data/android_emulator.dart';
import 'package:eagly/features/emulator_manager/data/emulator_entry.dart';
import 'package:eagly/features/emulator_manager/data/emulator_launch_options.dart';
import 'package:eagly/features/emulator_manager/emulator_manager_controller.dart';
import 'package:eagly/features/emulator_manager/services/avd_metadata_reader.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/services/ios/ios_device_domains.dart';
import 'package:eagly/services/ios/ios_device_service.dart';
import 'package:eagly/data/ios_device_info.dart';
import 'package:eagly/services/tools/adb_tool.dart';
import 'package:eagly/services/tools/emulator_tool.dart';
import 'package:eagly/utils/android_sdk_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeEmulatorAdbTool adbTool;
  late _FakeIosDeviceService iosDeviceService;
  late _FakeEmulatorTool emulatorTool;
  late _FakeMetadataReader metadataReader;
  late DevicesRepository repository;
  EmulatorManagerController? controller;

  AndroidSdkLocation sdk = const AndroidSdkLocation(
    status: AndroidSdkStatus.ready,
    sdkPath: '/fake/sdk',
    emulatorExecutable: '/fake/sdk/emulator/emulator',
    avdManagerExecutable: '/fake/sdk/cmdline-tools/latest/bin/avdmanager',
  );

  final readyDevices = <Device>[];

  EmulatorManagerController buildController() {
    return controller = EmulatorManagerController(
      devicesRepository: repository,
      adbTool: adbTool,
      metadataReader: metadataReader,
      locateSdk: () => sdk,
      createEmulatorTool: (_) => emulatorTool,
      onEmulatorReady: (device) async => readyDevices.add(device),
    );
  }

  setUp(() {
    adbTool = _FakeEmulatorAdbTool();
    iosDeviceService = _FakeIosDeviceService();
    emulatorTool = _FakeEmulatorTool();
    metadataReader = _FakeMetadataReader();
    readyDevices.clear();
    sdk = const AndroidSdkLocation(
      status: AndroidSdkStatus.ready,
      sdkPath: '/fake/sdk',
      emulatorExecutable: '/fake/sdk/emulator/emulator',
      avdManagerExecutable: '/fake/sdk/cmdline-tools/latest/bin/avdmanager',
    );
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
      await _waitFor(() => adbTool.avdNameRequests.length >= 3);

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
      await _waitFor(() => controller.entryFor('Small_Phone')!.isStopped);

      expect(controller.entryFor('Small_Phone')!.serial, isNull);

      // The port is recycled, so the mapping must not have been kept.
      adbTool.avdNames['emulator-5554'] = 'Small_Phone';
      await setDevices([Device.android('emulator-5554', 'device')]);
      await _waitFor(() => controller.entryFor('Small_Phone')!.isRunning);

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
      await _waitFor(() => readyDevices.isNotEmpty);

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
    await _waitFor(() => controller.entryFor('Small_Phone')!.isRunning);
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

    await _waitFor(() => controller.error != null);

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
    await _waitFor(() => controller.entryFor('Small_Phone')!.isStopped);
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
    await _waitFor(() => adbTool.avdNameRequests.length >= 3);

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

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition was not met within ${timeout.inSeconds}s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _FakeEmulatorAdbTool extends AdbTool {
  _FakeEmulatorAdbTool() : super(executablePath: '/usr/bin/true');

  List<Device> androidDevices = const [];

  /// Serial → the AVD its console reports. A serial that is absent stands for
  /// a console that has not answered yet.
  final Map<String, String> avdNames = {};
  final List<String> avdNameRequests = [];
  final List<String> killRequests = [];
  DeviceCommandResult killResult = DeviceCommandResult.success(
    message: 'Stopping…',
  );

  final StreamController<List<Device>> _watchController =
      StreamController<List<Device>>.broadcast();

  @override
  Future<List<Device>> getDevices() async => List.of(androidDevices);

  @override
  Future<Device> describeDevice(String deviceId) async =>
      Device.android(deviceId, 'device');

  @override
  Stream<List<Device>> watchDeviceChanges() => _watchController.stream;

  @override
  Future<String?> emulatorAvdName(
    String deviceId, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    avdNameRequests.add(deviceId);
    return avdNames[deviceId];
  }

  @override
  Future<DeviceCommandResult> killEmulator(
    String deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    killRequests.add(deviceId);
    return killResult;
  }

  Future<void> disposeTool() async {
    await _watchController.close();
  }
}

class _FakeEmulatorTool extends EmulatorTool {
  _FakeEmulatorTool() : super(executablePath: '/usr/bin/true');

  List<String> avdNames = const [];
  var listCallCount = 0;

  /// (name, coldBoot, wipeData) per launch.
  final List<(String, bool, bool)> launchRequests = [];
  EmulatorLaunchOutcome launchOutcome = const EmulatorLaunchOutcome.success(
    4242,
  );

  @override
  Future<List<String>> listAvds() async {
    listCallCount++;
    return List.of(avdNames);
  }

  @override
  Future<EmulatorLaunchOutcome> launch(
    String avdName, {
    EmulatorLaunchOptions options = EmulatorLaunchOptions.normal,
  }) async {
    launchRequests.add((avdName, options.coldBoot, options.wipeData));
    return launchOutcome;
  }
}

class _FakeMetadataReader extends AvdMetadataReader {
  // A path that cannot exist, so an unstubbed read is a visible mistake rather
  // than a silent trip through the developer's own ~/.android/avd.
  _FakeMetadataReader() : super(avdHome: '/nonexistent/avd/home');

  final Map<String, AndroidEmulator> emulators = {};

  @override
  Future<AndroidEmulator> read(String name) async =>
      emulators[name] ?? AndroidEmulator(name: name);
}

class _FakeIosDeviceService implements IosDeviceService {
  @override
  Future<List<String>> listDeviceIds() async => const [];

  @override
  Future<IosDeviceInfo> describeDevice(String deviceId) async =>
      IosDeviceInfo(deviceId: deviceId, status: 'device');

  @override
  Future<IosDeviceDomains> readDeviceDomains(String deviceId) async =>
      const IosDeviceDomains();

  @override
  bool get usbmuxdUnavailable => false;
}
