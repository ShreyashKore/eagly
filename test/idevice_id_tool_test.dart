import 'package:flutter_test/flutter_test.dart';
import 'package:eagly/features/app_log/app_logger.dart';
import 'package:eagly/services/tools/idevice_id_tool.dart';
import 'package:eagly/services/tools/tool_process_runner.dart';

void main() {
  late IdeviceIdTool tool;

  setUp(() {
    AppLogger.global.clear();
    tool = IdeviceIdTool(executablePath: '/usr/bin/true');
  });

  ToolCommandResult success(String stdout) =>
      ToolCommandResult(exitCode: 0, stdout: stdout, stderr: '');

  ToolCommandResult usbmuxdUnavailable() => const ToolCommandResult(
    exitCode: 255,
    stdout: '',
    stderr: 'ERROR: Unable to retrieve device list!',
  );

  List<AppLogEntry> warnings() => AppLogger.global
      .entriesWhere()
      .where((entry) => entry.level == AppLogLevel.warning)
      .toList();

  List<AppLogEntry> errors() => AppLogger.global.entriesWhere(errorsOnly: true);

  test('parses non-empty device ids and logs nothing', () {
    final ids = tool.parseDeviceIds(success('abc123\n  def456 \n\n'));

    expect(ids, ['abc123', 'def456']);
    expect(AppLogger.global.entriesWhere(), isEmpty);
  });

  test('a clean empty list is not an error', () {
    expect(tool.parseDeviceIds(success('\n')), isEmpty);
    expect(AppLogger.global.entriesWhere(), isEmpty);
  });

  test(
    'usbmuxd-unavailable is logged once as a warning, not on every poll',
    () {
      tool.parseDeviceIds(usbmuxdUnavailable());
      tool.parseDeviceIds(usbmuxdUnavailable());
      tool.parseDeviceIds(usbmuxdUnavailable());

      expect(warnings(), hasLength(1));
      expect(errors(), isEmpty);
      expect(warnings().single.detail, contains('usbmuxd'));
    },
  );

  test('a successful poll resets the warning so a later outage logs again', () {
    tool.parseDeviceIds(usbmuxdUnavailable());
    tool.parseDeviceIds(success('\n'));
    tool.parseDeviceIds(usbmuxdUnavailable());

    expect(warnings(), hasLength(2));
  });

  test('a missing bundled binary warns once with staging guidance', () async {
    // No executablePath and nothing to resolve in the test runner's directory,
    // so the runner falls back to the bare name and the launch fails.
    final missing = IdeviceIdTool();

    expect(await missing.getDeviceIds(), isEmpty);
    expect(await missing.getDeviceIds(), isEmpty);
    expect(await missing.getDeviceIds(), isEmpty);

    expect(warnings(), hasLength(1));
    expect(errors(), isEmpty);
    expect(warnings().single.detail, contains('download_platform_tools.sh'));
  });

  test('a staged binary that cannot launch is reported as an error', () async {
    final broken = IdeviceIdTool(executablePath: '/nonexistent/dir/idevice_id');

    expect(await broken.getDeviceIds(), isEmpty);

    expect(errors(), hasLength(1));
    expect(warnings(), isEmpty);
  });

  test('an unexpected failure is still logged as an error every time', () {
    final failure = const ToolCommandResult(
      exitCode: 1,
      stdout: '',
      stderr: 'segfault or something else entirely',
    );

    tool.parseDeviceIds(failure);
    tool.parseDeviceIds(failure);

    expect(errors(), hasLength(2));
    expect(warnings(), isEmpty);
  });
}
