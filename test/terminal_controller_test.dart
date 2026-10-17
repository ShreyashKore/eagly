import 'package:eagly/data/device.dart';
import 'package:eagly/features/terminal/data/terminal_command.dart';
import 'package:eagly/features/terminal/data/terminal_line.dart';
import 'package:eagly/features/terminal/terminal_controller.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final android = Device(
    'emulator-5554',
    'device',
    platform: DevicePlatform.android,
    brand: 'Google',
    model: 'Pixel 8',
  );
  final ios = Device(
    '00008030-000A1B2C3D4E5F',
    'device',
    platform: DevicePlatform.ios,
    model: 'iPhone 15',
    name: 'Work phone',
  );

  final pixel7 = Device(
    'RF8N70ABCDE',
    'device',
    platform: DevicePlatform.android,
    model: 'Pixel 7',
  );

  late FakeSessionService service;
  DeviceSessionController? session;
  late TerminalController controller;

  /// Mirrors [controller] so tearDown can skip tests that never made one.
  TerminalController? activeController;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  TerminalController createController({
    Device? device,
    List<Device> known = const [],
  }) {
    final bound = device ?? android;
    service = FakeSessionService(bound);
    session = DeviceSessionController(device: bound, service: service);
    controller = TerminalController(session!, availableDevices: () => known);
    return activeController = controller;
  }

  tearDown(() {
    activeController?.dispose();
    activeController = null;
    session?.dispose();
    session = null;
  });

  /// Submits [line] and drives the fake process it started to completion.
  Future<void> run(
    String line, {
    int exitCode = 0,
    List<String> stdout = const [],
    List<String> stderr = const [],
  }) async {
    final pending = controller.submit(line);
    await pumpEventQueue();
    final process = service.terminalProcesses.last;
    for (final text in stdout) {
      process.emit(text);
    }
    for (final text in stderr) {
      process.emit(text, isError: true);
    }
    await process.finish(exitCode);
    await pending;
  }

  List<String> textOf(TerminalLineKind kind) => controller.lines
      .where((line) => line.kind == kind)
      .map((line) => line.text)
      .toList();

  group('tokenizer', () {
    test('splits on whitespace and honours quotes', () {
      expect(tokenizeCommandLine('adb  shell   ls'), ['adb', 'shell', 'ls']);
      expect(tokenizeCommandLine('''adb shell "am start -n a/b"'''), [
        'adb',
        'shell',
        'am start -n a/b',
      ]);
      expect(tokenizeCommandLine("echo 'a  b'"), ['echo', 'a  b']);
      expect(tokenizeCommandLine(r'adb push my\ file.txt /sdcard'), [
        'adb',
        'push',
        'my file.txt',
        '/sdcard',
      ]);
    });

    test('an unbalanced quote is a format error', () {
      expect(
        () => tokenizeCommandLine('adb shell "ls'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('device selector injection', () {
    test('adb gets -s for the session device', () async {
      createController();
      await run('adb shell getprop');

      expect(service.terminalRequests.single.executable, 'adb');
      expect(service.terminalRequests.single.arguments, [
        '-s',
        'emulator-5554',
        'shell',
        'getprop',
      ]);
    });

    test('an explicit selector is left alone', () async {
      createController();
      await run('adb -s other-device shell getprop');

      expect(service.terminalRequests.single.arguments, [
        '-s',
        'other-device',
        'shell',
        'getprop',
      ]);
    });

    test('host subcommands get no selector', () async {
      createController();
      await run('adb devices -l');

      expect(service.terminalRequests.single.arguments, ['devices', '-l']);
    });

    test('idevice tools get -u for an iOS device', () async {
      createController(device: ios);
      await run('ideviceinfo -k ProductVersion');

      expect(service.terminalRequests.single.executable, 'ideviceinfo');
      expect(service.terminalRequests.single.arguments, [
        '-u',
        '00008030-000A1B2C3D4E5F',
        '-k',
        'ProductVersion',
      ]);
    });

    test('tools without a device selector are run bare', () async {
      createController(device: ios);
      await run('idevice_id -l');

      expect(service.terminalRequests.single.arguments, ['-l']);
    });
  });

  group('implicit device shell', () {
    test('an unknown command runs through adb shell on Android', () async {
      createController();
      await run('pm list packages | grep eagly', stdout: ['package:eagly']);

      expect(service.terminalRequests.single.arguments, [
        '-s',
        'emulator-5554',
        'shell',
        'pm list packages | grep eagly',
      ]);
      expect(textOf(TerminalLineKind.stdout), ['package:eagly']);
    });

    test('iOS has no shell, so the user is pointed at the tools', () async {
      createController(device: ios);
      await controller.submit('ls /var');

      expect(service.terminalRequests, isEmpty);
      expect(textOf(TerminalLineKind.error).single, contains('no shell'));
    });

    test('a tool for the other platform is refused', () async {
      createController();
      await controller.submit('ideviceinfo');

      expect(service.terminalRequests, isEmpty);
      expect(textOf(TerminalLineKind.error).single, contains('iOS'));
    });
  });

  group('targeting another device', () {
    test('@ref sends one line elsewhere without moving the tab', () async {
      createController(known: [android, pixel7]);
      await run('@RF8N adb shell ls');

      // Matched on an id prefix, and adb gets the *other* device's id.
      expect(service.terminalRequests.single.arguments.take(2), [
        '-s',
        'RF8N70ABCDE',
      ]);
      expect(controller.targetDevice.id, android.id);
    });

    test('an ambiguous reference is reported, not guessed', () async {
      final second = Device(
        'emulator-5556',
        'device',
        platform: DevicePlatform.android,
      );
      createController(known: [android, second]);
      await controller.submit('@emulator adb shell ls');

      expect(service.terminalRequests, isEmpty);
      expect(textOf(TerminalLineKind.error).single, contains('matches 2'));
    });

    test('an unknown reference is reported', () async {
      createController(known: [android]);
      await controller.submit('@nope adb shell ls');

      expect(service.terminalRequests, isEmpty);
      expect(textOf(TerminalLineKind.error).single, contains('No device'));
    });

    test('`use` pins the tab and `use auto` releases it', () async {
      createController(known: [android, pixel7]);

      await controller.submit('use Pixel 7');
      expect(controller.targetDevice.id, pixel7.id);
      expect(controller.isPinnedElsewhere, isTrue);

      await run('adb shell ls');
      expect(service.terminalRequests.single.arguments.take(2), [
        '-s',
        pixel7.id,
      ]);

      await controller.submit('use auto');
      expect(controller.targetDevice.id, android.id);
      expect(controller.isPinnedElsewhere, isFalse);
    });

    test('a tab pinned to an iOS device runs its tools', () async {
      createController(known: [android, ios]);

      await controller.submit('use 00008030');
      expect(controller.targetDevice.id, ios.id);

      await run('ideviceinfo');
      expect(service.terminalRequests.single.executable, 'ideviceinfo');
      expect(service.terminalRequests.single.arguments, ['-u', ios.id]);
    });
  });

  group('running commands', () {
    test('stdout and stderr are kept apart', () async {
      createController();
      await run('adb shell ls', stdout: ['a.txt'], stderr: ['permission']);

      expect(textOf(TerminalLineKind.stdout), ['a.txt']);
      expect(textOf(TerminalLineKind.stderr), ['permission']);
    });

    test('a non-zero exit is reported', () async {
      createController();
      await run('adb shell false', exitCode: 1);

      expect(textOf(TerminalLineKind.notice), contains('Exited with code 1.'));
      expect(controller.isRunning, isFalse);
    });

    test('a command that cannot start becomes an error line', () async {
      createController();
      service.terminalStartError = Exception('adb is missing');

      await controller.submit('adb shell ls');

      expect(textOf(TerminalLineKind.error).single, 'adb is missing');
      expect(controller.isRunning, isFalse);
    });

    test('a disconnected device is rejected before the tool runs', () async {
      createController();
      session!.updateDevice(
        android.copyWith(connectionState: DeviceConnectionState.disconnected),
      );

      await controller.submit('adb shell ls');

      expect(service.terminalRequests, isEmpty);
      expect(textOf(TerminalLineKind.error).single, contains('disconnected'));
    });

    test('a submitted line feeds stdin while a command runs', () async {
      createController();
      final pending = controller.submit('adb shell');
      await pumpEventQueue();
      expect(controller.isRunning, isTrue);

      await controller.submit('ls /sdcard');
      final process = service.terminalProcesses.single;
      expect(process.stdinLines, ['ls /sdcard']);
      // The stdin line is echoed, not re-dispatched as a new command.
      expect(service.terminalRequests, hasLength(1));
      expect(textOf(TerminalLineKind.input), ['ls /sdcard']);

      await process.finish(0);
      await pending;
    });

    test('cancel stops the process and says so', () async {
      createController();
      final pending = controller.submit('adb logcat');
      await pumpEventQueue();

      await controller.cancel();
      await pending;

      expect(service.terminalProcesses.single.killed, isTrue);
      expect(textOf(TerminalLineKind.notice), contains('Stopped.'));
    });
  });

  group('built-ins', () {
    test('clear empties the scrollback', () async {
      createController();
      await controller.submit('help');
      expect(controller.lines, isNotEmpty);

      await controller.submit('clear');
      expect(controller.lines, isEmpty);
    });

    test('devices marks the tab target', () async {
      createController(known: [android, ios]);
      await controller.submit('devices');

      final notices = textOf(TerminalLineKind.notice);
      expect(notices.where((line) => line.startsWith('→')), hasLength(1));
      expect(
        notices.firstWhere((line) => line.startsWith('→')),
        contains('emulator-5554'),
      );
    });

    test('tools only lists what the target platform can run', () async {
      createController();
      await controller.submit('tools');

      final notices = textOf(TerminalLineKind.notice).join('\n');
      expect(notices, contains('adb'));
      expect(notices, isNot(contains('ideviceinfo')));
    });

    test('a built-in never starts a process', () async {
      createController();
      await controller.submit('help');
      expect(service.terminalRequests, isEmpty);
    });
  });

  group('history', () {
    test('↑/↓ walk submitted lines and back to an empty prompt', () async {
      createController();
      await controller.submit('help');
      await controller.submit('tools');

      expect(controller.historyPrevious(), 'tools');
      expect(controller.historyPrevious(), 'help');
      expect(controller.historyPrevious(), isNull);
      expect(controller.historyNext(), 'tools');
      expect(controller.historyNext(), '');
      expect(controller.historyNext(), isNull);
    });

    test('repeating the same line does not duplicate it', () async {
      createController();
      await controller.submit('help');
      await controller.submit('help');

      expect(controller.history, ['help']);
    });
  });

  test('scrollback is capped', () async {
    createController();
    final pending = controller.submit('adb logcat');
    await pumpEventQueue();
    final process = service.terminalProcesses.single;
    for (var i = 0; i < TerminalController.maxScrollbackLines + 50; i++) {
      process.emit('line $i');
    }
    await process.finish(0);
    await pending;

    expect(controller.lines, hasLength(TerminalController.maxScrollbackLines));
    // The oldest lines fell off the front; the newest survived.
    expect(
      controller.lines.last.text,
      'line ${TerminalController.maxScrollbackLines + 49}',
    );
  });
}
