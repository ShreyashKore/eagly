import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/services/log_parsers/logcat_parser.dart';
import 'package:flutter_test/flutter_test.dart';

List<LogEntry> _parseAll(List<String> lines) {
  final parser = LogcatParser();
  final logs = <LogEntry>[];
  for (final line in lines) {
    logs.addAll(parser.addLine(line));
  }
  final trailingEntry = parser.flush();
  if (trailingEntry != null) logs.add(trailingEntry);
  return logs;
}

void main() {
  group('LogcatParser', () {
    // Captured verbatim from `adb logcat -v long` on an API 34 device.
    test('keeps a multi-line message as one entry, blank lines included', () {
      final logs = _parseAll([
        '--------- beginning of main',
        '[ 09-26 20:46:04.996 32036:32036 D/EaglyML  ]',
        'line one',
        'line two',
        '',
        'line four',
        '',
        '[ 09-26 20:46:05.045 32040:32040 D/EaglyML  ]',
        'single A',
        '',
      ]);

      expect(logs, hasLength(3));
      expect(logs[0].type, LogEntryType.notice);

      final multiLine = logs[1];
      expect(multiLine.type, LogEntryType.log);
      expect(multiLine.timestamp, '09-26 20:46:04.996');
      expect(multiLine.pid, '32036');
      expect(multiLine.tid, '32036');
      expect(multiLine.level, 'D');
      expect(multiLine.tag, 'EaglyML');
      expect(multiLine.message, 'line one\nline two\n\nline four');

      expect(logs[2].message, 'single A');
    });

    test('keeps entries apart even when their headers are identical', () {
      // Two Log.d calls from one thread in the same millisecond — the case
      // `-v threadtime` can't tell apart from a single two-line message.
      final logs = _parseAll([
        '[ 09-26 20:46:05.034  1234: 1234 I/Loop     ]',
        'item 1',
        '',
        '[ 09-26 20:46:05.034  1234: 1234 I/Loop     ]',
        'item 2',
        '',
      ]);

      expect(logs.map((log) => log.message), ['item 1', 'item 2']);
    });

    test('holds the entry being built until the next header or flush', () {
      final parser = LogcatParser();

      expect(parser.addLine('[ 09-26 20:46:05.034  1: 2 W/Tag ]'), isEmpty);
      expect(parser.addLine('first'), isEmpty);
      expect(parser.addLine('second'), isEmpty);

      expect(parser.flush()?.message, 'first\nsecond');
      expect(parser.flush(), isNull);
    });

    test('emits the pending entry before a section separator', () {
      final logs = _parseAll([
        '[ 09-26 20:46:05.034  1: 2 E/Tag ]',
        'boom',
        '',
        '--------- switch to crash',
      ]);

      expect(logs.map((log) => log.type), [
        LogEntryType.log,
        LogEntryType.notice,
      ]);
      expect(logs.first.message, 'boom');
      expect(logs.last.message, 'Switched to crash');
    });

    test('keeps tags containing spaces and brackets', () {
      final logs = _parseAll([
        '[ 09-26 20:46:05.034  1: 2 I/My Tag [x] ]',
        'hello',
      ]);

      expect(logs.single.tag, 'My Tag [x]');
    });

    test('ignores lines that arrive before any header', () {
      final logs = _parseAll([
        'stray output',
        '[ 09-26 20:46:05.034  1: 2 I/Tag ]',
        'hello',
      ]);

      expect(logs.single.message, 'hello');
    });
  });
}
