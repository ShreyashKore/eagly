import 'package:eagly/services/sentry_breadcrumb_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  late DateTime now;
  late SentryBreadcrumbFilter filter;

  setUp(() {
    now = DateTime.utc(2026, 11, 27, 12);
    filter = SentryBreadcrumbFilter(clock: () => now);
  });

  void advance(Duration by) => now = now.add(by);

  Hint hintFor(BreadcrumbOrigin origin) =>
      Hint.withMap({breadcrumbOriginHintKey: origin.name});

  /// A breadcrumb as `AppBreadcrumbs.log` builds it, stamped "now".
  Breadcrumb? logLine(
    String message, {
    String source = 'AdbTool',
    SentryLevel level = SentryLevel.info,
  }) => filter.filter(
    Breadcrumb(
      message: message,
      category: source,
      level: level,
      data: {},
      timestamp: now,
    ),
    hintFor(BreadcrumbOrigin.appLog),
  );

  /// A breadcrumb as `AppBreadcrumbs.action` builds it, stamped "now".
  Breadcrumb? action(String message, {String category = 'logs.stream'}) =>
      filter.filter(
        Breadcrumb(message: message, category: category, timestamp: now),
        hintFor(BreadcrumbOrigin.action),
      );

  /// Feeds [count] breadcrumbs [gap] apart and returns the ones kept.
  List<Breadcrumb> storm(
    int count,
    Duration gap,
    Breadcrumb? Function(int i) add,
  ) {
    final kept = <Breadcrumb>[];
    for (var i = 0; i < count; i++) {
      final crumb = add(i);
      if (crumb != null) kept.add(crumb);
      advance(gap);
    }
    return kept;
  }

  group('drops noise', () {
    test('console breadcrumbs from print/debugPrint', () {
      final crumb = Breadcrumb.console(
        message: 'Another exception was thrown: …',
        level: SentryLevel.info,
        timestamp: now,
      );
      expect(filter.filter(crumb, Hint()), isNull);
    });

    test('debug-level breadcrumbs', () {
      expect(logLine('verbose detail', level: SentryLevel.debug), isNull);
    });

    test('null in, null out', () {
      expect(filter.filter(null, Hint()), isNull);
    });
  });

  group('collapses duplicates', () {
    test('the adb polling storm keeps one crumb per window, with a count', () {
      // FLUTTER-M5: ~100 identical lines 50 ms apart.
      final kept = storm(100, const Duration(milliseconds: 50), (_) {
        return logLine('Found 4 device(s)');
      });
      expect(kept, hasLength(1));
      expect(
        kept.single.data,
        isNot(contains(SentryBreadcrumbFilter.repeatedKey)),
      );

      // Past the window the next copy passes and says how many were folded.
      advance(const Duration(seconds: 30));
      final next = logLine('Found 4 device(s)');
      expect(next, isNotNull);
      expect(next!.data![SentryBreadcrumbFilter.repeatedKey], 99);
    });

    test('distinct messages in a category are not collapsed', () {
      expect(logLine('Found 4 device(s)'), isNotNull);
      advance(const Duration(milliseconds: 10));
      expect(logLine('Found 3 device(s)'), isNotNull);
      advance(const Duration(milliseconds: 10));
      expect(logLine('Found 4 device(s)'), isNull);
    });

    test('the same text at another level is a different breadcrumb', () {
      expect(logLine('adb exited'), isNotNull);
      advance(const Duration(milliseconds: 10));
      expect(logLine('adb exited', level: SentryLevel.error), isNotNull);
    });

    test('identical errors are collapsed too', () {
      final kept = storm(50, const Duration(milliseconds: 20), (_) {
        return logLine('Failed to list devices', level: SentryLevel.error);
      });
      expect(kept, hasLength(1));
    });

    test('deliberate actions are never collapsed', () {
      // The device-tab click → log stream restart bug was found by seeing
      // this breadcrumb twice in a row.
      expect(action('Started live logging for Pixel'), isNotNull);
      advance(const Duration(milliseconds: 300));
      expect(action('Started live logging for Pixel'), isNotNull);
    });

    test('taps recorded by Sentry are never collapsed', () {
      Breadcrumb tap() => Breadcrumb.userInteraction(
        subCategory: 'click',
        viewId: 'tab',
        timestamp: now,
      );
      expect(filter.filter(tap(), Hint()), isNotNull);
      advance(const Duration(milliseconds: 100));
      expect(filter.filter(tap(), Hint()), isNotNull);
    });
  });

  group('rate-limits storms', () {
    test('distinct lines in one category are bounded', () {
      // 1000 lines in 10 s that all differ (as `MCP x in N ms` lines do).
      final kept = storm(1000, const Duration(milliseconds: 10), (i) {
        return logLine('MCP read_logs from agent in $i ms', source: 'MCP');
      });
      // Burst of 15, then 0.5/s for 10 s.
      expect(kept.length, lessThanOrEqualTo(15 + 5 + 1));
      expect(kept.length, greaterThanOrEqualTo(15));
    });

    test('the shared bucket bounds a storm spread over many categories', () {
      final kept = storm(2000, const Duration(milliseconds: 5), (i) {
        return logLine('line $i', source: 'Source${i % 100}');
      });
      // Burst of 40, then 1/s for 10 s.
      expect(kept.length, lessThanOrEqualTo(40 + 10 + 1));
    });

    test('the next crumb to pass says how many its category lost', () {
      storm(100, const Duration(milliseconds: 10), (i) {
        return logLine('line $i', source: 'MCP');
      });
      advance(const Duration(seconds: 10));
      final next = logLine('after the storm', source: 'MCP');
      expect(next, isNotNull);
      expect(
        next!.data![SentryBreadcrumbFilter.rateLimitedKey],
        greaterThan(0),
      );
    });

    test('an info storm does not starve errors or user actions', () {
      storm(500, const Duration(milliseconds: 2), (i) {
        return logLine('Found $i device(s)');
      });
      expect(
        logLine('adb devices -l failed', level: SentryLevel.error),
        isNotNull,
      );
      expect(action('Started live logging for Pixel'), isNotNull);
      final tap = Breadcrumb.userInteraction(
        subCategory: 'click',
        viewId: 'x',
        timestamp: now,
      );
      expect(filter.filter(tap, Hint()), isNotNull);
    });

    test('priority breadcrumbs are bounded as well', () {
      final kept = storm(1000, const Duration(milliseconds: 10), (i) {
        return action('Scheduling log recovery (attempt $i)');
      });
      // Per-category burst of 20, then 1/s for 10 s.
      expect(kept.length, lessThanOrEqualTo(20 + 10 + 1));
    });

    test('ordinary use is not limited', () {
      // A busy session for two minutes: a distinct tool line every two
      // seconds from each of two sources, and an action every second.
      final kept = storm(120, const Duration(seconds: 1), (i) {
        return switch (i % 4) {
          0 => logLine('Connecting to 10.0.0.$i…'),
          2 => logLine('Starting idevicesyslog for $i', source: 'Ios'),
          _ => action('Opened pane $i', category: 'navigation'),
        };
      });
      expect(kept, hasLength(120));
    });
  });

  group('replayed native breadcrumbs', () {
    test('pass untouched and leave the state alone', () {
      // LoadContextsIntegration re-runs beforeBreadcrumb over the native
      // copies, at millisecond precision, when a Dart event is captured.
      final live = filter.filter(
        Breadcrumb(
          message: 'Found 4 device(s)',
          category: 'AdbTool',
          timestamp: now.add(const Duration(microseconds: 456)),
        ),
        hintFor(BreadcrumbOrigin.appLog),
      );
      expect(live, isNotNull);
      advance(const Duration(milliseconds: 5));

      final replayed = Breadcrumb.fromJson(live!.toJson());
      for (var i = 0; i < 200; i++) {
        expect(filter.filter(replayed, Hint()), same(replayed));
      }
      // The replay consumed nothing: the live line is still collapsed...
      expect(logLine('Found 4 device(s)'), isNull);
      // ...and the category still has its burst less the one live crumb.
      final kept = storm(20, const Duration(milliseconds: 1), (i) {
        return logLine('fresh $i', source: 'AdbTool');
      });
      expect(kept, hasLength(14));
    });

    test('a storm sharing one clock tick is still filtered', () {
      // Windows' clock ticks coarsely, so a burst can carry one timestamp.
      final kept = storm(100, Duration.zero, (_) {
        return logLine('Found 4 device(s)');
      });
      expect(kept, hasLength(1));
    });

    test('a clock stepping back does not turn live crumbs into replays', () {
      expect(logLine('before'), isNotNull);
      now = now.subtract(const Duration(minutes: 5));
      expect(logLine('after the step'), isNotNull);
      advance(const Duration(milliseconds: 5));
      expect(logLine('after the step'), isNull);
    });
  });

  group('trims', () {
    test('long messages and string data', () {
      final crumb = filter.filter(
        Breadcrumb(
          message: 'x' * 5000,
          category: 'AdbTool',
          data: {'detail': 'y' * 5000, 'count': 3},
          timestamp: now,
        ),
        hintFor(BreadcrumbOrigin.appLog),
      )!;
      expect(crumb.message!.length, lessThanOrEqualTo(1025));
      expect((crumb.data!['detail'] as String).length, lessThanOrEqualTo(1025));
      expect(crumb.data!['count'], 3);
    });

    test('annotates breadcrumbs whose data map is typed narrowly', () {
      // Sentry's own breadcrumbs may carry a Map<String, String>.
      Breadcrumb lifecycle() => Breadcrumb(
        category: 'app.lifecycle',
        data: <String, String>{'state': 'resumed'},
        timestamp: now,
      );
      expect(filter.filter(lifecycle(), Hint()), isNotNull);
      advance(const Duration(milliseconds: 1));
      expect(filter.filter(lifecycle(), Hint()), isNull);
      advance(const Duration(seconds: 31));
      final next = filter.filter(lifecycle(), Hint());
      expect(next!.data![SentryBreadcrumbFilter.repeatedKey], 1);
    });
  });
}
