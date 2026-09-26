import 'dart:async';

import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/services/log_parsers/ios_syslog_parser.dart';
import 'package:eagly/features/logs/services/log_parsers/log_line_parser.dart';
import 'package:eagly/features/logs/services/log_parsers/logcat_parser.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

const _interval = Duration(milliseconds: 100);

class _CountingParser implements LogLineParser {
  final _inner = LogcatParser();
  var flushes = 0;

  @override
  List<LogEntry> addLine(String line) => _inner.addLine(line);

  @override
  LogEntry? flush() {
    flushes++;
    return _inner.flush();
  }
}

/// Drives [parseLogLines] over a hand-fed line stream inside [FakeAsync].
class _Harness {
  _Harness(this.async, {LogLineParser? parser})
    : parser = parser ?? LogcatParser() {
    subscription = parseLogLines(
      _lines.stream,
      this.parser,
      idleFlushInterval: _interval,
    ).listen(entries.add, onError: errors.add);
  }

  final FakeAsync async;
  final LogLineParser parser;
  final _lines = StreamController<String>();
  final entries = <LogEntry>[];
  final errors = <Object>[];
  late final StreamSubscription<LogEntry> subscription;

  List<String> get messages => entries.map((entry) => entry.message).toList();

  void add(List<String> lines) {
    lines.forEach(_lines.add);
    async.flushMicrotasks();
  }

  void elapse(Duration duration) => async.elapse(duration);

  void close() {
    _lines.close();
    async.flushMicrotasks();
  }
}

void main() {
  group('parseLogLines', () {
    test('flushes the held entry when the stream ends', () {
      fakeAsync((async) {
        final harness = _Harness(async)
          ..add([
            '[ 09-26 20:46:04.996  1: 2 D/Tag ]',
            'one',
            'two',
            '',
            '[ 09-26 20:46:04.997  1: 2 D/Tag ]',
            'last',
          ]);
        expect(harness.messages, ['one\ntwo']);

        harness.close();
        expect(harness.messages, ['one\ntwo', 'last']);
      });
    });

    test('flushes the held entry once the stream goes quiet', () {
      fakeAsync((async) {
        final harness = _Harness(async)
          ..add(['[ 09-26 20:46:04.996  1: 2 D/Tag ]', 'only entry', '']);
        expect(harness.entries, isEmpty);

        harness.elapse(_interval * 3);
        expect(harness.messages, ['only entry']);
      });
    });

    test('forwards errors from the line stream', () {
      fakeAsync((async) {
        final errors = <Object>[];
        parseLogLines(
          Stream<String>.error(StateError('boom')),
          LogcatParser(),
          idleFlushInterval: _interval,
        ).listen((_) {}, onError: errors.add);
        async.flushMicrotasks();

        expect(errors, [isStateError]);
      });
    });

    test('cancelling stops the source and the idle timer', () {
      fakeAsync((async) {
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
        async.flushMicrotasks();
        subscription.cancel();
        async.elapse(_interval * 10);

        expect(sourceCancelled, isTrue);
        expect(parser.flushes, 0);
      });
    });
  });

  group('parseLogRecords', () {
    IosSyslogParser iosParser() =>
        IosSyslogParser(now: () => DateTime(2026, 9, 26));

    test(
      'keeps a multi-line relay record as one entry under its own header',
      () async {
        final entries = await parseLogRecords(
          Stream.fromIterable([
            'Sep 26 20:46:04 MyApp[123] <Notice>: one\ntwo',
            'Sep 26 20:46:05 OtherApp(Net)[456] <Error>: three',
          ]),
          iosParser(),
        ).toList();

        expect(entries, hasLength(2));
        expect(entries[0].message, 'one\ntwo');
        expect(entries[0].timestamp, '2026-09-26 20:46:04.000');
        expect(entries[0].pid, '123');
        expect(entries[0].packageName, 'MyApp');
        expect(entries[0].level, 'default');
        expect(entries[1].message, 'three');
        expect(entries[1].timestamp, '2026-09-26 20:46:05.000');
        expect(entries[1].pid, '456');
        expect(entries[1].tag, 'Net');
        expect(entries[1].level, 'error');
      },
    );

    test('emits each record as soon as it arrives', () {
      fakeAsync((async) {
        final records = StreamController<String>();
        final entries = <LogEntry>[];
        parseLogRecords(records.stream, iosParser()).listen(entries.add);

        records.add('Sep 26 20:46:04 MyApp[123] <Notice>: solo');
        async.flushMicrotasks();

        expect(entries.map((entry) => entry.message), ['solo']);
      });
    });

    test('drops only the empty piece after a trailing newline', () async {
      final entries = await parseLogRecords(
        Stream.fromIterable(['Sep 26 20:46:04 MyApp[123] <Notice>: a\n\nb\n']),
        iosParser(),
      ).toList();

      expect(entries.single.message, 'a\n\nb');
    });

    test('decodes meta escapes on every line of a record', () async {
      final entries = await parseLogRecords(
        Stream.fromIterable([
          r'Sep 26 20:46:04 MyApp[123] <Notice>: \M-b\M^U\M^T top'
              '\n'
              r'\M-b\M^U\M^Z bottom',
        ]),
        iosParser(),
      ).toList();

      expect(entries.single.message, '╔ top\n╚ bottom');
    });
  });
}
