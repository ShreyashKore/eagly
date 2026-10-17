import 'dart:async';

import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/services/log_parsers/ios_syslog_parser.dart';
import 'package:eagly/features/logs/services/log_parsers/log_line_parser.dart';
import 'package:eagly/features/logs/services/log_parsers/logcat_parser.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

const _interval = Duration(milliseconds: 100);
const _fallback = Duration(seconds: 1);
const _header = '[ 09-26 20:46:04.996  1: 2 D/Tag ]';

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

  @override
  PendingEntryStatus get pendingEntryStatus => _inner.pendingEntryStatus;
}

class _ThrowingParser implements LogLineParser {
  _ThrowingParser({this.onAddLine = false, this.onFlush = false});

  final bool onAddLine;
  final bool onFlush;
  final _inner = LogcatParser();

  @override
  List<LogEntry> addLine(String line) {
    if (onAddLine && line == 'bad') throw const FormatException('addLine');
    return _inner.addLine(line);
  }

  @override
  LogEntry? flush() {
    if (onFlush) throw const FormatException('flush');
    return _inner.flush();
  }

  @override
  PendingEntryStatus get pendingEntryStatus => _inner.pendingEntryStatus;
}

/// Drives [parseLogLines] over a hand-fed line stream inside [FakeAsync].
class _Harness {
  _Harness(this.async, {LogLineParser? parser})
    : parser = parser ?? LogcatParser() {
    subscription = parseLogLines(
      _lines.stream,
      this.parser,
      idleFlushInterval: _interval,
      incompleteEntryFlushDelay: _fallback,
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

    test('holds a header however long its body takes, then joins them', () {
      fakeAsync((async) {
        final harness = _Harness(async)..add([_header]);
        harness.elapse(_fallback * 3);
        expect(harness.entries, isEmpty);

        harness
          ..add(['one', 'two', ''])
          ..elapse(_interval * 3);
        expect(harness.messages, ['one\ntwo']);
        expect(harness.entries.single.timestamp, '09-26 20:46:04.996');
      });
    });

    test('waits for the fallback before flushing an entry with no footer', () {
      fakeAsync((async) {
        final harness = _Harness(async)..add([_header, 'one']);
        harness.elapse(_fallback ~/ 2);
        expect(harness.entries, isEmpty);

        harness
          ..add(['two', ''])
          ..elapse(_interval * 3);
        expect(harness.messages, ['one\ntwo']);
      });
    });

    test('keeps the rest of an entry cut off past the fallback', () {
      fakeAsync((async) {
        final harness = _Harness(async)..add([_header, 'one']);
        harness.elapse(_fallback + _interval * 2);
        expect(harness.messages, ['one']);

        harness
          ..add(['two', ''])
          ..elapse(_interval * 3);
        expect(harness.messages, ['one', 'two']);
        final [first, rest] = harness.entries;
        expect(
          [rest.timestamp, rest.pid, rest.tid, rest.level, rest.tag],
          [first.timestamp, first.pid, first.tid, first.level, first.tag],
        );
      });
    });

    test('flushes an entry with its footer after the short interval', () {
      fakeAsync((async) {
        final harness = _Harness(async)..add([_header, 'body', '']);
        // The first tick still sees the lines; only the second is quiet.
        harness.elapse(_interval);
        expect(harness.entries, isEmpty);

        harness.elapse(_interval);
        expect(harness.messages, ['body']);
      });
    });

    test('keeps an iOS continuation that arrives after an idle flush', () {
      fakeAsync((async) {
        final harness = _Harness(
          async,
          parser: IosSyslogParser(now: () => DateTime(2026, 9, 26)),
        )..add(['Sep 26 20:46:04 MyApp[123] <Notice>: first']);
        harness.elapse(_interval * 3);
        expect(harness.messages, ['first']);

        harness
          ..add(['second'])
          ..elapse(_interval * 3);
        expect(harness.messages, ['first', 'second']);
        final [first, rest] = harness.entries;
        expect(
          [rest.timestamp, rest.pid, rest.processName],
          [first.timestamp, first.pid, first.processName],
        );
      });
    });

    test('delivers a parser exception as an error and keeps going', () {
      fakeAsync((async) {
        final harness = _Harness(
          async,
          parser: _ThrowingParser(onAddLine: true),
        )..add([_header, 'bad', _header, 'good', '']);
        harness.close();

        expect(harness.errors, [isFormatException]);
        expect(harness.messages, ['', 'good']);
      });
    });

    test('delivers an idle-flush exception as an error', () {
      fakeAsync((async) {
        final harness = _Harness(async, parser: _ThrowingParser(onFlush: true))
          ..add([_header, 'body', '']);
        harness.elapse(_interval * 2);

        expect(harness.errors, [isFormatException]);
      });
    });

    test('never idle-flushes while the output is paused', () {
      fakeAsync((async) {
        final parser = _CountingParser();
        final harness = _Harness(async, parser: parser)
          ..add([_header, 'body', '']);
        harness.subscription.pause();
        harness.elapse(_fallback * 5);
        // A paused listener wouldn't see a flushed entry anyway, so check the
        // parser still holds it.
        expect(parser.flushes, 0);

        harness.subscription.resume();
        harness.elapse(_interval * 2);
        expect(harness.messages, ['body']);
      });
    });

    test('does not restart the timer when resumed after the source ends', () {
      fakeAsync((async) {
        final lines = StreamController<String>();
        final messages = <String>[];
        late final StreamSubscription<LogEntry> subscription;
        subscription =
            parseLogLines(
              lines.stream,
              LogcatParser(),
              idleFlushInterval: _interval,
            ).listen((entry) {
              messages.add(entry.message);
              // Still draining after the source has ended.
              subscription.pause();
              subscription.resume();
            });

        lines
          ..add(_header)
          ..add('body')
          ..close();
        async.flushMicrotasks();

        expect(messages, ['body']);
        expect(async.periodicTimerCount, 0);
      });
    });

    test('emits the held entry before a source error', () {
      fakeAsync((async) {
        final lines = StreamController<String>();
        final events = <Object>[];
        parseLogLines(
          lines.stream,
          LogcatParser(),
          idleFlushInterval: _interval,
        ).listen((entry) => events.add(entry.message), onError: events.add);

        lines
          ..add(_header)
          ..add('before the error')
          ..addError(StateError('boom'));
        async.flushMicrotasks();

        expect(events, ['before the error', isStateError]);
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

    test('delivers a parser exception as an error event', () async {
      await expectLater(
        parseLogRecords(
          Stream.fromIterable(['bad']),
          _ThrowingParser(onAddLine: true),
        ),
        emitsInOrder([emitsError(isFormatException), emitsDone]),
      );
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
