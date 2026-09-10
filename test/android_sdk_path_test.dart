import 'dart:io';

import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/utils/android_sdk_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds a plausible SDK tree under [root]. [withEmulator] mirrors an SDK
/// whose emulator package was never installed.
void _createSdk(
  String root, {
  bool withEmulator = true,
  String? cmdlineToolsVersion = 'latest',
  bool legacyTools = false,
}) {
  Directory('$root/platform-tools').createSync(recursive: true);

  if (withEmulator) {
    final emulator = Directory('$root/emulator')..createSync(recursive: true);
    File('${emulator.path}/${_executable('emulator')}').createSync();
  }

  if (cmdlineToolsVersion != null) {
    final bin = Directory('$root/cmdline-tools/$cmdlineToolsVersion/bin')
      ..createSync(recursive: true);
    File('${bin.path}/${_avdManager()}').createSync();
  }

  if (legacyTools) {
    final bin = Directory('$root/tools/bin')..createSync(recursive: true);
    File('${bin.path}/${_avdManager()}').createSync();
  }
}

String _executable(String name) => Platform.isWindows ? '$name.exe' : name;

String _avdManager() => Platform.isWindows ? 'avdmanager.bat' : 'avdmanager';

void main() {
  late Directory temp;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
    temp = await Directory.systemTemp.createTemp('eagly-sdk-test');
    // Empty by default so nothing leaks in from the machine running the test.
    AndroidSdkPath.environment = const {};
  });

  tearDown(() async {
    AndroidSdkPath.resetEnvironment();
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  group('resolveSdkRoot', () {
    test('finds nothing when no candidate exists', () {
      expect(AndroidSdkPath.resolveSdkRoot(), isNull);
      expect(AndroidSdkPath.locate().status, AndroidSdkStatus.sdkMissing);
    });

    test('the configured path wins over the environment', () async {
      final configured = '${temp.path}/configured';
      final fromEnv = '${temp.path}/from-env';
      _createSdk(configured);
      _createSdk(fromEnv);
      AndroidSdkPath.environment = {'ANDROID_HOME': fromEnv};
      await PreferencesService.setAndroidSdkPath(configured);

      expect(AndroidSdkPath.resolveSdkRoot(), configured);
    });

    test('ANDROID_HOME wins over ANDROID_SDK_ROOT', () {
      final home = '${temp.path}/home';
      final root = '${temp.path}/root';
      _createSdk(home);
      _createSdk(root);
      AndroidSdkPath.environment = {
        'ANDROID_HOME': home,
        'ANDROID_SDK_ROOT': root,
      };

      expect(AndroidSdkPath.resolveSdkRoot(), home);
    });

    test('skips a configured path that is not an SDK', () async {
      final notAnSdk = Directory('${temp.path}/empty')..createSync();
      final real = '${temp.path}/real';
      _createSdk(real);
      await PreferencesService.setAndroidSdkPath(notAnSdk.path);
      AndroidSdkPath.environment = {'ANDROID_SDK_ROOT': real};

      expect(AndroidSdkPath.resolveSdkRoot(), real);
    });

    test(
      'a trailing separator does not create a duplicate candidate',
      () async {
        final sdk = '${temp.path}/sdk';
        _createSdk(sdk);
        await PreferencesService.setAndroidSdkPath(
          '$sdk${Platform.pathSeparator}',
        );
        AndroidSdkPath.environment = {'ANDROID_HOME': sdk};

        expect(
          AndroidSdkPath.candidateSdkRoots()
              .where((path) => path == sdk)
              .length,
          1,
        );
      },
    );
  });

  group('locate', () {
    test('reports a usable SDK', () async {
      final sdk = '${temp.path}/sdk';
      _createSdk(sdk);
      await PreferencesService.setAndroidSdkPath(sdk);

      final location = AndroidSdkPath.locate();

      expect(location.status, AndroidSdkStatus.ready);
      expect(location.isReady, isTrue);
      expect(location.canManageAvds, isTrue);
      expect(location.sdkPath, sdk);
      expect(location.emulatorExecutable, contains('emulator'));
    });

    test(
      'an SDK without the emulator package is distinguished from no SDK',
      () async {
        final sdk = '${temp.path}/sdk';
        _createSdk(sdk, withEmulator: false);
        await PreferencesService.setAndroidSdkPath(sdk);

        final location = AndroidSdkPath.locate();

        expect(location.status, AndroidSdkStatus.emulatorMissing);
        expect(location.sdkPath, sdk);
        expect(location.emulatorExecutable, isNull);
        // Listing/launching is off, but avdmanager was still found.
        expect(location.avdManagerExecutable, isNotNull);
        expect(location.canManageAvds, isFalse);
      },
    );

    test(
      'missing cmdline-tools disables management but not launching',
      () async {
        final sdk = '${temp.path}/sdk';
        _createSdk(sdk, cmdlineToolsVersion: null);
        await PreferencesService.setAndroidSdkPath(sdk);

        final location = AndroidSdkPath.locate();

        expect(location.isReady, isTrue);
        expect(location.avdManagerExecutable, isNull);
        expect(location.canManageAvds, isFalse);
      },
    );

    test('falls back to a versioned cmdline-tools install', () async {
      final sdk = '${temp.path}/sdk';
      _createSdk(sdk, cmdlineToolsVersion: '13.0');
      await PreferencesService.setAndroidSdkPath(sdk);

      expect(AndroidSdkPath.locate().avdManagerExecutable, contains('13.0'));
    });

    test('falls back to the pre-2021 tools/bin location', () async {
      final sdk = '${temp.path}/sdk';
      _createSdk(sdk, cmdlineToolsVersion: null, legacyTools: true);
      await PreferencesService.setAndroidSdkPath(sdk);

      expect(AndroidSdkPath.locate().avdManagerExecutable, contains('tools'));
    });
  });

  group('avdHome', () {
    test('ANDROID_AVD_HOME is used verbatim', () {
      AndroidSdkPath.environment = {'ANDROID_AVD_HOME': '/avds'};
      expect(AndroidSdkPath.avdHome(), '/avds');
    });

    test('ANDROID_USER_HOME gets an avd suffix', () {
      AndroidSdkPath.environment = {'ANDROID_USER_HOME': '/user-home'};
      expect(
        AndroidSdkPath.avdHome(),
        ['/user-home', 'avd'].join(Platform.pathSeparator),
      );
    });

    test('ANDROID_SDK_HOME keeps the legacy .android/avd layout', () {
      AndroidSdkPath.environment = {'ANDROID_SDK_HOME': '/legacy'};
      expect(
        AndroidSdkPath.avdHome(),
        ['/legacy', '.android', 'avd'].join(Platform.pathSeparator),
      );
    });

    test('falls back to the home directory', () {
      AndroidSdkPath.environment = {'HOME': '/users/dev'};
      expect(
        AndroidSdkPath.avdHome(),
        ['/users/dev', '.android', 'avd'].join(Platform.pathSeparator),
      );
    });

    test('is null when the environment has no home at all', () {
      expect(AndroidSdkPath.avdHome(), isNull);
    });
  });
}
