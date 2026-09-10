import 'dart:io';

import 'package:eagly/features/emulator_manager/services/android_sdk_picker.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/utils/android_sdk_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
    tempDir = Directory.systemTemp.createTempSync('android-sdk-picker');
  });

  tearDown(() {
    AndroidSdkPicker.resetChooseDirectory();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  String createSdk({bool withEmulator = true}) {
    final root = '${tempDir.path}/sdk';
    Directory('$root/platform-tools').createSync(recursive: true);
    if (withEmulator) {
      final emulator = Directory('$root/emulator')..createSync(recursive: true);
      File(
        '${emulator.path}/${Platform.isWindows ? 'emulator.exe' : 'emulator'}',
      ).createSync();
    }
    return root;
  }

  group('evaluate', () {
    test('accepts an SDK that can launch emulators', () {
      final root = createSdk();

      final choice = AndroidSdkPicker.evaluate(root);

      expect(choice.accepted, isTrue);
      expect(choice.path, root);
      expect(choice.message, contains(root));
    });

    test('accepts an SDK missing only the emulator package', () {
      final root = createSdk(withEmulator: false);

      final choice = AndroidSdkPicker.evaluate(root);

      expect(
        choice.accepted,
        isTrue,
        reason:
            'it is the right folder, just an incomplete install — saying '
            '"wrong folder" would send the user hunting for one they have',
      );
      expect(choice.message, contains('no emulator package'));
      expect(choice.message, contains('SDK Manager'));
    });

    test('refuses a folder with nothing an SDK would hold', () {
      final elsewhere = '${tempDir.path}/Documents';
      Directory(elsewhere).createSync(recursive: true);

      final choice = AndroidSdkPicker.evaluate(elsewhere);

      expect(choice.accepted, isFalse);
      expect(choice.message, contains('does not look like an Android SDK'));
      expect(choice.message, contains('platform-tools'));
    });

    test('refuses a folder that does not exist', () {
      final choice = AndroidSdkPicker.evaluate('${tempDir.path}/nope');

      expect(choice.accepted, isFalse);
    });
  });

  group('chooseAndSave', () {
    test('remembers an accepted folder', () async {
      final root = createSdk();
      AndroidSdkPicker.chooseDirectory = ({String? initialDirectory}) async =>
          root;

      final choice = await AndroidSdkPicker.chooseAndSave();

      expect(choice!.accepted, isTrue);
      expect(PreferencesService.androidSdkPath, root);
    });

    test('an incomplete SDK is still remembered', () async {
      final root = createSdk(withEmulator: false);
      AndroidSdkPicker.chooseDirectory = ({String? initialDirectory}) async =>
          root;

      await AndroidSdkPicker.chooseAndSave();

      expect(PreferencesService.androidSdkPath, root);
    });

    test('a refused folder is not remembered', () async {
      AndroidSdkPicker.chooseDirectory = ({String? initialDirectory}) async =>
          tempDir.path;

      final choice = await AndroidSdkPicker.chooseAndSave();

      expect(choice!.accepted, isFalse);
      expect(PreferencesService.androidSdkPath, isNull);
    });

    test('cancelling says nothing and changes nothing', () async {
      await PreferencesService.setAndroidSdkPath(createSdk());
      AndroidSdkPicker.chooseDirectory = ({String? initialDirectory}) async =>
          null;

      final choice = await AndroidSdkPicker.chooseAndSave();

      expect(
        choice,
        isNull,
        reason: 'a cancel is not a rejection and must not be reported as one',
      );
      expect(PreferencesService.androidSdkPath, isNotNull);
    });

    test('a blank pick counts as a cancel', () async {
      AndroidSdkPicker.chooseDirectory = ({String? initialDirectory}) async =>
          '   ';

      expect(await AndroidSdkPicker.chooseAndSave(), isNull);
      expect(PreferencesService.androidSdkPath, isNull);
    });

    test('the saved override wins when the SDK is located again', () async {
      final root = createSdk();
      AndroidSdkPicker.chooseDirectory = ({String? initialDirectory}) async =>
          root;
      AndroidSdkPath.environment = const {'ANDROID_HOME': '/somewhere/else'};
      addTearDown(AndroidSdkPath.resetEnvironment);

      await AndroidSdkPicker.chooseAndSave();

      expect(AndroidSdkPath.locate().sdkPath, root);
      expect(AndroidSdkPath.locate().isReady, isTrue);
    });
  });

  test('clear falls back to the environment again', () async {
    final root = createSdk();
    await PreferencesService.setAndroidSdkPath(root);
    expect(AndroidSdkPath.resolveSdkRoot(), root);

    await AndroidSdkPicker.clear();

    expect(PreferencesService.androidSdkPath, isNull);
    expect(AndroidSdkPath.candidateSdkRoots(), isNot(contains(root)));
  });
}
