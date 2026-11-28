import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/presentation/components/log_row.dart';
import 'package:eagly/features/logs/services/log_display_list.dart';
import 'package:eagly/utils/log_entry_utils.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/session_test_support.dart';

LogEntry line(
  String message, {
  String pid = '100',
  String tag = 'Tag',
  String level = 'I',
  String timestamp = '2026-04-26 10:00:00.000',
}) => testLogEntry(
  message: message,
  pid: pid,
  tag: tag,
  level: level,
  timestamp: timestamp,
);

/// Each row as `message` or `message×count` (`+` when unfolded).
List<String> shape(LogDisplayList rows) => [
  for (var row = 0; row < rows.length; row++)
    switch (rows.repeatAt(row)) {
      null => rows.entries[row].message,
      final repeat =>
        '${rows.entries[row].message}×${repeat.count}'
            '${repeat.expanded ? '+' : ''}',
    },
];

LogDisplayList built(List<LogEntry> entries) => LogDisplayList()..sync(entries);

void main() {
  group('runs', () {
    test('fold from three identical lines, not two', () {
      final rows = built([
        line('a'),
        line('a'),
        line('b'),
        line('c'),
        line('c'),
        line('c'),
        line('d'),
      ]);
      expect(shape(rows), ['a', 'a', 'b', 'c×3', 'd']);
    });

    test('break on a different level, tag, pid or message', () {
      for (final odd in [
        line('x', level: 'W'),
        line('x', tag: 'Other'),
        line('x', pid: '200'),
        line('y'),
      ]) {
        final rows = built([line('x'), line('x'), odd, line('x'), line('x')]);
        expect(rows.length, 5, reason: '$odd');
        expect(rows.repeatAt(0), isNull);
      }
    });

    test('ignore timestamps and threads', () {
      final rows = built([
        testLogEntry(message: 'x', tid: '1'),
        testLogEntry(message: 'x', tid: '2', timestamp: '2026-04-26 10:00:01'),
        testLogEntry(message: 'x', tid: '3', timestamp: '2026-04-26 10:00:02'),
      ]);
      expect(shape(rows), ['x×3']);
    });

    test('never take in a session marker', () {
      final marker = LogEntryUtils.buildLoggingState(
        type: LogEntryType.paused,
        message: 'x',
        tag: 'Tag',
      );
      final rows = built([line('x'), line('x'), marker, line('x'), line('x')]);
      expect(rows.length, 5);
      expect(
        built([marker, marker, marker]).length,
        3,
        reason: 'markers never fold together either',
      );
    });

    test('report their count and span', () {
      final rows = built([
        line('x', timestamp: '2026-04-26 10:00:00.000'),
        line('x', timestamp: '2026-04-26 10:00:01.000'),
        line('x', timestamp: '2026-04-26 10:00:02.100'),
      ]);
      final repeat = rows.repeatAt(0)!;
      expect(repeat.count, 3);
      expect(repeat.span, const Duration(milliseconds: 2100));
      expect(LogRow.repeatChipText(repeat), '×3 over 2.1 s');
    });

    test('leave the span out when a timestamp does not parse', () {
      final rows = built([
        line('x', timestamp: 'garbled'),
        line('x'),
        line('x'),
      ]);
      expect(rows.repeatAt(0)!.span, isNull);
      expect(LogRow.repeatChipText(rows.repeatAt(0)!), '×3');
    });
  });

  group('appending', () {
    test('grows the last run or starts a new one, as a rebuild would', () {
      final entries = <LogEntry>[];
      final rows = LogDisplayList();
      final sequence = [
        'a', 'a', 'a', 'a', 'b', 'b', 'c', 'c', 'c', 'a', //
      ].map(line).toList();
      for (final entry in sequence) {
        entries.add(entry);
        rows.sync(entries);
        expect(shape(rows), shape(built(List.of(entries))));
      }
      expect(shape(rows), ['a×4', 'b', 'b', 'c×3', 'a']);
    });

    test('costs only the new lines', () {
      final entries = [for (var i = 0; i < 1000; i++) line('$i')];
      final rows = built(entries);
      final revision = rows.revision;
      entries.addAll([line('999'), line('999')]);
      rows.sync(entries);
      expect(rows.revision, revision + 1);
      expect(rows.length, 1000, reason: '0 to 998, then 999 three times');
      rows.sync(entries);
      expect(rows.revision, revision + 1, reason: 'nothing new, no work');
    });

    test('rebuilds when lines leave the front', () {
      final entries = [line('a'), line('b'), line('b'), line('b')];
      final rows = built(entries);
      entries
        ..removeAt(0)
        ..removeAt(0);
      rows.sync(entries);
      expect(shape(rows), ['b', 'b']);
    });

    test('rebuilds for a replaced list', () {
      final rows = built([line('a'), line('a'), line('a')]);
      rows.sync([line('b')]);
      expect(shape(rows), ['b']);
    });
  });

  group('mapping', () {
    test('maps rows to entry ranges and back', () {
      final rows = built([
        line('a'),
        line('b'),
        line('b'),
        line('b'),
        line('b'),
        line('c'),
      ]);
      expect(rows.length, 3);
      expect([for (var r = 0; r < 3; r++) rows.startOf(r)], [0, 1, 5]);
      expect([for (var r = 0; r < 3; r++) rows.lengthOf(r)], [1, 4, 1]);
      expect([for (var i = 0; i < 6; i++) rows.rowOf(i)], [0, 1, 1, 1, 1, 2]);
    });

    test('is the identity with folding off', () {
      final entries = [line('a'), line('a'), line('a')];
      final rows = built(entries)..collapse = false;
      rows.sync(entries);
      expect(rows.length, 3);
      expect(rows.entries, same(entries));
      expect(rows.rowOf(2), 2);
      expect(rows.lengthOf(0), 1);
      expect(rows.repeatAt(0), isNull);
      rows.collapse = true;
      rows.sync(entries);
      expect(shape(rows), ['a×3']);
    });
  });

  group('unfolding', () {
    test('shows each line in place and folds back', () {
      final entries = [line('a'), line('b'), line('b'), line('b'), line('c')];
      final rows = built(entries);
      expect(rows.toggleRepeat(1), isTrue);
      expect(shape(rows), ['a', 'b×3+', 'b', 'b', 'c']);
      expect([for (var i = 0; i < 5; i++) rows.rowOf(i)], [0, 1, 2, 3, 4]);
      expect(rows.repeatAt(2), isNull, reason: 'only the first row has a chip');
      expect(rows.toggleRepeat(2), isFalse);
      expect(rows.toggleRepeat(1), isTrue);
      expect(shape(rows), ['a', 'b×3', 'c']);
    });

    test('an unfolded run at the tail keeps unfolding as it grows', () {
      final entries = [line('b'), line('b'), line('b')];
      final rows = built(entries)..toggleRepeat(0);
      entries.add(line('b'));
      rows.sync(entries);
      expect(shape(rows), ['b×4+', 'b', 'b', 'b']);
    });

    test('survives a rebuild', () {
      final entries = [line('a'), line('b'), line('b'), line('b')];
      final rows = built(entries)..toggleRepeat(1);
      rows
        ..invalidate()
        ..sync(entries);
      expect(shape(rows), ['a', 'b×3+', 'b', 'b']);
    });
  });

  test('formatRepeatSpan', () {
    expect(formatRepeatSpan(null), isNull);
    expect(formatRepeatSpan(Duration.zero), isNull);
    expect(formatRepeatSpan(const Duration(milliseconds: 340)), '340 ms');
    expect(formatRepeatSpan(const Duration(milliseconds: 2149)), '2.1 s');
    expect(
      formatRepeatSpan(const Duration(minutes: 4, seconds: 12)),
      '4 min 12 s',
    );
    expect(formatRepeatSpan(const Duration(minutes: 4)), '4 min');
    expect(formatRepeatSpan(const Duration(hours: 1, minutes: 5)), '1 h 5 min');
  });
}
