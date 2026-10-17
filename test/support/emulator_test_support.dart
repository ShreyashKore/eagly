import 'package:eagly/data/device.dart';
import 'package:eagly/features/emulator_manager/data/android_emulator.dart';
import 'package:eagly/features/emulator_manager/data/emulator_launch_options.dart';
import 'package:eagly/features/emulator_manager/data/device_profile.dart';
import 'package:eagly/features/emulator_manager/data/system_image.dart';
import 'package:eagly/features/emulator_manager/services/avd_metadata_reader.dart';
import 'package:eagly/features/emulator_manager/services/system_image_scanner.dart';
import 'package:eagly/services/tools/avd_manager_tool.dart';
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

class FakeEmulatorTool() extends EmulatorTool {
  this : super(executablePath: '/usr/bin/true');

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

class FakeAvdMetadataReader() extends AvdMetadataReader {
  // A path that cannot exist, so an unstubbed read is a visible mistake rather
  // than a silent trip through the developer's own ~/.android/avd.
  this : super(avdHome: '/nonexistent/avd/home');

  final Map<String, AndroidEmulator> emulators = {};

  @override
  Future<AndroidEmulator> read(String name) async =>
      emulators[name] ?? AndroidEmulator(name: name);
}

class FakeAvdManagerTool() extends AvdManagerTool {
  this : super(executablePath: '/usr/bin/true');

  List<DeviceProfile> profiles = const [];
  var listProfilesCallCount = 0;

  /// (name, packagePath, deviceProfileId) per create.
  final List<(String, String, String?)> createRequests = [];
  final List<String> deleteRequests = [];
  DeviceCommandResult createResult = DeviceCommandResult.success(
    message: 'Created it.',
  );
  DeviceCommandResult deleteResult = DeviceCommandResult.success(
    message: 'Deleted it.',
  );

  @override
  Future<List<DeviceProfile>> listDeviceProfiles() async {
    listProfilesCallCount++;
    return List.of(profiles);
  }

  @override
  Future<DeviceCommandResult> createAvd({
    required String name,
    required String packagePath,
    String? deviceProfileId,
    bool replaceExisting = false,
  }) async {
    createRequests.add((name, packagePath, deviceProfileId));
    return createResult;
  }

  @override
  Future<DeviceCommandResult> deleteAvd(String name) async {
    deleteRequests.add(name);
    return deleteResult;
  }
}

class FakeSystemImageScanner implements SystemImageScanner {
  List<SystemImage> images = const [];
  final List<String> scanRequests = [];

  @override
  Future<List<SystemImage>> scan(String sdkRoot) async {
    scanRequests.add(sdkRoot);
    return List.of(images);
  }
}

/// A phone image, the common case.
const fakePlayStoreImage = SystemImage(
  packagePath: 'system-images;android-34;google_apis_playstore;arm64-v8a',
  apiLevel: '34',
  tagId: 'google_apis_playstore',
  tagDisplay: 'Google Play',
  abi: 'arm64-v8a',
);

const fakeTvImage = SystemImage(
  packagePath: 'system-images;android-34;android-tv;arm64-v8a',
  apiLevel: '34',
  tagId: 'android-tv',
  tagDisplay: 'Android TV',
  abi: 'arm64-v8a',
);

const fakePixelProfile = DeviceProfile(
  id: 'pixel_7',
  name: 'Pixel 7',
  oem: 'Google',
);

const fakeTvProfile = DeviceProfile(
  id: 'tv_1080p',
  name: 'Television (1080p)',
  oem: 'Google',
  tag: 'android-tv',
);

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
