import 'package:eagly/services/tools/ideviceinstaller_tool.dart';
import 'package:eagly/services/tools/tool_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stubs the process boundary by overriding [runText] (a regular, overridable
/// instance method) so [IdeviceInstallerTool]'s real parsing runs against
/// canned `ideviceinstaller` output.
class _FakeIdeviceInstallerTool extends IdeviceInstallerTool {
  _FakeIdeviceInstallerTool(this.stdout)
    : super(executablePath: '/usr/bin/true');

  final String stdout;

  @override
  Future<ToolCommandResult> runText(List<String> arguments) async {
    return ToolCommandResult(exitCode: 0, stdout: stdout, stderr: '');
  }
}

/// Simulates a real `ideviceinstaller` binary of one CLI generation: it
/// rejects the *other* generation's arguments the way the real tools do
/// (option parsing fails long before the device is touched).
class _CliGenerationFake extends IdeviceInstallerTool {
  _CliGenerationFake({required this.legacyBinary, this.stdout = ''})
    : super(executablePath: '/usr/bin/true');

  final bool legacyBinary;
  final String stdout;
  final calls = <List<String>>[];

  @override
  Future<ToolCommandResult> runText(List<String> arguments) async {
    calls.add(arguments);
    final usesSubcommands = arguments.any(
      (a) => const {'install', 'uninstall', 'list'}.contains(a),
    );

    if (legacyBinary && usesSubcommands) {
      return const ToolCommandResult(
        exitCode: 1,
        stdout: '',
        stderr:
            'ERROR: No mode/command was supplied.\n'
            'Usage: ideviceinstaller OPTIONS',
      );
    }
    if (!legacyBinary && !usesSubcommands) {
      return const ToolCommandResult(
        exitCode: 1,
        stdout: '',
        stderr:
            'ideviceinstaller: invalid option -- i\n'
            'Usage: ideviceinstaller OPTIONS',
      );
    }
    return ToolCommandResult(exitCode: 0, stdout: stdout, stderr: '');
  }
}

void main() {
  // Reproduces two real-world quirks seen on a real device dump:
  //  - Truecaller's CFBundleDisplayName is declared *before* its
  //    CFBundleIdentifier (plist key order isn't guaranteed).
  //  - Its dict also nests other dicts (a stand-in for entitlements/group
  //    containers), including one that declares its own CFBundleIdentifier —
  //    that must never be mistaken for the real, top-level one.
  const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<array>
	<dict>
		<key>SomeExtension</key>
		<dict>
			<key>CFBundleIdentifier</key>
			<string>should.not.be.picked.up</string>
		</dict>
		<key>CFBundleDisplayName</key>
		<string>Truecaller</string>
		<key>EnvironmentVariables</key>
		<dict>
			<key>HOME</key>
			<string>/private/var/mobile</string>
		</dict>
		<key>CFBundleIdentifier</key>
		<string>com.truesoftware.TrueCallerOther</string>
		<key>CFBundleShortVersionString</key>
		<string>26.30.5</string>
	</dict>
	<dict>
		<key>CFBundleIdentifier</key>
		<string>com.amazon.AmazonIN</string>
		<key>CFBundleShortVersionString</key>
		<string>876082.0</string>
		<key>CFBundleDisplayName</key>
		<string>Amazon</string>
	</dict>
</array>
</plist>
''';

  test(
    'listAllApps parses out-of-order fields and ignores nested dicts',
    () async {
      final tool = _FakeIdeviceInstallerTool(xml);

      final apps = await tool.listAllApps('udid');

      expect(apps.map((a) => a.packageName), [
        'com.amazon.AmazonIN',
        'com.truesoftware.TrueCallerOther',
      ]);
      expect(
        apps.any((a) => a.packageName == 'should.not.be.picked.up'),
        isFalse,
      );

      final truecaller = apps.firstWhere(
        (a) => a.packageName == 'com.truesoftware.TrueCallerOther',
      );
      expect(truecaller.appName, 'Truecaller');
      expect(truecaller.versionName, '26.30.5');

      final amazon = apps.firstWhere(
        (a) => a.packageName == 'com.amazon.AmazonIN',
      );
      expect(amazon.appName, 'Amazon');
      expect(amazon.versionName, '876082.0');
    },
  );

  test('listAllApps requests xml output (plain -l is unparseable)', () async {
    // The default (no -o xml) output is a terse CSV table with no <key>
    // tags at all — the earlier bug that made every iOS app disappear.
    const csvOutput =
        'CFBundleIdentifier, CFBundleVersion, CFBundleDisplayName\n'
        'com.amazon.AmazonIN, "876082.0", "Amazon"\n';
    final tool = _FakeIdeviceInstallerTool(csvOutput);

    final apps = await tool.listAllApps('udid');

    expect(apps, isEmpty);
  });

  test('listInstalledApps caps at 5 and maps to the lighter model', () async {
    final tool = _FakeIdeviceInstallerTool(xml);

    final apps = await tool.listInstalledApps('udid');

    // Unsorted (document order), matching listAllApps' pre-sort order.
    expect(apps, hasLength(2));
    expect(apps.map((a) => a.packageName), [
      'com.truesoftware.TrueCallerOther',
      'com.amazon.AmazonIN',
    ]);
  });

  group('CLI generation', () {
    test('installs with subcommands on a 1.1.1+ binary', () async {
      final tool = _CliGenerationFake(legacyBinary: false);

      final result = await tool.installApp(deviceId: 'udid', appPath: '/a.ipa');

      expect(result.isSuccess, isTrue);
      expect(tool.calls, [
        ['-u', 'udid', 'install', '/a.ipa'],
      ]);
    });

    test(
      'retries with the legacy flags when subcommands are rejected',
      () async {
        final tool = _CliGenerationFake(legacyBinary: true);

        final result = await tool.installApp(
          deviceId: 'udid',
          appPath: '/a.ipa',
        );

        expect(result.isSuccess, isTrue);
        expect(tool.calls, [
          ['-u', 'udid', 'install', '/a.ipa'],
          ['-u', 'udid', '-i', '/a.ipa'],
        ]);
      },
    );

    test('remembers the working dialect for later commands', () async {
      final tool = _CliGenerationFake(legacyBinary: true);

      await tool.installApp(deviceId: 'udid', appPath: '/a.ipa');
      tool.calls.clear();
      final result = await tool.uninstallApp(
        deviceId: 'udid',
        bundleId: 'com.example.app',
      );

      expect(result.isSuccess, isTrue);
      expect(tool.calls, [
        ['-u', 'udid', '-U', 'com.example.app'],
      ]);
    });

    test('lists apps as xml on either generation', () async {
      final modern = _CliGenerationFake(legacyBinary: false, stdout: xml);
      final legacy = _CliGenerationFake(legacyBinary: true, stdout: xml);

      expect(await modern.listAllApps('udid'), hasLength(2));
      expect(await legacy.listAllApps('udid'), hasLength(2));
      expect(modern.calls.single, ['-u', 'udid', 'list', '--xml']);
      expect(legacy.calls.last, ['-u', 'udid', '-l', '-o', 'xml']);
    });
  });
}
