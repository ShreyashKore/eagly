import 'dart:io';

import 'package:eagly/services/tools/tool_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// A runner over `/bin/sleep`, so a spawned child stays alive until something
/// kills it.
class _SleepRunner() extends ToolProcessRunner {
  this : super(executableName: 'sleep', executablePath: '/bin/sleep');
}

/// A runner over `/bin/sh`, for children that spawn children of their own.
class _ShellRunner() extends ToolProcessRunner {
  this : super(executableName: 'sh', executablePath: '/bin/sh');
}

void main() {
  group('ToolProcessRunner.runTextWithTimeout', () {
    test(
      'returns on timeout even while a grandchild holds the pipes',
      () async {
        // The backgrounded sleep inherits stdout and outlives the killed shell,
        // the way java outlives cmd.exe behind `avdmanager.bat`.
        final result = await _ShellRunner()
            .runTextWithTimeout([
              '-c',
              r'sleep 30 & echo $!; wait',
            ], timeout: const Duration(milliseconds: 300))
            .timeout(const Duration(seconds: 10));
        final grandchild = int.tryParse(result.stdout.trim());
        if (grandchild != null) {
          Process.killPid(grandchild, ProcessSignal.sigkill);
        }

        expect(result.exitCode, -1);
        expect(result.stderr, contains('Timed out'));
        expect(grandchild, isNotNull, reason: 'output before the kill is kept');
      },
    );
  }, skip: Platform.isWindows ? 'POSIX-only process helpers' : null);

  group('ToolProcessRunner process tracking', () {
    test('terminateAllProcesses kills every live child', () async {
      final runner = _SleepRunner();
      final first = await runner.startProcess(['30']);
      final second = await runner.startProcess(['30']);

      await ToolProcessRunner.terminateAllProcesses();

      expect(await first.exitCode, isNot(0));
      expect(await second.exitCode, isNot(0));
    });

    test('a child that already exited is dropped from tracking', () async {
      final runner = _SleepRunner();
      final process = await runner.startProcess(['0']);
      await process.exitCode;

      // Nothing left to kill: this must return rather than wait on a process
      // that can never exit again.
      await ToolProcessRunner.terminateAllProcesses().timeout(
        const Duration(seconds: 2),
      );
    });

    test('detached children are left running', () async {
      final runner = _SleepRunner();
      final detached = await runner.startProcess([
        '30',
      ], mode: ProcessStartMode.detached);
      addTearDown(() => Process.killPid(detached.pid, ProcessSignal.sigkill));

      await ToolProcessRunner.terminateAllProcesses();

      // `kill -0` succeeds only while the pid is still addressable. A detached
      // child is not ours to reap, so a killed one would have been reaped by
      // init and the signal would fail.
      final alive = await Process.run('kill', ['-0', '${detached.pid}']);
      expect(
        alive.exitCode,
        0,
        reason: 'the adb server is started detached precisely to outlive us',
      );
    });
  }, skip: Platform.isWindows ? 'POSIX-only process helpers' : null);
}
