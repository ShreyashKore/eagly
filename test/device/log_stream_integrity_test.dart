/// Checks, against real devices, that the live log pipeline loses and
/// reorders nothing. Opt-in, so skipped in CI; run it before changing anything
/// in docs/LOG_STREAMING.md's scope:
///
/// ```bash
/// cd rust && cargo build --release && cd ..   # only for the Rust iOS check
/// EAGLY_TEST_ANDROID_SERIAL=<adb serial> EAGLY_TEST_IOS_UDID=<udid> \
///   fvm flutter test test/device/log_stream_integrity_test.dart
/// ```
///
/// Each check tees the raw tool output as it enters the pipeline, records what
/// the pipeline emits, then parses the same raw output again offline with no
/// idle timer — the canonical result. The two must hold the same message
/// lines under the same headers in the same order; the only difference allowed
/// is an entry split in two by an idle flush (reported as `splits`). A busy
/// device makes this a stress test: an Android backlog replays hundreds of
/// thousands of lines in seconds.
library;

import 'dart:async';
import 'dart:io';

import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/services/log_parsers/ios_syslog_parser.dart';
import 'package:eagly/features/logs/services/log_parsers/log_line_parser.dart';
import 'package:eagly/features/logs/services/log_parsers/logcat_parser.dart';
import 'package:eagly/services/tools/adb_tool.dart';
import 'package:eagly/services/tools/idevice_syslog_tool.dart';
import 'package:eagly/src/rust/api/ios.dart' as rust;
import 'package:eagly/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

final _androidSerial = Platform.environment['EAGLY_TEST_ANDROID_SERIAL'];
final _iosUdid = Platform.environment['EAGLY_TEST_IOS_UDID'];
const _capture = Duration(seconds: 10);

final String _toolsDir = () {
  final os = Platform.isMacOS
      ? 'macos'
      : Platform.isWindows
      ? 'windows'
      : 'linux';
  return '${Directory.current.path}/platform-tools/$os';
}();

final bool _rustLibraryBuilt = () {
  final release = Directory('${Directory.current.path}/rust/target/release');
  return release.existsSync() &&
      release.listSync().any((file) => file.path.contains('rust_lib_eagly'));
}();

void main() {
  test(
    'Android: live logcat entries match the raw output',
    () async {
      final tool = _TeeAdbTool('$_toolsDir/adb');
      final session = tool.startLogcat(_androidSerial!);
      final live = await _collect(session.stream, stop: session.stop);

      _expectIntact('android', live, _parseOffline(LogcatParser(), tool.raw));
    },
    skip: _androidSerial == null ? 'set EAGLY_TEST_ANDROID_SERIAL' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'iOS (idevicesyslog): live entries match the raw output',
    () async {
      final tool = _TeeSyslogTool('$_toolsDir/idevicesyslog');
      final session = tool.start(deviceId: _iosUdid!, processName: 'device');
      final live = await _collect(session.stream, stop: session.stop);

      _expectIntact(
        'ios-cli',
        live,
        _parseOffline(IosSyslogParser(), tool.raw),
      );
    },
    skip: _iosUdid == null ? 'set EAGLY_TEST_IOS_UDID' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'iOS (Rust relay): each record becomes exactly one entry',
    () async {
      await RustLib.init();
      final records = <String>[];
      const sessionId = 'device-integrity-check';
      // The same wiring as RustIosLogService, with the records teed off.
      final stream = parseLogRecords(
        rust.startIosSyslog(udid: _iosUdid!, sessionId: sessionId).map((
          record,
        ) {
          records.add(record);
          return record;
        }),
        IosSyslogParser(),
      );
      final live = await _collect(
        stream,
        stop: () => rust.stopIosSyslog(sessionId: sessionId),
      );

      final expected = <LogEntry>[];
      final parser = IosSyslogParser();
      for (final record in records) {
        final lines = record.split('\n');
        if (lines.length > 1 && lines.last.isEmpty) lines.removeLast();
        for (final line in lines) {
          expected.addAll(parser.addLine(line));
        }
        expected.addAll([?parser.flush()]);
      }
      _expectIntact('ios-rust', live, expected);
      expect(live, hasLength(records.length), reason: 'one entry per record');
    },
    skip: _iosUdid == null
        ? 'set EAGLY_TEST_IOS_UDID'
        : !_rustLibraryBuilt
        ? 'run `cargo build --release` in rust/ first'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// Collects [stream] for [_capture], then stops the source and waits for the
/// tail (the entry held at end of stream) before returning what arrived.
Future<List<LogEntry>> _collect(
  Stream<LogEntry> stream, {
  required Future<void> Function() stop,
}) async {
  final live = <LogEntry>[];
  final done = Completer<void>();
  final subscription = stream.listen(
    live.add,
    onDone: done.complete,
    cancelOnError: false,
  );
  await Future<void>.delayed(_capture);
  await stop();
  await done.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => subscription.cancel(),
  );
  return live;
}

/// The canonical parse: no idle timer, so an entry ends only at the next
/// header and at end of input.
List<LogEntry> _parseOffline(LogLineParser parser, List<String> lines) => [
  for (final line in lines) ...parser.addLine(line),
  ?parser.flush(),
];

void _expectIntact(String name, List<LogEntry> live, List<LogEntry> expected) {
  final multiLine = expected.where((entry) => entry.message.contains('\n'));
  // ignore: avoid_print
  print(
    '$name: ${expected.length} entries (${multiLine.length} multi-line), '
    'splits=${live.length - expected.length}',
  );
  expect(expected, isNotEmpty, reason: 'no logs captured from the device');
  expect(
    live.where((entry) => entry.type == LogEntryType.error),
    isEmpty,
    reason: 'the tool reported an error',
  );
  expect(_flatten(live), _flatten(expected));
}

/// Every message line with the full header it was logged under, in order.
List<String> _flatten(List<LogEntry> entries) => [
  for (final entry in entries.where((entry) => entry.type == LogEntryType.log))
    for (final line in entry.message.split('\n'))
      '${entry.timestamp}|${entry.pid}|${entry.tid}|${entry.level}|'
          '${entry.tag}|${entry.processName}|$line',
];

class _TeeAdbTool(String path) extends AdbTool {
  this : super(executablePath: path);

  final raw = <String>[];

  @override
  Stream<String> stdoutLines(Process process) =>
      super.stdoutLines(process).map((line) {
        raw.add(line);
        return line;
      });
}

class _TeeSyslogTool(String path) extends IdeviceSyslogTool {
  this : super(executablePath: path);

  final raw = <String>[];

  @override
  Stream<String> stdoutLines(Process process) =>
      super.stdoutLines(process).map((line) {
        raw.add(line);
        return line;
      });
}
