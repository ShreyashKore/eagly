import 'dart:io';

import 'package:eagly/features/emulator_manager/services/avd_metadata_reader.dart';
import 'package:eagly/utils/android_sdk_path.dart';
import 'package:flutter_test/flutter_test.dart';

/// A trimmed copy of a real `config.ini` written by the AVD Manager.
const _pixel7aConfig = '''
AvdId=Pixel_7a
PlayStore.enabled=true
abi.type=arm64-v8a
avd.ini.displayname=Pixel 7a
avd.ini.encoding=UTF-8
hw.device.manufacturer=Google
hw.device.name=pixel_7a
hw.lcd.density=420
hw.lcd.height=2400
hw.lcd.width=1080
hw.ramSize=2048
image.sysdir.1=system-images/android-36.1/google_apis_playstore/arm64-v8a/
skin.name=pixel_7a
tag.display=Google Play
tag.id=google_apis_playstore
target=android-36.1
''';

void main() {
  late Directory avdHome;

  setUp(() async {
    avdHome = await Directory.systemTemp.createTemp('eagly-avd-test');
    // Blank so no test can reach the real `~/.android/avd` of the machine
    // running the suite.
    AndroidSdkPath.environment = const {};
  });

  tearDown(() async {
    AndroidSdkPath.resetEnvironment();
    if (avdHome.existsSync()) await avdHome.delete(recursive: true);
  });

  /// Writes `<name>.ini` plus `<name>.avd/config.ini` under [avdHome].
  void writeAvd(
    String name, {
    String config = _pixel7aConfig,
    String? pointerTarget = 'android-36.1',
    Directory? at,
  }) {
    final directory = at ?? Directory('${avdHome.path}/$name.avd');
    directory.createSync(recursive: true);
    File('${directory.path}/config.ini').writeAsStringSync(config);

    File('${avdHome.path}/$name.ini').writeAsStringSync(
      'avd.ini.encoding=UTF-8\n'
      'path=${directory.path}\n'
      'path.rel=avd/$name.avd\n'
      '${pointerTarget == null ? '' : 'target=$pointerTarget\n'}',
    );
  }

  group('parseIni', () {
    test('reads key=value pairs and ignores comments and blanks', () {
      final parsed = AvdMetadataReader.parseIni(
        '# a comment\n'
        '\n'
        'hw.ramSize=2048\n'
        '  tag.display = Google Play  \n',
      );

      expect(parsed, {'hw.ramSize': '2048', 'tag.display': 'Google Play'});
    });

    test('splits on the first = so paths survive intact', () {
      final parsed = AvdMetadataReader.parseIni(
        'skin.path=/opt/sdk/skins/pixel=7\n',
      );

      expect(parsed['skin.path'], '/opt/sdk/skins/pixel=7');
    });

    test('drops lines that are not assignments', () {
      final parsed = AvdMetadataReader.parseIni('garbage\n=novalue\n');
      expect(parsed, isEmpty);
    });
  });

  group('read', () {
    test('maps a real config onto the model', () async {
      writeAvd('Pixel_7a');

      final emulator = await AvdMetadataReader(
        avdHome: avdHome.path,
      ).read('Pixel_7a');

      expect(emulator.name, 'Pixel_7a');
      expect(emulator.displayName, 'Pixel 7a');
      expect(emulator.label, 'Pixel 7a');
      expect(emulator.deviceProfile, 'pixel_7a');
      expect(emulator.manufacturer, 'Google');
      expect(emulator.apiLevel, '36.1');
      expect(emulator.tagDisplay, 'Google Play');
      expect(emulator.abi, 'arm64-v8a');
      expect(emulator.ramMb, 2048);
      expect(emulator.resolution, '1080 × 2400');
      expect(emulator.densityDpi, 420);
      expect(emulator.hasPlayStore, isTrue);
      expect(emulator.avdPath, endsWith('Pixel_7a.avd'));
      expect(emulator.summary, 'API 36.1 · Google Play · arm64-v8a');
      expect(emulator.isMetadataMissing, isFalse);
    });

    test('follows path= to an AVD stored outside the AVD home', () async {
      final elsewhere = await Directory.systemTemp.createTemp('eagly-avd-alt');
      addTearDown(() => elsewhere.delete(recursive: true));
      writeAvd('Pixel_7a', at: elsewhere);

      final emulator = await AvdMetadataReader(
        avdHome: avdHome.path,
      ).read('Pixel_7a');

      expect(emulator.avdPath, elsewhere.path);
      expect(emulator.apiLevel, '36.1');
    });

    test('falls back to <name>.avd when path= points nowhere', () async {
      writeAvd('Pixel_7a');
      File(
        '${avdHome.path}/Pixel_7a.ini',
      ).writeAsStringSync('path=/definitely/not/here\n');

      final emulator = await AvdMetadataReader(
        avdHome: avdHome.path,
      ).read('Pixel_7a');

      expect(emulator.avdPath, endsWith('Pixel_7a.avd'));
      expect(emulator.abi, 'arm64-v8a');
    });

    test('a listed AVD with no files on disk is still returned', () async {
      final emulator = await AvdMetadataReader(
        avdHome: avdHome.path,
      ).read('Ghost_AVD');

      expect(emulator.name, 'Ghost_AVD');
      expect(emulator.isMetadataMissing, isTrue);
      expect(emulator.label, 'Ghost AVD');
      expect(emulator.summary, isEmpty);
    });

    test(
      'takes target from the pointer file when config.ini lacks it',
      () async {
        writeAvd('Pixel_7a', config: 'abi.type=arm64-v8a\n');

        final emulator = await AvdMetadataReader(
          avdHome: avdHome.path,
        ).read('Pixel_7a');

        expect(emulator.apiLevel, '36.1');
      },
    );

    test('ignores an add-on target it cannot read as an API level', () async {
      writeAvd(
        'Old_AVD',
        config: 'target=Google Inc.:Google APIs:24\n',
        pointerTarget: null,
      );

      final emulator = await AvdMetadataReader(
        avdHome: avdHome.path,
      ).read('Old_AVD');

      expect(emulator.apiLevel, isNull);
    });

    test('reads a RAM size written with a unit suffix', () {
      final emulator = AvdMetadataReader.buildEmulator(
        name: 'X',
        config: const {'hw.ramSize': '1536M'},
      );

      expect(emulator.ramMb, 1536);
    });

    test('is null-safe when no AVD home can be resolved', () async {
      final emulator = await AvdMetadataReader(avdHome: null).read('Pixel_7a');
      expect(emulator.name, 'Pixel_7a');
      expect(emulator.isMetadataMissing, isTrue);
    });

    test('readAll preserves the order it was given', () async {
      writeAvd('A');
      writeAvd('B');

      final emulators = await AvdMetadataReader(
        avdHome: avdHome.path,
      ).readAll(['B', 'A']);

      expect(emulators.map((e) => e.name), ['B', 'A']);
    });
  });
}
