import 'dart:collection';
import 'dart:math' as math;

import 'package:sentry_flutter/sentry_flutter.dart';

/// [Hint] key [AppBreadcrumbs] sets to say which of its methods produced a
/// breadcrumb, so [SentryBreadcrumbFilter] can tell a mirrored app-log line
/// from a deliberate user/app action. Values are [BreadcrumbOrigin] names.
const String breadcrumbOriginHintKey = 'eagly.breadcrumb_origin';

/// Which [AppBreadcrumbs] method produced a breadcrumb.
enum BreadcrumbOrigin { appLog, action, navigation }

/// Bounds how many breadcrumbs reach Sentry's scope, and so its native sync.
///
/// **Why.** On macOS every Dart breadcrumb is synced to sentry-cocoa over a
/// method channel that runs on the main thread: `SentryFlutterPlugin
/// .addBreadcrumb` builds a `SentryBreadcrumb` from a dictionary (ISO-8601
/// parse through `NSDateFormatter`), adds it to the native scope, and
/// SentryCrash serialises it into its crash-time scope copy. That is cheap
/// once and a multi-second hang at storm rates — FLUTTER-M3/M4/M5, where the
/// trail held ~100 identical `Found 4 device(s)` lines 50 ms apart.
///
/// **Why not turn the sync off.** `options.enableScopeSync = false` would
/// stop the cost, but native app-hang and native crash reports (the M-series
/// themselves, the log-flood hang, Impeller crashes) carry Dart breadcrumbs —
/// and the user id set in `main.dart` — only through that sync, and those
/// trails are how the device-tab → log restart crash and the adb storm were
/// diagnosed. So the sync stays on and this filter bounds what feeds it:
///
/// 1. **Dropped:** `console` breadcrumbs (`print`/`debugPrint`, which also
///    echo every Flutter error that is already its own event) and anything at
///    [SentryLevel.debug].
/// 2. **Collapsed:** an identical breadcrumb (category + level + message)
///    passes at most once per [duplicateWindow]; the next one to pass after
///    the window carries `repeated: n`, the copies folded away in between.
///    Deliberate actions, navigation and `ui.*` taps are never collapsed —
///    two identical "Started live logging" crumbs a second apart *are* the
///    evidence.
/// 3. **Rate-limited:** token buckets per category and per class. Priority
///    breadcrumbs (actions, navigation, `ui.*`, warnings and errors) draw on
///    buckets of their own, so a storm of info lines can't starve them, but
///    they are bounded too. The next breadcrumb to pass in a category carries
///    `rate_limited: n`, the ones dropped since the last one passed.
/// 4. **Trimmed:** long messages and string data values are cut to
///    [maxTextLength], which bounds the native serialisation per crumb.
///
/// With the defaults, sustained input of any shape reaches native at about
/// three breadcrumbs a second, with bursts of at most ~100 — the size of the
/// breadcrumb ring itself.
///
/// **Replays.** When a Dart event is captured on Cocoa, sentry_flutter's
/// `LoadContextsIntegration` loads the native breadcrumbs and runs each one
/// through `beforeBreadcrumb` again. Those already passed (or are native-only)
/// and must not be collapsed against themselves, so a breadcrumb older than
/// the newest one already seen passes untouched and leaves the state alone.
/// Native copies keep milliseconds and Dart stamps microseconds, so a copy
/// sorts before its original. *Equal* stamps count as live: on a clock with
/// coarse ticks (Windows) a storm shares one stamp and must still be
/// filtered.
class SentryBreadcrumbFilter {
  SentryBreadcrumbFilter({
    DateTime Function()? clock,
    this.duplicateWindow = const Duration(seconds: 30),
    this.categoryBurst = 15,
    this.categoryPerSecond = 0.5,
    this.noiseBurst = 40,
    this.noisePerSecond = 1,
    this.priorityCategoryBurst = 20,
    this.priorityCategoryPerSecond = 1,
    this.priorityBurst = 60,
    this.priorityPerSecond = 2,
    this.maxTextLength = 1024,
  }) : _clock = clock ?? _utcNow;

