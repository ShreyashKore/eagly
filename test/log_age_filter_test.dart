import 'package:eagly/data/device.dart';
import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/data/models/log_filters.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/features/logs/services/filter_utils.dart';
import 'package:flutter_test/flutter_test.dart';

LogEntry _entry(
  String timestamp, {
  DevicePlatform platform = DevicePlatform.android,
  DateTime? now,
}) => LogEntry(
  timestamp: timestamp,
  platform: platform,
  pid: '100',
  tid: '200',
  level: 'I',
  tag: 'Tag',
  message: 'message',
  now: now,
);

void main() {
  group('parseMaxAge', () {
    test('parses single-unit values', () {
      expect(parseMaxAge('45s'), const Duration(seconds: 45));
      expect(parseMaxAge('30m'), const Duration(minutes: 30));
      expect(parseMaxAge('2h'), const Duration(hours: 2));
      expect(parseMaxAge('1d'), const Duration(days: 1));
    });

    test('parses compound values and is case/space tolerant', () {
      expect(parseMaxAge('1h30m'), const Duration(hours: 1, minutes: 30));
      expect(parseMaxAge('1D 12H'), const Duration(days: 1, hours: 12));
    });

    test('rejects junk, unit-less, and zero values', () {
      expect(parseMaxAge(''), isNull);
      expect(parseMaxAge('abc'), isNull);
      expect(parseMaxAge('10'), isNull);
      expect(parseMaxAge('0s'), isNull);
      expect(parseMaxAge('5x'), isNull);
    });
  });

  group('formatMaxAge', () {
    test('emits the compact form and round-trips through parseMaxAge', () {
      expect(formatMaxAge(const Duration(hours: 1)), '1h');
      expect(formatMaxAge(const Duration(minutes: 90)), '1h30m');
      expect(formatMaxAge(const Duration(days: 2, seconds: 5)), '2d5s');
      for (final input in ['45s', '30m', '2h', '1d', '1h30m']) {
        expect(formatMaxAge(parseMaxAge(input)!), input);
      }
    });
  });

  group('LogFilters age parsing / composing', () {
    test('parse reads the age key and aliases into maxAge', () {
      for (final text in ['age:1h', 'maxage:1h', 'since:1h']) {
        final filters = LogFilters.parse(
          text,
          fallbackLevel: LogLevel.verbose,
          isIosLogContext: false,
        );
        expect(filters.maxAge, const Duration(hours: 1), reason: text);
      }
    });

    test('invalid age value is ignored rather than treated as a term', () {
      final filters = LogFilters.parse(
        'age:soon',
        fallbackLevel: LogLevel.verbose,
        isIosLogContext: false,
      );
      expect(filters.maxAge, isNull);
      expect(filters.rawTerms, isEmpty);
    });

    test('compose emits an age token that parse reads back', () {
      final text = LogFilters.compose(
        level: LogLevel.verbose,
        defaultLevel: LogLevel.verbose,
        maxAge: const Duration(hours: 1, minutes: 30),
      );
      expect(text, 'age:1h30m');
      final reparsed = LogFilters.parse(
        text,
        fallbackLevel: LogLevel.verbose,
        isIosLogContext: false,
      );
      expect(reparsed.maxAge, const Duration(hours: 1, minutes: 30));
    });
  });

  group('LogEntry.parsedTimestamp', () {
    final now = DateTime(2026, 7, 5, 12, 0, 0);

    test('parses the full YYYY-MM-DD form', () {
      expect(
        _entry('2026-07-05 11:30:00.250', now: now).parsedTimestamp,
        DateTime(2026, 7, 5, 11, 30, 0, 250),
      );
    });

    test('parses the short MM-DD Android form using the reference year', () {
      expect(
        _entry('07-05 11:59:00.000', now: now).parsedTimestamp,
        DateTime(2026, 7, 5, 11, 59, 0, 0),
      );
    });

    test('steps back a year for a short date that would sit in the future', () {
      final january = DateTime(2026, 1, 2, 9, 0, 0);
      expect(
        _entry('12-31 23:00:00.000', now: january).parsedTimestamp,
        DateTime(2025, 12, 31, 23, 0, 0),
      );
    });

    test('returns null for empty or unrecognised timestamps', () {
      expect(_entry('', now: now).parsedTimestamp, isNull);
      expect(_entry('not a timestamp', now: now).parsedTimestamp, isNull);
    });

    test('does not recognise the year-less short form on iOS entries', () {
      expect(
        _entry(
          '07-05 11:59:00.000',
          platform: DevicePlatform.ios,
          now: now,
        ).parsedTimestamp,
        isNull,
      );
    });
  });

  group('matchesLogFilters max age', () {
    final now = DateTime(2026, 7, 5, 12, 0, 0);
    final filters = LogFilters.fromFields(
      level: LogLevel.verbose,
      maxAge: const Duration(hours: 1),
    );

    bool matches(String timestamp) => matchesLogFilters(
      _entry(timestamp, now: now),
      filters,
      LogLevel.verbose,
      now: now,
    );

    test('keeps entries within the max age', () {
      expect(matches('2026-07-05 11:30:00.000'), isTrue);
      expect(matches('07-05 11:59:00.000'), isTrue);
    });

    test('drops entries older than the max age', () {
      expect(matches('2026-07-05 10:00:00.000'), isFalse);
      expect(matches('07-05 09:00:00.000'), isFalse);
    });

    test('keeps entries whose timestamp cannot be parsed', () {
      expect(matches(''), isTrue);
    });
  });
}
