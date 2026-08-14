import 'package:eagly/services/sentry_event_filter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  setUp(() {
    SentryEventFilter.ignoredPatterns.clear();
    SentryEventFilter.ignoredPatterns.addAll([
      RegExp(r'RenderFlex overflowed', caseSensitive: false),
      RegExp(r'A RenderFlex overflowed by \d+ pixels', caseSensitive: false),
    ]);
    SentryEventFilter.ignoredExceptionTypes.clear();
    SentryEventFilter.customFilters.clear();
  });

  group('SentryEventFilter default filters', () {
    test('drops event when exception value contains RenderFlex overflowed', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'FlutterError',
            value: 'A RenderFlex overflowed by 16 pixels on the right.',
          ),
        ],
      );
      final hint = Hint();

      expect(SentryEventFilter.shouldIgnore(event, hint), isTrue);
      expect(SentryEventFilter.beforeSend(event, hint), isNull);
    });

    test(
      'drops event when throwable is FlutterError for RenderFlex overflow',
      () {
        final error = FlutterError(
          'A RenderFlex overflowed by 24 pixels on the bottom.',
        );
        final event = SentryEvent(throwable: error);
        final hint = Hint();

        expect(SentryEventFilter.shouldIgnore(event, hint), isTrue);
        expect(SentryEventFilter.beforeSend(event, hint), isNull);
      },
    );

    test(
      'drops event when throwable is FlutterErrorDetails for RenderFlex overflow',
      () {
        final details = FlutterErrorDetails(
          exception: FlutterError(
            'A RenderFlex overflowed by 8 pixels on the top.',
          ),
          library: 'rendering library',
          context: ErrorDescription('during layout'),
        );
        final event = SentryEvent(throwable: details);
        final hint = Hint();

        expect(SentryEventFilter.shouldIgnore(event, hint), isTrue);
        expect(SentryEventFilter.beforeSend(event, hint), isNull);
      },
    );

    test('drops event when message contains RenderFlex overflowed', () {
      final event = SentryEvent(
        message: SentryMessage(
          'A RenderFlex overflowed by 16 pixels on the right.',
        ),
      );
      final hint = Hint();

      expect(SentryEventFilter.shouldIgnore(event, hint), isTrue);
      expect(SentryEventFilter.beforeSend(event, hint), isNull);
    });

    test('preserves critical or non-matching errors', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'StateError',
            value: 'Bad state: Session expired',
          ),
        ],
      );
      final hint = Hint();

      expect(SentryEventFilter.shouldIgnore(event, hint), isFalse);
      expect(SentryEventFilter.beforeSend(event, hint), equals(event));
    });

    test('preserves generic FlutterError that is not an overflow', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'FlutterError',
            value: 'Could not find a declaration of class Widget in context',
          ),
        ],
      );
      final hint = Hint();

      expect(SentryEventFilter.shouldIgnore(event, hint), isFalse);
      expect(SentryEventFilter.beforeSend(event, hint), equals(event));
    });
  });

  group('SentryEventFilter extensibility', () {
    test('can dynamically add new string pattern to ignore', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'SocketException',
            value: 'Connection reset by peer',
          ),
        ],
      );
      final hint = Hint();

      // Initially not ignored
      expect(SentryEventFilter.shouldIgnore(event, hint), isFalse);

      // Add ignored pattern
      SentryEventFilter.ignorePattern('Connection reset by peer');

      expect(SentryEventFilter.shouldIgnore(event, hint), isTrue);
      expect(SentryEventFilter.beforeSend(event, hint), isNull);
    });

    test('can dynamically add new RegExp pattern to ignore', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'HttpException',
            value: 'HTTP 429 Too Many Requests: retry after 5s',
          ),
        ],
      );
      final hint = Hint();

      // Initially not ignored
      expect(SentryEventFilter.shouldIgnore(event, hint), isFalse);

      // Add ignored regex
      SentryEventFilter.ignorePattern(RegExp(r'HTTP 429'));

      expect(SentryEventFilter.shouldIgnore(event, hint), isTrue);
      expect(SentryEventFilter.beforeSend(event, hint), isNull);
    });

    test('can dynamically add ignored exception types', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'CustomBenignWarning',
            value: 'Harmless warning',
          ),
        ],
      );
      final hint = Hint();

      // Initially not ignored
      expect(SentryEventFilter.shouldIgnore(event, hint), isFalse);

      // Add ignored exception type
      SentryEventFilter.ignoreExceptionType('CustomBenignWarning');

      expect(SentryEventFilter.shouldIgnore(event, hint), isTrue);
      expect(SentryEventFilter.beforeSend(event, hint), isNull);
    });

    test('can dynamically add custom filter predicate', () {
      final event = SentryEvent(
        tags: const {'feature': 'experimental_preview'},
      );
      final hint = Hint();

      // Initially not ignored
      expect(SentryEventFilter.shouldIgnore(event, hint), isFalse);

      // Add custom filter
      SentryEventFilter.addCustomFilter((e, h) {
        return e.tags?['feature'] == 'experimental_preview';
      });

      expect(SentryEventFilter.shouldIgnore(event, hint), isTrue);
      expect(SentryEventFilter.beforeSend(event, hint), isNull);
    });
  });
}