  /// The filter `main.dart` installs.
  static final SentryBreadcrumbFilter instance = SentryBreadcrumbFilter();

  /// Sentry `beforeBreadcrumb` callback.
  static Breadcrumb? beforeBreadcrumb(Breadcrumb? breadcrumb, Hint hint) =>
      instance.filter(breadcrumb, hint);

  /// Data key on a breadcrumb that stands for identical ones collapsed away.
  static const String repeatedKey = 'repeated';

  /// Data key on a breadcrumb counting ones its category lost to the limit.
  static const String rateLimitedKey = 'rate_limited';

  static const int _maxTrackedKeys = 256;
  static const int _maxTrackedCategories = 128;

  // A clock that steps back further than this resets the replay watermark,
  // so live breadcrumbs aren't all mistaken for replays.
  static const Duration _clockStepTolerance = Duration(seconds: 1);

  final DateTime Function() _clock;

  /// How long an identical breadcrumb is collapsed after one passes.
  final Duration duplicateWindow;

  /// Per-category bucket for ordinary breadcrumbs.
  final int categoryBurst;
  final double categoryPerSecond;

  /// Bucket shared by all ordinary breadcrumbs.
  final int noiseBurst;
  final double noisePerSecond;

  /// Per-category bucket for priority breadcrumbs.
  final int priorityCategoryBurst;
  final double priorityCategoryPerSecond;

  /// Bucket shared by all priority breadcrumbs.
  final int priorityBurst;
  final double priorityPerSecond;

  /// Longest message or string data value kept, in UTF-16 code units.
  final int maxTextLength;

  final LinkedHashMap<String, _Run> _runs = LinkedHashMap<String, _Run>();
  final LinkedHashMap<String, _TokenBucket> _categoryBuckets =
      LinkedHashMap<String, _TokenBucket>();
  final Map<String, int> _rateLimited = <String, int>{};
  late final _TokenBucket _noiseBucket = _TokenBucket(
    noiseBurst,
    noisePerSecond,
  );
  late final _TokenBucket _priorityBucket = _TokenBucket(
    priorityBurst,
    priorityPerSecond,
  );
  DateTime? _newestSeen;

  /// Returns [breadcrumb] (possibly annotated or trimmed) to keep it, or
  /// `null` to drop it.
  Breadcrumb? filter(Breadcrumb? breadcrumb, Hint hint) {
    if (breadcrumb == null) return null;
    final now = _clock();

    final newest = _newestSeen;
    if (newest != null && newest.isAfter(now.add(_clockStepTolerance))) {
      _newestSeen = null;
    } else if (newest != null && breadcrumb.timestamp.isBefore(newest)) {
      return breadcrumb;
    }
    _newestSeen = breadcrumb.timestamp;

    if (_isNoise(breadcrumb)) return null;

    final origin = _originOf(hint);
    final deliberate = _isDeliberate(breadcrumb, origin);
    final priority = deliberate || _isAtLeastWarning(breadcrumb.level);

    String? runKey;
    _Run? run;
    if (!deliberate) {
      runKey = _runKeyOf(breadcrumb);
      run = _runs[runKey];
      if (run != null && now.difference(run.passedAt) < duplicateWindow) {
        run.suppressed++;
        return null;
      }
    }

    final category = breadcrumb.category ?? '';
    final bucketKey = priority ? '!$category' : category;
    final categoryBucket = _categoryBucketFor(bucketKey, priority);
    final sharedBucket = priority ? _priorityBucket : _noiseBucket;
    if (!categoryBucket.canTake(now) || !sharedBucket.canTake(now)) {
      _rateLimited[bucketKey] = (_rateLimited[bucketKey] ?? 0) + 1;
      return null;
    }
    categoryBucket.take();
    sharedBucket.take();

    final repeated = run?.suppressed ?? 0;
    final rateLimited = _rateLimited.remove(bucketKey) ?? 0;
    if (runKey != null) {
      _runs.remove(runKey);
      _runs[runKey] = _Run(now);
      if (_runs.length > _maxTrackedKeys) _runs.remove(_runs.keys.first);
    }

    _trim(breadcrumb);
    if (repeated > 0 || rateLimited > 0) {
      breadcrumb.data = <String, dynamic>{
        ...?breadcrumb.data,
        if (repeated > 0) repeatedKey: repeated,
        if (rateLimited > 0) rateLimitedKey: rateLimited,
      };
    }
    return breadcrumb;
  }

