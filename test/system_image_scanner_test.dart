import 'dart:io';

import 'package:eagly/features/emulator_manager/data/system_image.dart';
import 'package:eagly/features/emulator_manager/services/system_image_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

/// A trimmed copy of a real `source.properties`, from
/// `system-images/android-36.1/google_apis_playstore/arm64-v8a`.
const _playStoreProperties = '''
Pkg.Desc=System Image arm64-v8a with Google Play.
Pkg.Revision=4
Pkg.Dependencies=emulator#35.4.9
AndroidVersion.ApiLevel=36.1
AndroidVersion.ExtensionLevel=20
AndroidVersion.IsBaseSdk=true
SystemImage.Abi=arm64-v8a
SystemImage.TagId=google_apis_playstore
SystemImage.TagDisplay=Google Play
SystemImage.GpuSupport=true
Addon.VendorId=google
Addon.VendorDisplay=Google Inc.
''';

const _googleApisProperties = '''
Pkg.Desc=System Image arm64-v8a with Google APIs.
Pkg.Revision=16
AndroidVersion.ApiLevel=30
SystemImage.Abi=arm64-v8a
SystemImage.TagId=google_apis
SystemImage.TagDisplay=Google APIs
Addon.VendorDisplay=Google Inc.
''';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('system-image-scanner');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  void writeImage(String api, String tag, String abi, String? properties) {
    final dir = Directory('${tempDir.path}/system-images/$api/$tag/$abi')
      ..createSync(recursive: true);
    if (properties != null) {
      File('${dir.path}/source.properties').writeAsStringSync(properties);
    }
  }

  group('parseProperties', () {
    test('reads key=value lines and ignores the rest', () {
      final values = SystemImageScanner.parseProperties(_playStoreProperties);

      expect(values['AndroidVersion.ApiLevel'], '36.1');
      expect(values['SystemImage.TagId'], 'google_apis_playstore');
      expect(values['SystemImage.TagDisplay'], 'Google Play');
      expect(values['SystemImage.Abi'], 'arm64-v8a');
    });

    test('a value containing = keeps all of it', () {
      final values = SystemImageScanner.parseProperties('Pkg.Desc=a=b=c');

      expect(values['Pkg.Desc'], 'a=b=c');
    });

    test('blank lines and comments are skipped', () {
      final values = SystemImageScanner.parseProperties(
        '# a comment\n\nPkg.Revision=4\n',
      );

      expect(values, {'Pkg.Revision': '4'});
    });
  });

  group('buildImage', () {
    test('assembles the package path from the directory names', () {
      final image = SystemImageScanner.buildImage(
        properties: SystemImageScanner.parseProperties(_playStoreProperties),
        apiSegment: 'android-36.1',
        tagSegment: 'google_apis_playstore',
        abiSegment: 'arm64-v8a',
      );

      expect(
        image.packagePath,
        'system-images;android-36.1;google_apis_playstore;arm64-v8a',
        reason: 'this is the string avdmanager -k takes',
      );
      expect(image.apiLevel, '36.1');
      expect(image.tagDisplay, 'Google Play');
      expect(image.hasPlayStore, isTrue);
      expect(image.isHandheld, isTrue);
      expect(image.label, 'API 36.1 · Google Play · arm64-v8a');
    });

    test('falls back to the directory names when properties are thin', () {
      final image = SystemImageScanner.buildImage(
        properties: const {},
        apiSegment: 'android-33',
        tagSegment: 'default',
        abiSegment: 'x86_64',
      );

      expect(image.apiLevel, '33');
      expect(image.tagId, 'default');
      expect(image.tagDisplay, 'default');
      expect(image.abi, 'x86_64');
    });

    test('a device-class image is not offered a phone profile', () {
      final image = SystemImageScanner.buildImage(
        properties: const {
          'SystemImage.TagId': 'android-tv',
          'SystemImage.TagDisplay': 'Android TV',
        },
        apiSegment: 'android-34',
        tagSegment: 'android-tv',
        abiSegment: 'arm64-v8a',
      );

      expect(image.isHandheld, isFalse);
    });

    test('an unrecognised tag is treated as a phone image', () {
      final image = SystemImageScanner.buildImage(
        properties: const {'SystemImage.TagId': 'google_apis_ps16k'},
        apiSegment: 'android-36',
        tagSegment: 'google_apis_ps16k',
        abiSegment: 'arm64-v8a',
      );

      expect(
        image.isHandheld,
        isTrue,
        reason:
            'a new API flavour lands with the phones, which is where a '
            'new tag almost always belongs',
      );
    });
  });

  group('scan', () {
    test('finds every installed image, newest API first', () async {
      writeImage(
        'android-30',
        'google_apis',
        'arm64-v8a',
        _googleApisProperties,
      );
      writeImage(
        'android-36.1',
        'google_apis_playstore',
        'arm64-v8a',
        _playStoreProperties,
      );
      writeImage(
        'android-35',
        'google_apis',
        'arm64-v8a',
        _googleApisProperties,
      );

      final images = await const SystemImageScanner().scan(tempDir.path);

      expect(images, hasLength(3));
      expect(
        images.map((image) => image.packagePath).first,
        'system-images;android-36.1;google_apis_playstore;arm64-v8a',
      );
    });

    test('36.1 sorts above 36, and 9 below 35', () {
      SystemImage image(String api) => SystemImage(
        packagePath: 'system-images;android-$api;google_apis;arm64-v8a',
        apiLevel: api,
        tagId: 'google_apis',
        tagDisplay: 'Google APIs',
        abi: 'arm64-v8a',
      );

      final images = [image('9'), image('36'), image('35'), image('36.1')]
        ..sort(SystemImageScanner.compareImages);

      expect(images.map((i) => i.apiLevel), [
        '36.1',
        '36',
        '35',
        '9',
      ], reason: 'a string compare would put android-9 at the top');
    });

    test('a directory with no source.properties is not an image', () async {
      writeImage('android-34', 'google_apis', 'arm64-v8a', null);

      expect(
        await const SystemImageScanner().scan(tempDir.path),
        isEmpty,
        reason: 'a partial download would fail at launch, so it is not offered',
      );
    });

    test('an SDK with no system-images tree scans clean', () async {
      expect(await const SystemImageScanner().scan(tempDir.path), isEmpty);
    });

    test('a path that does not exist scans clean', () async {
      expect(
        await const SystemImageScanner().scan('${tempDir.path}/nope'),
        isEmpty,
      );
    });
  });
}
