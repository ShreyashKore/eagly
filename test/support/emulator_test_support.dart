import 'package:eagly/data/device.dart';
import 'package:eagly/features/emulator_manager/data/android_emulator.dart';
import 'package:eagly/features/emulator_manager/data/emulator_launch_options.dart';
import 'package:eagly/features/emulator_manager/services/avd_metadata_reader.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/services/tools/emulator_tool.dart';
import 'package:eagly/utils/android_sdk_path.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_test_support.dart';

/// A ready SDK that exists only in the test's head, so nothing here can reach
/// the developer's own `~/Library/Android/sdk`.
const fakeReadySdk = AndroidSdkLocation(
  status: AndroidSdkStatus.ready,
  sdkPath: '/fake/sdk',
  emulatorExecutable: '/fake/sdk/emulator/emulator',
  avdManagerExecutable: '/fake/sdk/cmdline-tools/latest/bin/avdmanager',
);

/// [FakeAdbTool] plus the emulator console commands.
class FakeEmulatorAdbTool extends FakeAdbTool {
  /// Serial → the AVD its console reports. A serial that is absent stands for
  /// a console that has not answered yet, which is what a booting emulator
  /// looks like.
  final Map<String, String> avdNames = {};
  final List<String> avdNameRequests = [];
  final List<String> killRequests = [];
  DeviceCommandResult killResult = DeviceCommandResult.success(
    message: 'Stopping…',
  );

  /// Skips the real `adb shell getprop` round trip the base class would make
  /// for every online device.
  @override
  Future<Device> describeDevice(String deviceId) async =>
      Device.android(deviceId, 'device');

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
}

class FakeEmulatorTool extends EmulatorTool {
  FakeEmulatorTool() : super(executablePath: '/usr/bin/true');

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

class FakeAvdMetadataReader extends AvdMetadataReader {
  // A path that cannot exist, so an unstubbed read is a visible mistake rather
  // than a silent trip through the developer's own ~/.android/avd.
  FakeAvdMetadataReader() : super(avdHome: '/nonexistent/avd/home');

  final Map<String, AndroidEmulator> emulators = {};

  @override
  Future<AndroidEmulator> read(String name) async =>
      emulators[name] ?? AndroidEmulator(name: name);
}

/// Polls [condition] on the real clock. For widget tests drive the fake clock
/// with `tester.pump` instead.
Future<void> waitFor(
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
