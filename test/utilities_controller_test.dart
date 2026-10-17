import 'package:eagly/data/device.dart';
import 'package:eagly/features/utilities/data/utility_catalog.dart';
import 'package:eagly/features/utilities/data/utility_command.dart';
import 'package:eagly/features/utilities/utilities_controller.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/services/tools/tool_process_runner.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSessionService service;
  late Device device;
  DeviceSessionController? session;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  UtilitiesController createController({
    DevicePlatform platform = DevicePlatform.android,
  }) {
    device = platform == DevicePlatform.android
        ? Device(
            'emulator-5554',
            'device',
            platform: DevicePlatform.android,
            brand: 'Google',
            model: 'Pixel 8',
          )
        : Device(
            '00008030-001',
            'device',
            platform: DevicePlatform.ios,
            model: 'iPhone 15',
          );
    service = FakeSessionService(device);
    session = DeviceSessionController(device: device, service: service);
    return session!.utilitiesController;
  }

  UtilityCommand commandById(UtilitiesController controller, String id) {
    return controller.groups
        .expand((group) => group.commands)
        .firstWhere((command) => command.id == id);
  }

  tearDown(() {
    session?.dispose();
    session = null;
  });

  test('the catalog has no duplicate command ids', () {
    final ids = utilityCatalog
        .expand((group) => group.commands)
        .map((command) => command.id)
        .toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('every command is supported by at least one platform', () {
    final android = Device('a', 'device', platform: DevicePlatform.android);
    final ios = Device('i', 'device', platform: DevicePlatform.ios);
    for (final command in utilityCatalog.expand((group) => group.commands)) {
      expect(
        command.supports(android) || command.supports(ios),
        isTrue,
        reason: '${command.id} builds nothing on either platform',
      );
    }
  });

  test('groups only expose commands the device platform supports', () {
    final android = createController();
    final androidIds = android.groups
        .expand((group) => group.commands)
        .map((command) => command.id);
    expect(androidIds, contains('input-text'));
    expect(androidIds, isNot(contains('unpair')));
    session!.dispose();

    final ios = createController(platform: DevicePlatform.ios);
    final iosIds = ios.groups
        .expand((group) => group.commands)
        .map((command) => command.id);
    expect(iosIds, contains('unpair'));
    expect(iosIds, contains('reboot'));
    expect(iosIds, isNot(contains('input-text')));
  });

  test('search narrows commands and drops empty groups', () {
    final controller = createController();
    controller.setSearchText('battery');

    final commands = controller.groups.expand((group) => group.commands);
    expect(commands.map((command) => command.id), contains('battery'));
    expect(commands.map((command) => command.id), isNot(contains('reboot')));
    // Groups left with nothing matching disappear entirely.
    expect(
      controller.groups.map((group) => group.id),
      isNot(contains('power')),
    );
  });

  test(
    'running a command sends the built invocation and keeps the output',
    () async {
      final controller = createController();
      service.utilityResult = const ToolCommandResult(
        exitCode: 0,
        stdout: 'level: 87',
        stderr: '',
      );

      final result = await controller.run(commandById(controller, 'battery'));

      expect(service.utilityRequests, hasLength(1));
      expect(service.utilityRequests.single.tool, UtilityTool.adb);
      expect(service.utilityRequests.single.arguments, [
        'shell',
        'dumpsys battery',
      ]);
      expect(result!.isSuccess, isTrue);
      expect(controller.lastResult?.output, 'level: 87');
      expect(controller.isRunning, isFalse);
    },
  );

  test('parameters are substituted into the invocation', () async {
    final controller = createController();

    await controller.run(
      commandById(controller, 'input-text'),
      values: {'text': "it's here"},
    );

    // Spaces become %s for `input text`, and the value is single-quoted for
    // the device shell.
    expect(service.utilityRequests.single.arguments, [
      'shell',
      r"input text 'it'\''s%shere'",
    ]);
  });

  test('side-effect-only commands leave the output panel empty', () async {
    final controller = createController();
    service.utilityResult = const ToolCommandResult(
      exitCode: 0,
      stdout: '',
      stderr: '',
    );

    final result = await controller.run(commandById(controller, 'wake-screen'));

    expect(result!.isSuccess, isTrue);
    expect(controller.lastResult, isNull);
  });

  test('a non-zero exit is surfaced in the output panel', () async {
    final controller = createController();
    service.utilityResult = const ToolCommandResult(
      exitCode: 1,
      stdout: '',
      stderr: 'device offline',
    );

    final result = await controller.run(commandById(controller, 'wake-screen'));

    expect(result!.isSuccess, isFalse);
    expect(controller.lastResult?.output, 'device offline');
  });

  test('a thrown error becomes a failure result', () async {
    final controller = createController();
    service.utilityError = Exception('adb is missing');

    final result = await controller.run(commandById(controller, 'battery'));

    expect(result!.isSuccess, isFalse);
    expect(result.failure, contains('adb is missing'));
  });

  test('a disconnected device is rejected before the tool runs', () async {
    final controller = createController();
    session!.updateDevice(
      device.copyWith(connectionState: DeviceConnectionState.disconnected),
    );

    final result = await controller.run(commandById(controller, 'battery'));

    expect(service.utilityRequests, isEmpty);
    expect(result!.isSuccess, isFalse);
    expect(result.failure, contains('disconnected'));
  });

  test('only one command runs at a time', () async {
    final controller = createController();
    final first = controller.run(commandById(controller, 'battery'));
    final second = await controller.run(commandById(controller, 'storage'));

    expect(second, isNull);
    await first;
    expect(service.utilityRequests, hasLength(1));
  });
}
