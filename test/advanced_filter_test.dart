import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/data/models/log_filters.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/features/logs/data/models/recent_fliter_values.dart';
import 'package:eagly/features/logs/services/filter_utils.dart';
import 'package:flutter_test/flutter_test.dart';

LogEntry _log({
  String pid = '100',
  String tid = '200',
  String level = 'I',
  String tag = 'Tag',
  String message = 'message',
  String? packageName,
}) => LogEntry(
  timestamp: '',
  pid: pid,
  tid: tid,
  level: level,
  tag: tag,
  message: message,
  packageName: packageName,
);

LogFilters _parse(String text, {bool isIos = false}) => LogFilters.parse(
  text,
  fallbackLevel: LogLevel.verbose,
  isIosLogContext: isIos,
);

// Matching never depends on the level threshold here: verbose keeps everything.
bool _matches(LogFilters filters, LogEntry log) =>
    matchesLogFilters(log, filters, LogLevel.verbose);

void main() {
  group('parse maps operators to term mode + negation', () {
    void expectSingleTag(
      String text,
      String value,
      FilterMatchMode mode,
      bool negate,
    ) {
      final term = _parse(text).tagTerms.single;
      expect(term.value, value, reason: text);
      expect(term.mode, mode, reason: text);
      expect(term.negate, negate, reason: text);
    }

    test('contains is the default', () {
      expectSingleTag('tag:auth', 'auth', FilterMatchMode.contains, false);
    });

    test('=: selects an exact match', () {
      expectSingleTag('tag=:auth', 'auth', FilterMatchMode.exact, false);
    });

    test('~: selects a regex match', () {
      expectSingleTag('tag~:au.*', 'au.*', FilterMatchMode.regex, false);
    });

    test('a leading - negates each mode', () {
      expectSingleTag('-tag:auth', 'auth', FilterMatchMode.contains, true);
      expectSingleTag('-tag=:auth', 'auth', FilterMatchMode.exact, true);
      expectSingleTag('-tag~:au.*', 'au.*', FilterMatchMode.regex, true);
    });

    test('quoted values keep spaces and drop the quotes', () {
      final term = _parse('-message~:"a b c"').messageTerms.single;
      expect(term.value, 'a b c');
      expect(term.mode, FilterMatchMode.regex);
      expect(term.negate, isTrue);
    });
  });

  group('operators are keyed-only; bare words stay literal', () {
    test('- ~ = on a bare word are part of the raw contains term', () {
      for (final text in ['-foo', '~foo', '=foo']) {
        final raw = _parse(text).rawTerms.single;
        expect(raw.value, text, reason: text);
        expect(raw.mode, FilterMatchMode.contains, reason: text);
        expect(raw.negate, isFalse, reason: text);
      }
    });

    test('an unknown key falls back to a literal raw term', () {
      final filters = _parse('color=:red');
      expect(filters.tagTerms, isEmpty);
      expect(filters.rawTerms.single.value, 'color=:red');
    });
  });

  group('matching semantics', () {
    test('contains is a case-insensitive substring', () {
      expect(_matches(_parse('tag:uth'), _log(tag: 'Auth')), isTrue);
      expect(_matches(_parse('tag:xyz'), _log(tag: 'Auth')), isFalse);
    });

    test('exact requires the whole value (case-insensitive)', () {
      expect(_matches(_parse('tag=:auth'), _log(tag: 'Auth')), isTrue);
      expect(_matches(_parse('tag=:auth'), _log(tag: 'AuthService')), isFalse);
    });

    test('regex matches case-insensitively against the field', () {
      expect(
        _matches(_parse(r'message~:err\d+'), _log(message: 'saw ERR42 now')),
        isTrue,
      );
      expect(
        _matches(_parse(r'message~:err\d+'), _log(message: 'no digits')),
        isFalse,
      );
    });

    test('negation inverts the result', () {
      expect(_matches(_parse('-tag:auth'), _log(tag: 'Network')), isTrue);
      expect(_matches(_parse('-tag:auth'), _log(tag: 'Auth')), isFalse);
      expect(_matches(_parse('-tag=:auth'), _log(tag: 'AuthService')), isTrue);
      expect(_matches(_parse('-tag=:auth'), _log(tag: 'Auth')), isFalse);
    });

    test('package exact matches the package name, not a prefix', () {
      final log = _log(packageName: 'com.x.app');
      expect(_matches(_parse('package=:com.x.app'), log), isTrue);
      expect(_matches(_parse('package=:com.x'), log), isFalse);
      expect(_matches(_parse('package:com.x'), log), isTrue);
    });
  });

  group('pid/tid matches any form and negates as a whole', () {
    final log = _log(pid: '100', tid: '200');

    test('matches pid, tid, or the pair', () {
      expect(_matches(_parse('pid:100'), log), isTrue);
      expect(_matches(_parse('pid:200'), log), isTrue);
      expect(_matches(_parse('pid:100/200'), log), isTrue);
      expect(_matches(_parse('pid=:200'), log), isTrue);
      expect(_matches(_parse('pid=:2'), log), isFalse);
    });

    test('negation excludes only when no form matches', () {
      // pid or tid contains the value → excluded.
      expect(_matches(_parse('-pid:100'), log), isFalse);
      expect(_matches(_parse('-pid:200'), log), isFalse);
      // Nothing matches → kept, even though most candidates differ.
      expect(_matches(_parse('-pid:300'), log), isTrue);
    });
  });

  group('invalid regex', () {
    test('positive invalid regex matches nothing', () {
      final term = _parse('tag~:[bad').tagTerms.single;
      expect(term.hasInvalidRegex, isTrue);
      expect(_matches(_parse('tag~:[bad'), _log(tag: 'anything')), isFalse);
    });

    test('negated invalid regex matches everything', () {
      expect(_matches(_parse('-tag~:[bad'), _log(tag: 'anything')), isTrue);
    });
  });

  group('compose round-trips operators', () {
    LogFilters roundTrip(String text, {bool isIos = false}) {
      final composed = LogFilters.compose(
        _parse(text, isIos: isIos),
        defaultLevel: LogLevel.defaultSelectionForPlatform(isIos: isIos),
        isIos: isIos,
      );
      return _parse(composed, isIos: isIos);
    }

    test('advanced keyed terms survive parse → compose → parse', () {
      final reparsed = roundTrip('-package:test tag~:auth.* message=:hello');
      expect(reparsed.packageTerms.single.negate, isTrue);
      expect(reparsed.tagTerms.single.mode, FilterMatchMode.regex);
      expect(reparsed.tagTerms.single.value, 'auth.*');
      expect(reparsed.messageTerms.single.mode, FilterMatchMode.exact);
      expect(reparsed.messageTerms.single.value, 'hello');
    });

    test('bare words are re-emitted as raw terms, not promoted to message', () {
      final reparsed = roundTrip('foo bar');
      expect(reparsed.rawTerms.map((t) => t.value), ['foo', 'bar']);
      expect(reparsed.messageTerms, isEmpty);
    });

    test('iOS surfaces the tag key as category and reads it back', () {
      final composed = LogFilters.compose(
        _parse('tag~:Net', isIos: true),
        defaultLevel: LogLevel.defaultSelectionForPlatform(isIos: true),
        isIos: true,
      );
      expect(composed, contains('category~:Net'));
      final reparsed = _parse(composed, isIos: true);
      expect(reparsed.tagTerms.single.value, 'Net');
      expect(reparsed.tagTerms.single.mode, FilterMatchMode.regex);
    });
  });

  group('recent filter values ignore advanced terms', () {
    test('only plain, non-negated contains values are remembered', () {
      final recents = RecentFilterValues();
      recents.rememberFrom(_parse('tag:keep -tag:skip tag~:re package:pos'));
      expect(recents.tag, ['keep']);
      expect(recents.package, ['pos']);
    });
  });
}