  // ── Classification ──────────────────────────────────────────────────────

  static bool _isNoise(Breadcrumb breadcrumb) =>
      breadcrumb.category == 'console' || breadcrumb.level == SentryLevel.debug;

  static BreadcrumbOrigin? _originOf(Hint hint) {
    final value = hint.get(breadcrumbOriginHintKey);
    for (final origin in BreadcrumbOrigin.values) {
      if (origin.name == value) return origin;
    }
    return null;
  }

  /// A breadcrumb something chose to record as an event in the journey,
  /// rather than a log line: never collapsed, always on priority buckets.
  static bool _isDeliberate(Breadcrumb breadcrumb, BreadcrumbOrigin? origin) {
    if (origin == BreadcrumbOrigin.action ||
        origin == BreadcrumbOrigin.navigation) {
      return true;
    }
    if (origin == BreadcrumbOrigin.appLog) return false;
    final type = breadcrumb.type;
    return type == 'navigation' ||
        type == 'user' ||
        (breadcrumb.category?.startsWith('ui.') ?? false);
  }

  static bool _isAtLeastWarning(SentryLevel? level) =>
      level == SentryLevel.warning ||
      level == SentryLevel.error ||
      level == SentryLevel.fatal;

  static String _runKeyOf(Breadcrumb breadcrumb) {
    final message = breadcrumb.message ?? breadcrumb.data?.toString() ?? '';
    return '${breadcrumb.category}\u0000${breadcrumb.level?.name}\u0000'
        '$message';
  }

  // ── State ───────────────────────────────────────────────────────────────

  _TokenBucket _categoryBucketFor(String key, bool priority) {
    final existing = _categoryBuckets[key];
    if (existing != null) return existing;
    final bucket = priority
        ? _TokenBucket(priorityCategoryBurst, priorityCategoryPerSecond)
        : _TokenBucket(categoryBurst, categoryPerSecond);
    _categoryBuckets[key] = bucket;
    if (_categoryBuckets.length > _maxTrackedCategories) {
      final evicted = _categoryBuckets.keys.first;
      _categoryBuckets.remove(evicted);
      _rateLimited.remove(evicted);
    }
    return bucket;
  }

  void _trim(Breadcrumb breadcrumb) {
    final message = breadcrumb.message;
    if (message != null && message.length > maxTextLength) {
      breadcrumb.message = _truncate(message);
    }
    final data = breadcrumb.data;
    if (data == null) return;
    if (!data.values.any((v) => v is String && v.length > maxTextLength)) {
      return;
    }
    breadcrumb.data = <String, dynamic>{
      for (final MapEntry(:key, :value) in data.entries)
        key: value is String && value.length > maxTextLength
            ? _truncate(value)
            : value,
    };
  }

  String _truncate(String text) => '${text.substring(0, maxTextLength)}…';

  static DateTime _utcNow() => DateTime.now().toUtc();
}

class _Run {
  _Run(this.passedAt);

  final DateTime passedAt;
  int suppressed = 0;
}

/// Classic token bucket: holds up to [capacity] tokens, refilled at
/// [perSecond]; a breadcrumb costs one.
class _TokenBucket {
  _TokenBucket(this.capacity, this.perSecond) : _tokens = capacity.toDouble();

  final int capacity;
  final double perSecond;
  double _tokens;
  DateTime? _refilledAt;

  bool canTake(DateTime now) {
    final last = _refilledAt;
    if (last != null && now.isAfter(last)) {
      final seconds = now.difference(last).inMicroseconds / 1e6;
      _tokens = math.min(capacity.toDouble(), _tokens + seconds * perSecond);
    }
    if (last == null || now.isAfter(last)) _refilledAt = now;
    return _tokens >= 1;
  }

  void take() => _tokens -= 1;
}
