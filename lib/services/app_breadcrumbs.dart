import 'package:sentry_flutter/sentry_flutter.dart';

/// Central place for turning app-internal events into Sentry breadcrumbs, so
/// a crash/error report can be replayed as a user journey: which device was
/// selected, which pane was open, what tool command ran, what failed.
///
/// Kept dependency-free of [AppLogger] (only depends on `sentry_flutter`) so
/// `app_logger.dart` can import this without a cycle.
class AppBreadcrumbs {
  AppBreadcrumbs._();

  /// Mirrors an [AppLogger] entry (already used across tools/services) as a
  /// breadcrumb. `level` is the raw `AppLogLevel.name` (debug/info/success/
  /// warning/error).
  static void log({
    required String level,
    required String source,
    required String message,
    String? detail,
    String? sessionTag,
  }) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: source,
        level: _levelFromName(level),
        data: {
          if (sessionTag != null) 'session': sessionTag,
          if (detail != null && detail.isNotEmpty) 'detail': detail,
        },
      ),
    );
  }

  /// Records a pane/tab/workspace transition, rendered by Sentry as a
  /// navigation breadcrumb (`from` -> `to`).
  static void navigation({
    required String from,
    required String to,
    String category = 'navigation',
    Map<String, dynamic>? data,
  }) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        type: 'navigation',
        category: category,
        message: '$from -> $to',
        data: {'from': from, 'to': to, ...?data},
      ),
    );
  }

  /// Records a discrete user/app action that isn't a navigation or an
  /// [AppLogger] entry (e.g. "install started", "mirror stopped").
  static void action(
    String message, {
    String category = 'action',
    SentryLevel level = SentryLevel.info,
    Map<String, dynamic>? data,
  }) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: category,
        level: level,
        data: data,
      ),
    );
  }

  static SentryLevel _levelFromName(String level) {
    switch (level) {
      case 'debug':
        return SentryLevel.debug;
      case 'warning':
        return SentryLevel.warning;
      case 'error':
        return SentryLevel.error;
      case 'info':
      case 'success':
      default:
        return SentryLevel.info;
    }
  }
}
