@TestOn('!windows')
library;

import 'dart:io';

import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/services/tools/adb_tool.dart';
import 'package:eagly/services/tools/idevice_syslog_tool.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end guards for the log pipeline — a real child process, its stdout
/// split into lines, [parseLogLines], the platform parser, the tool's stream —
/// driven by fake `adb` / `idevicesyslog` scripts. See docs/LOG_STREAMING.md.
///
/// These pin the invariants that are easy to break from outside the parsers:
/// the logcat format Eagly asks for, and that no text is lost when an entry
/// arrives in pieces slow enough to trip the idle flush.

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('log-stream-pipeline');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test(
    'adb logcat is asked for -v long, and multi-line entries stay whole',
    () async {
      // Output captured verbatim from `adb logcat -v long` on an API 34 device,
      // with a pause mid-entry that is longer than the idle-flush interval.
      final adb = await _writeExecutable(tempDir, 'adb', r'''#!/bin/sh
if [ "$*" != "-s SERIAL logcat -v long" ]; then
  echo "unexpected adb arguments: $*" >&2
  exit 2
fi
echo '--------- beginning of main'
echo '[ 09-26 20:46:04.996 32036:32036 D/EaglyML  ]'
echo 'line one'
echo 'line two'
sleep 0.3
echo ''
echo 'line four'
echo ''
echo '[ 09-26 20:46:05.045 32040:32040 D/EaglyML  ]'
echo 'single A'
echo ''
''');

      final entries = await AdbTool(executablePath: adb)
          .startLogcat('SERIAL')
          .stream
          .toList();

      // A bad argument list surfaces as a tool-error row instead.
      expect(entries.first.type, LogEntryType.notice);
      expect(entries.first.message, 'Beginning of main');
      expect(_flatten(entries), [
        '32036|09-26 20:46:04.996|line one',
        '32036|09-26 20:46:04.996|line two',
        '32036|09-26 20:46:04.996|',
        '32036|09-26 20:46:04.996|line four',
        '32040|09-26 20:46:05.045|single A',
      ]);
    },
  );

  test('idevicesyslog continuations survive an idle flush', () async {
    // The pause after the header is longer than the idle-flush interval, so
    // the entry is flushed before its continuation arrives; the continuation
    // must come through under the same header rather than being dropped.
    final syslog = await _writeExecutable(
      tempDir,
      'idevicesyslog',
      r'''#!/bin/sh
echo '[connected:UDID]'
echo 'Sep 26 23:11:50.009450 camerad(AudioUnits)[136] <Debug>: SetupConverter: input'
sleep 0.3
echo '  from:  1 ch,      0 Hz, Float32'
echo '    to:  2 ch,  48000 Hz, Float32, interleaved'
echo 'Sep 26 23:11:50.009491 camerad(AudioUnits)[136] <Debug>: Initialize'
''',
    );

    final entries = await IdeviceSyslogTool(executablePath: syslog)
        .start(deviceId: 'UDID', processName: 'iPhone')
        .stream
        .toList();

    final at = '${DateTime.now().year}-09-26 23:11:50';
    expect(_flatten(entries), [
      '136|$at.009|SetupConverter: input',
      '136|$at.009|  from:  1 ch,      0 Hz, Float32',
      '136|$at.009|    to:  2 ch,  48000 Hz, Float32, interleaved',
      '136|$at.009|Initialize',
    ]);
  });
}

/// Every message line with the header it was logged under, in order — equal
/// for any split of the same entries, so it checks that nothing was lost or
/// reordered without depending on flush timing.
List<String> _flatten(List<LogEntry> entries) => [
  for (final entry in entries.where((entry) => entry.type == LogEntryType.log))
    for (final line in entry.message.split('\n'))
      '${entry.pid}|${entry.timestamp}|$line',
];

Future<String> _writeExecutable(
  Directory directory,
  String name,
  String content,
) async {
  final file = File('${directory.path}/$name');
  await file.writeAsString(content);
  final chmodResult = await Process.run('chmod', ['+x', file.path]);
  if (chmodResult.exitCode != 0) {
    throw StateError('Failed to mark ${file.path} executable');
  }
  return file.path;
}
