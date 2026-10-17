import 'dart:io';

import 'package:eagly/features/app_log/app_logger.dart';
import 'package:eagly/features/emulator_manager/data/emulator_launch_options.dart';
import 'package:eagly/services/tools/adb_tool.dart';
import 'package:eagly/services/tools/emulator_tool.dart';
import 'package:eagly/services/tools/tool_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what [launch] would have spawned instead of spawning it, so the
/// argument list can be asserted without an SDK present.
class _RecordingEmulatorTool extends EmulatorTool {
  _RecordingEmulatorTool() : super(executablePath: '/usr/bin/true');

  final List<List<String>> started = [];

  @override
  Future<Process> startProcess(
    List<String> arguments, {
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    started.add(arguments);
    return super.startProcess(arguments, mode: mode);
  }
}

ToolCommandResult _ok(String stdout) =>
    ToolCommandResult(exitCode: 0, stdout: stdout, stderr: '');

void main() {
  late EmulatorTool tool;
  late AdbTool adb;

  setUp(() {
    AppLogger.global.clear();
    tool = EmulatorTool(executablePath: '/usr/bin/true');
    adb = AdbTool(executablePath: '/usr/bin/true');
  });

  group('parseAvdNames', () {
    test('reads one name per line from stdout', () {
      // Verbatim shape of a real `emulator -list-avds` run.
      final names = tool.parseAvdNames(
        _ok('Pixel_4\nPixel_7_Pro\nSmall_Phone\n'),
      );

      expect(names, ['Pixel_4', 'Pixel_7_Pro', 'Small_Phone']);
      expect(AppLogger.global.entriesWhere(), isEmpty);
    });

    test('drops log lines a chatty build might interleave', () {
      final names = tool.parseAvdNames(
        _ok(
          'INFO         | Android emulator version 37.1.11.0\n'
          'Pixel_7a\n'
          'ERROR        | Unknown something\n',
        ),
      );

      expect(names, ['Pixel_7a']);
    });

    test('an empty SDK lists nothing without complaining', () {
      expect(tool.parseAvdNames(_ok('\n')), isEmpty);
      expect(AppLogger.global.entriesWhere(), isEmpty);
    });

    test('a failed run warns and yields nothing', () {
      final names = tool.parseAvdNames(
        const ToolCommandResult(
          exitCode: 1,
          stdout: '',
          stderr: 'PANIC: broken SDK',
        ),
      );

      expect(names, isEmpty);
      expect(
        AppLogger.global.entriesWhere().where(
          (entry) => entry.level == AppLogLevel.warning,
        ),
        hasLength(1),
      );
    });
  });

  group('launch arguments', () {
    test('a plain launch passes only -avd', () {
      expect(
        tool.buildLaunchArguments('Pixel_7a', EmulatorLaunchOptions.normal),
        ['-avd', 'Pixel_7a'],
      );
    });

    test('cold boot skips the saved snapshot', () {
      expect(
        tool.buildLaunchArguments(
          'Pixel_7a',
          const EmulatorLaunchOptions(coldBoot: true),
        ),
        ['-avd', 'Pixel_7a', '-no-snapshot-load'],
      );
    });

    test('wipe data is passed and is flagged destructive', () {
      const options = EmulatorLaunchOptions(wipeData: true);

      expect(tool.buildLaunchArguments('Pixel_7a', options), [
        '-avd',
        'Pixel_7a',
        '-wipe-data',
      ]);
      expect(options.isDestructive, isTrue);
      expect(EmulatorLaunchOptions.normal.isDestructive, isFalse);
    });

    test('launch spawns the built argument list and reports the pid', () async {
      final recording = _RecordingEmulatorTool();

      final outcome = await recording.launch(
        'Pixel_7a',
        options: const EmulatorLaunchOptions(coldBoot: true),
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.pid, isPositive);
      expect(outcome.error, isNull);
      expect(recording.started.single, [
        '-avd',
        'Pixel_7a',
        '-no-snapshot-load',
      ]);
    });

    test('a missing emulator binary is reported, not thrown', () async {
      final missing = EmulatorTool(executablePath: '/nonexistent/emulator');

      final outcome = await missing.launch('Pixel_7a');

      expect(outcome.isSuccess, isFalse);
      expect(outcome.pid, isNull);
      expect(outcome.error, contains('Pixel_7a'));
    });

    test('a listing failure is swallowed into an empty list', () async {
      final missing = EmulatorTool(executablePath: '/nonexistent/emulator');
      expect(await missing.listAvds(), isEmpty);
    });
  });

  group('adb emulator commands', () {
    test('recognises emulator serials only', () {
      expect(AdbTool.isEmulatorSerial('emulator-5554'), isTrue);
      expect(AdbTool.isEmulatorSerial('emulator-5556'), isTrue);
      expect(AdbTool.isEmulatorSerial('R58M12345'), isFalse);
      expect(AdbTool.isEmulatorSerial('192.168.1.5:5555'), isFalse);
      expect(AdbTool.isEmulatorSerial('emulator-'), isFalse);
    });

    test('reads the AVD name and drops the console acknowledgement', () {
      expect(adb.parseEmulatorAvdName(_ok('Pixel_7a\nOK\n')), 'Pixel_7a');
    });

    test('treats a KO answer as no name', () {
      expect(adb.parseEmulatorAvdName(_ok('KO: bad command\n')), isNull);
    });

    test('a failed call yields no name', () {
      expect(
        adb.parseEmulatorAvdName(
          const ToolCommandResult(exitCode: 1, stdout: '', stderr: 'error'),
        ),
        isNull,
      );
    });

    test('does not call the console for a physical device', () async {
      // `/usr/bin/true` would answer nothing anyway; the point is that the
      // guard returns before spawning at all.
      expect(await adb.emulatorAvdName('R58M12345'), isNull);
    });

    test('refuses to kill something that is not an emulator', () async {
      final result = await adb.killEmulator('R58M12345');

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('not a local emulator'));
    });
  });
}
