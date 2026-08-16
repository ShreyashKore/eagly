@TestOn('mac-os || linux')
library;

import 'package:eagly/services/tools/device_tool_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the generic runner the Utilities feature is built on against real
/// processes — the argument passing, output collection and timeout kill are
/// the parts that can't be faked meaningfully.
void main() {
  test('runs an executable and collects stdout', () async {
    final runner = DeviceToolRunner(
      executableName: 'echo',
      executablePath: '/bin/echo',
    );

    final result = await runner.runTextWithTimeout(['-s', 'serial', 'hello']);

    expect(result.exitCode, 0);
    expect(result.combinedOutput, '-s serial hello');
  });

  test('arguments are passed verbatim, never through a host shell', () async {
    final runner = DeviceToolRunner(
      executableName: 'echo',
      executablePath: '/bin/echo',
    );

    // A shell would have expanded these; the device shell on the other end is
    // the only thing that should ever interpret them.
    final result = await runner.runTextWithTimeout([
      'shell',
      'wm size; wm density',
    ]);

    expect(result.combinedOutput, 'shell wm size; wm density');
  });

  test('reports a non-zero exit with stderr', () async {
    final runner = DeviceToolRunner(
      executableName: 'sh',
      executablePath: '/bin/sh',
    );

    final result = await runner.runTextWithTimeout([
      '-c',
      'echo boom >&2; exit 3',
    ]);

    expect(result.exitCode, 3);
    expect(result.isSuccess, isFalse);
    expect(result.combinedOutput, contains('boom'));
  });

  test('kills a process that outruns its timeout', () async {
    final runner = DeviceToolRunner(
      executableName: 'sleep',
      executablePath: '/bin/sleep',
    );

    final result = await runner.runTextWithTimeout([
      '30',
    ], timeout: const Duration(milliseconds: 300));

    expect(result.exitCode, -1);
    expect(result.combinedOutput, contains('Timed out'));
  });
}
