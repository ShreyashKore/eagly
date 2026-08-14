import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Filters noisy, benign, or non-critical errors before they are dispatched to
/// Sentry, conserving event quota and preventing dashboard clutter.
///
/// To add more ignored error messages or patterns in the future, simply append
/// them to [ignoredPatterns] or [ignoredExceptionTypes], or register a custom rule
/// via [addCustomFilter].
class SentryEventFilter {
  SentryEventFilter._();

  /// Substrings or regex patterns that, if found in an error's message,
  /// exception value, or throwable summary, will cause the event to be dropped.
  ///
  /// Add any non-critical or known noisy error patterns here.
  static final List<Pattern> ignoredPatterns = <Pattern>[
    // Benign layout overflow errors during window resizing or layout shifts
    RegExp(r'RenderFlex overflowed', caseSensitive: false),
    RegExp(r'A RenderFlex overflowed by \d+ pixels', caseSensitive: false),
  ];

  /// Exception types / class names that should be dropped unconditionally.
  static final List<String> ignoredExceptionTypes = <String>[];

  /// Custom filter predicates. If any predicate returns `true`, the event will
  /// be ignored and dropped.
  static final List<bool Function(SentryEvent event, Hint hint)> customFilters =
      <bool Function(SentryEvent event, Hint hint)>[];

  /// Adds a new pattern (string or [RegExp]) to the list of ignored patterns.
  static void ignorePattern(Pattern pattern) {
    if (!ignoredPatterns.contains(pattern)) {
      ignoredPatterns.add(pattern);
    }
  }

  /// Adds an exception type name to the list of ignored exception types.
  static void ignoreExceptionType(String typeName) {
    if (!ignoredExceptionTypes.contains(typeName)) {
      ignoredExceptionTypes.add(typeName);
    }
  }

  /// Adds a custom filter predicate that inspects [SentryEvent] and [Hint].
  static void addCustomFilter(
    bool Function(SentryEvent event, Hint hint) filter,
  ) {
    customFilters.add(filter);
  }

  /// Evaluates whether the given [event] and [hint] match any ignore criteria.
  static bool shouldIgnore(SentryEvent event, Hint hint) {
    // 1. Check custom filter predicates first
    for (final filter in customFilters) {
      try {
        if (filter(event, hint)) return true;
      } catch (_) {
        // If a filter throws, do not block the event processing
      }
    }

    // 2. Extract all strings associated with this event
    final extractedTexts = _extractEventTexts(event, hint);

    // 3. Match against ignored patterns
    for (final text in extractedTexts) {
      if (text.isEmpty) continue;
      for (final pattern in ignoredPatterns) {
        if (pattern is RegExp) {
          if (pattern.hasMatch(text)) return true;
        } else if (pattern is String) {
          if (text.toLowerCase().contains(pattern.toLowerCase())) return true;
        }
      }
    }

    // 4. Match against ignored exception types
    if (ignoredExceptionTypes.isNotEmpty) {
      final types = _extractExceptionTypes(event, hint);
      for (final type in types) {
        for (final ignoredType in ignoredExceptionTypes) {
          if (type.toLowerCase() == ignoredType.toLowerCase()) return true;
        }
      }
    }

    return false;
  }

  /// Sentry `beforeSend` callback.
  ///
  /// Returns `null` if the event should be dropped (not sent to Sentry),
  /// or returns the (optionally modified) [SentryEvent] to proceed with sending.
  static FutureOr<SentryEvent?> beforeSend(SentryEvent event, Hint hint) {
    if (shouldIgnore(event, hint)) {
      // Returning null tells Sentry to discard the event, preventing quota
      // consumption and keeping the dashboard clean.
      return null;
    }
    return event;
  }

  /// Collects all diagnostic text, messages, and values from the event.
  static List<String> _extractEventTexts(SentryEvent event, Hint hint) {
    final texts = <String>[];

    // Message
    final message = event.message;
    if (message != null) {
      if (message.formatted.isNotEmpty) {
        texts.add(message.formatted);
      }
      final template = message.template;
      if (template != null && template.isNotEmpty) {
        texts.add(template);
      }
    }

    // Exceptions list
    if (event.exceptions != null) {
      for (final ex in event.exceptions!) {
        if (ex.value != null && ex.value!.isNotEmpty) {
          texts.add(ex.value!);
        }
        if (ex.type != null && ex.type!.isNotEmpty) {
          texts.add(ex.type!);
        }
      }
    }

    // Throwable / FlutterErrorDetails
    final throwable = event.throwable;
    if (throwable != null) {
      if (throwable is FlutterErrorDetails) {
        texts.add(throwable.exceptionAsString());
        texts.add(throwable.summary.toString());
        texts.add(throwable.exception.toString());
      } else {
        texts.add(throwable.toString());
      }
    }

    return texts;
  }

  /// Collects exception type names from the event.
  static List<String> _extractExceptionTypes(SentryEvent event, Hint hint) {
    final types = <String>[];

    if (event.exceptions != null) {
      for (final ex in event.exceptions!) {
        if (ex.type != null && ex.type!.isNotEmpty) {
          types.add(ex.type!);
        }
      }
    }

    final throwable = event.throwable;
    if (throwable != null) {
      if (throwable is FlutterErrorDetails) {
        types.add(throwable.exception.runtimeType.toString());
      } else {
        types.add(throwable.runtimeType.toString());
      }
    }

    return types;
  }
}
