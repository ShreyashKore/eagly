import 'package:eagly/services/tools/avd_manager_tool.dart';
import 'package:eagly/services/tools/tool_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape `avdmanager list device` really prints, taken from a live SDK.
/// Note the two id spellings: a slug, and an older profile whose id is its
/// display name, spaces included.
const _deviceListing = '''
Available devices definitions:
id: 0 or "ai_glasses_displayless"
    Name: Audio Glasses
    OEM : Google
    Tag : ai-glasses
---------
id: 12 or "Galaxy Nexus"
    Name: Galaxy Nexus
    OEM : Google
---------
id: 28 or "pixel"
    Name: Pixel
    OEM : Google
---------
id: 44 or "pixel_7"
    Name: Pixel 7
    OEM : Google
---------
id: 90 or "wearos_small_round"
    Name: Wear OS Small Round
    OEM : Google
    Tag : android-wear
---------
''';

ToolCommandResult failure(String stderr) =>
    ToolCommandResult(exitCode: 1, stdout: '', stderr: stderr);

void main() {
  late AvdManagerTool tool;

  setUp(() {
    tool = AvdManagerTool(executablePath: '/usr/bin/true');
  });

  group('parseDeviceProfiles', () {
    test('reads every profile in the listing', () {
      final profiles = tool.parseDeviceProfiles(_deviceListing);

      expect(profiles.map((profile) => profile.id), [
        'ai_glasses_displayless',
        'Galaxy Nexus',
        'pixel',
        'pixel_7',
        'wearos_small_round',
      ]);
    });

    test('keeps an id that contains spaces intact', () {
      final profiles = tool.parseDeviceProfiles(_deviceListing);

      expect(
        profiles[1].id,
        'Galaxy Nexus',
        reason:
            'that string is passed to -d as a single argument, never '
            'through a shell',
      );
      expect(profiles[1].name, 'Galaxy Nexus');
    });

    test('a profile with no Tag is a phone or tablet', () {
      final profiles = tool.parseDeviceProfiles(_deviceListing);
      final pixel = profiles.firstWhere((profile) => profile.id == 'pixel_7');

      expect(pixel.tag, isNull);
      expect(pixel.isHandheld, isTrue);
      expect(pixel.label, 'Pixel 7 · Google');
    });

    test('a tagged profile keeps its device class', () {
      final profiles = tool.parseDeviceProfiles(_deviceListing);
      final wear = profiles.last;

      expect(wear.tag, 'android-wear');
      expect(wear.isHandheld, isFalse);
    });

    test('empty output yields no profiles rather than a broken one', () {
      expect(tool.parseDeviceProfiles(''), isEmpty);
      expect(
        tool.parseDeviceProfiles('Available devices definitions:'),
        isEmpty,
      );
    });
  });

  group('buildCreateArguments', () {
    test('passes the name, package and profile', () {
      expect(
        tool.buildCreateArguments(
          name: 'Pixel_7_API_34',
          packagePath:
              'system-images;android-34;google_apis_playstore;arm64-v8a',
          deviceProfileId: 'pixel_7',
        ),
        [
          'create',
          'avd',
          '-n',
          'Pixel_7_API_34',
          '-k',
          'system-images;android-34;google_apis_playstore;arm64-v8a',
          '-d',
          'pixel_7',
        ],
      );
    });

    test('omits -d when there is no profile', () {
      final arguments = tool.buildCreateArguments(
        name: 'Bare',
        packagePath: 'system-images;android-34;google_apis;arm64-v8a',
      );

      expect(arguments, isNot(contains('-d')));
    });

    test('--force only when replacing', () {
      expect(
        tool.buildCreateArguments(
          name: 'A',
          packagePath: 'p',
          replaceExisting: true,
        ),
        contains('--force'),
      );
      expect(
        tool.buildCreateArguments(name: 'A', packagePath: 'p'),
        isNot(contains('--force')),
      );
    });
  });

  group('describeInvalidName', () {
    test('accepts the alphabet avdmanager accepts', () {
      expect(AvdManagerTool.describeInvalidName('Pixel_7-API.34'), isNull);
    });

    test('rejects a name with a space', () {
      expect(
        AvdManagerTool.describeInvalidName('Pixel 7'),
        contains('no spaces'),
      );
    });

    test('rejects an empty name', () {
      expect(
        AvdManagerTool.describeInvalidName('   '),
        contains('Enter a name'),
      );
    });

    test('rejects characters avdmanager cannot address', () {
      expect(AvdManagerTool.describeInvalidName('naïve/avd'), isNotNull);
    });
  });

  group('describeFailure', () {
    test('lifts the reason out of the Error line', () {
      final result = failure(
        "Error: Android Virtual Device 'Pixel_7a' already exists.\n"
        'Use --force if you want to replace it.\n'
        'null\n',
      );

      expect(
        AvdManagerTool.describeFailure(result, 'fallback'),
        "Android Virtual Device 'Pixel_7a' already exists.",
      );
    });

    test('drops the literal null avdmanager prints after an error', () {
      final result = failure('null\n');

      expect(
        AvdManagerTool.describeFailure(result, 'Could not create it.'),
        'Could not create it.',
        reason:
            'avdmanager prints its exception message, which is often the '
            'text "null" — passing that on is worse than saying nothing',
      );
    });

    test('falls back to the last real line when there is no Error line', () {
      final result = failure('something went sideways\n');

      expect(
        AvdManagerTool.describeFailure(result, 'fallback'),
        'something went sideways',
      );
    });

    test('uses the fallback when the tool said nothing at all', () {
      expect(
        AvdManagerTool.describeFailure(failure(''), 'Could not delete X.'),
        'Could not delete X.',
      );
    });
  });

  group('guards before spending a JVM start', () {
    test('an invalid name never reaches the process', () async {
      final result = await tool.createAvd(
        name: 'has spaces',
        packagePath: 'system-images;android-34;google_apis;arm64-v8a',
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('no spaces'));
    });

    test('deleting by an invalid name is refused too', () async {
      final result = await tool.deleteAvd('');

      expect(result.isSuccess, isFalse);
    });
  });
}
