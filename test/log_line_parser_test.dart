import 'dart:async';

import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/services/log_parsers/log_line_parser.dart';
import 'package:eagly/features/logs/services/log_parsers/logcat_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _interval = Duration(milliseconds: 20);

class _CountingParser implements LogLineParser {
  final _inner = LogcatParser();
  var flushes = 0;

  @override
  Iterable<LogEntry> addLine(String line) => _inner.addLine(line);

  @override
  LogEntry? flush() {
    flushes++;
    return _inner.flush();
  }
}

void main() {
  group('parseLogLines', () {
    test('flushes the held entry when the stream ends', () async {
      final entries = await parseLogLines(
        Stream.fromIterable([
          '[ 09-26 20:46:04.996  1: 2 D/Tag ]',
          'one',
          'two',
          '',
          '[ 09-26 20:46:04.997  1: 2 D/Tag ]',
          'last',
        ]),
        LogcatParser(),
        idleFlushInterval: _interval,
      ).toList();

      expect(entries.map((entry) => entry.message), ['one\ntwo', 'last']);
    });

    test('flushes the held entry once the stream goes quiet', () async {
      final lines = StreamController<String>();
      final entries = <LogEntry>[];
      final subscription = parseLogLines(
        lines.stream,
        LogcatParser(),
        idleFlushInterval: _interval,
      ).listen(entries.add);

      lines
        ..add('[ 09-26 20:46:04.996  1: 2 D/Tag ]')
        ..add('only entry');
      await Future<void>.delayed(_interval * 5);

      expect(entries.map((entry) => entry.message), ['only entry']);
      await subscription.cancel();
      await lines.close();
    });

    test('forwards errors from the line stream', () async {
      final lines = Stream<String>.error(StateError('boom'));

      await expectLater(
        parseLogLines(lines, LogcatParser(), idleFlushInterval: _interval),
        emitsError(isStateError),
      );
    });

    test('cancelling stops the source and the idle timer', () async {
      var sourceCancelled = false;
      final lines = StreamController<String>(
        onCancel: () => sourceCancelled = true,
      );
      final parser = _CountingParser();
      final subscription = parseLogLines(
        lines.stream,
        parser,
        idleFlushInterval: _interval,
      ).listen((_) {});

      lines
        ..add('[ 09-26 20:46:04.996  1: 2 D/Tag ]')
        ..add('never flushed');
      await subscription.cancel();
      await Future<void>.delayed(_interval * 5);

      expect(sourceCancelled, isTrue);
      expect(parser.flushes, 0);
    });
  });
}
