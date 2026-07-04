import 'package:eagly/features/logs/data/models/log_level.dart';

enum LogFilterField { message, packageName, pidTid, tag }

enum InlineFilterKey { message, packageName, pidTid, tag, level, age }

class LogFilters {
  const LogFilters({
    required this.messageText,
    required this.packageText,
    required this.pidTidText,
    required this.tagText,
    required this.messageTerms,
    required this.rawTerms,
    required this.packageTerms,
    required this.pidTidTerms,
    required this.tagTerms,
    required this.level,
    this.maxAge,
  });

  final String messageText;
  final String packageText;
  final String pidTidText;
  final String tagText;
  final List<String> messageTerms;
  final List<String> rawTerms;
  final List<String> packageTerms;
  final List<String> pidTidTerms;
  final List<String> tagTerms;
  final LogLevel level;

  /// When set, only entries whose timestamp is no older than this duration
  /// (relative to now) match. Parsed from the inline `age:` key (e.g. `1h`).
  final Duration? maxAge;

  /// An empty filter that only constrains by [level].
  factory LogFilters.empty(LogLevel level) => LogFilters(
    messageText: '',
    packageText: '',
    pidTidText: '',
    tagText: '',
    messageTerms: const [],
    rawTerms: const [],
    packageTerms: const [],
    pidTidTerms: const [],
    tagTerms: const [],
    level: level,
    maxAge: null,
  );

  /// Builds a filter from discrete classic-field values. Each field contributes
  /// a single (trimmed) term; the message field filters the message column only
  /// (no [rawTerms]).
  factory LogFilters.fromFields({
    required LogLevel level,
    String message = '',
    String package = '',
    String pidTid = '',
    String tag = '',
    Duration? maxAge,
  }) {
    List<String> single(String value) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? const [] : [trimmed];
    }

    return LogFilters(
      messageText: message.trim(),
      packageText: package.trim(),
      pidTidText: pidTid.trim(),
      tagText: tag.trim(),
      messageTerms: single(message),
      rawTerms: const [],
      packageTerms: single(package),
      pidTidTerms: single(pidTid),
      tagTerms: single(tag),
      level: level,
      maxAge: maxAge,
    );
  }

  LogFilters copyWith({LogLevel? level}) => LogFilters(
    messageText: messageText,
    packageText: packageText,
    pidTidText: pidTidText,
    tagText: tagText,
    messageTerms: messageTerms,
    rawTerms: rawTerms,
    packageTerms: packageTerms,
    pidTidTerms: pidTidTerms,
    tagTerms: tagTerms,
    level: level ?? this.level,
    maxAge: maxAge,
  );

  static LogFilters parse(
    String rawText, {
    required LogLevel fallbackLevel,
    required bool isIosLogContext,
  }) => _parseInlineFilters(
    rawText,
    fallbackLevel: fallbackLevel,
    isIosLogContext: isIosLogContext,
  );

  /// Serializes discrete filter fields into inline `key:value` syntax, the
  /// inverse of [parse]. The `level` token is emitted only when it differs from
  /// [defaultLevel]; blank fields are skipped.
  static String compose({
    required LogLevel level,
    required LogLevel defaultLevel,
    String package = '',
    String pidTid = '',
    String tag = '',
    String message = '',
    Duration? maxAge,
  }) {
    final tokens = <String>[];
    if (level != defaultLevel) {
      tokens.add(_composeToken('level', level.code));
    }
    if (maxAge != null) {
      tokens.add(_composeToken('age', formatMaxAge(maxAge)));
    }
    if (package.trim().isNotEmpty) {
      tokens.add(_composeToken('package', package));
    }
    if (pidTid.trim().isNotEmpty) {
      tokens.add(_composeToken('pid', pidTid));
    }
    if (tag.trim().isNotEmpty) {
      tokens.add(_composeToken('tag', tag));
    }
    if (message.trim().isNotEmpty) {
      tokens.add(_composeToken('message', message));
    }
    return tokens.where((token) => token.isNotEmpty).join(' ');
  }
}

/// Parses a human "max age" string into a [Duration]. Accepts a single unit
/// (`30s`, `15m`, `2h`, `1d`) or a compound of them (`1h30m`). Units are
/// s(econds), m(inutes), h(ours), d(ays); whitespace between groups is allowed.
/// Returns null when [value] has no recognizable component or resolves to zero.
Duration? parseMaxAge(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty) return null;
  if (!RegExp(r'^(?:\d+\s*[smhd]\s*)+$').hasMatch(trimmed)) return null;

  var total = Duration.zero;
  for (final match in RegExp(r'(\d+)\s*([smhd])').allMatches(trimmed)) {
    final amount = int.parse(match.group(1)!);
    total += switch (match.group(2)!) {
      's' => Duration(seconds: amount),
      'm' => Duration(minutes: amount),
      'h' => Duration(hours: amount),
      'd' => Duration(days: amount),
      _ => Duration.zero,
    };
  }
  return total == Duration.zero ? null : total;
}

/// Formats a [Duration] into the compact form understood by [parseMaxAge]
/// (e.g. `1h30m`), the inverse of parsing. Zero-valued components are omitted.
String formatMaxAge(Duration age) {
  var remaining = age;
  final parts = <String>[];

  void take(int amount, String unit) {
    if (amount > 0) parts.add('$amount$unit');
  }

  final days = remaining.inDays;
  take(days, 'd');
  remaining -= Duration(days: days);
  final hours = remaining.inHours;
  take(hours, 'h');
  remaining -= Duration(hours: hours);
  final minutes = remaining.inMinutes;
  take(minutes, 'm');
  remaining -= Duration(minutes: minutes);
  take(remaining.inSeconds, 's');

  return parts.isEmpty ? '0s' : parts.join();
}

String _composeToken(String key, String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return '';

  final needsQuotes =
      normalized.contains(RegExp(r'\s')) || normalized.contains('"');
  if (!needsQuotes) {
    return '$key:$normalized';
  }

  final escaped = normalized.replaceAll('"', r'\"');
  return '$key:"$escaped"';
}

LogFilters _parseInlineFilters(
  String rawText, {
  required LogLevel fallbackLevel,
  required bool isIosLogContext,
}) {
  final messageTerms = <String>[];
  final rawTerms = <String>[];
  final packageTerms = <String>[];
  final pidTidTerms = <String>[];
  final tagTerms = <String>[];
  var parsedLevel = fallbackLevel;
  Duration? parsedMaxAge;

  for (final token in _tokenizeInlineFilterText(rawText)) {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) continue;

    final colonIndex = trimmedToken.indexOf(':');
    if (colonIndex <= 0) {
      final messageValue = _normalizeInlineFilterValue(trimmedToken);
      if (messageValue.isNotEmpty) {
        rawTerms.add(messageValue);
      }
      continue;
    }

    final rawKey = trimmedToken.substring(0, colonIndex);
    final rawValue = trimmedToken.substring(colonIndex + 1);
    final key = _canonicalInlineFilterKey(rawKey);
    final value = _normalizeInlineFilterValue(rawValue);
    if (key == null || value.isEmpty) {
      final fallbackValue = _normalizeInlineFilterValue(trimmedToken);
      if (fallbackValue.isNotEmpty) {
        rawTerms.add(fallbackValue);
      }
      continue;
    }

    switch (key) {
      case InlineFilterKey.message:
        messageTerms.add(value);
      case InlineFilterKey.packageName:
        packageTerms.add(value);
      case InlineFilterKey.pidTid:
        pidTidTerms.add(value.toLowerCase());
      case InlineFilterKey.tag:
        tagTerms.add(value);
      case InlineFilterKey.level:
        parsedLevel = LogLevel.fromStored(
          value,
        ).normalizeSelectionForPlatform(isIos: isIosLogContext);
      case InlineFilterKey.age:
        final parsed = parseMaxAge(value);
        if (parsed != null) parsedMaxAge = parsed;
    }
  }

  final messageFieldTerms = <String>[...rawTerms, ...messageTerms];
  return LogFilters(
    messageText: messageFieldTerms.join(' '),
    packageText: packageTerms.join(' '),
    pidTidText: pidTidTerms.join(' '),
    tagText: tagTerms.join(' '),
    messageTerms: List.unmodifiable(messageTerms),
    rawTerms: List.unmodifiable(rawTerms),
    packageTerms: List.unmodifiable(packageTerms),
    pidTidTerms: List.unmodifiable(pidTidTerms),
    tagTerms: List.unmodifiable(tagTerms),
    level: parsedLevel,
    maxAge: parsedMaxAge,
  );
}

InlineFilterKey? _canonicalInlineFilterKey(String rawKey) {
  return switch (rawKey.trim().toLowerCase()) {
    'message' || 'msg' || 'text' => InlineFilterKey.message,
    'package' || 'pkg' || 'app' || 'process' => InlineFilterKey.packageName,
    'pid' || 'tid' || 'thread' || 'pidtid' => InlineFilterKey.pidTid,
    'tag' || 'category' => InlineFilterKey.tag,
    'level' || 'lvl' || 'priority' => InlineFilterKey.level,
    'age' || 'maxage' || 'since' => InlineFilterKey.age,
    _ => null,
  };
}

String _normalizeInlineFilterValue(String rawValue) {
  var normalized = rawValue.trim();
  if (normalized.length >= 2 &&
      normalized.startsWith('"') &&
      normalized.endsWith('"')) {
    normalized = normalized.substring(1, normalized.length - 1);
  }
  return normalized.replaceAll(r'\"', '"').trim();
}

List<String> _tokenizeInlineFilterText(String rawText) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (final rune in rawText.runes) {
    final char = String.fromCharCode(rune);
    if (char == '"') {
      inQuotes = !inQuotes;
      buffer.write(char);
      continue;
    }
    if (!inQuotes && RegExp(r'\s').hasMatch(char)) {
      final token = buffer.toString().trim();
      if (token.isNotEmpty) {
        tokens.add(token);
      }
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }

  final finalToken = buffer.toString().trim();
  if (finalToken.isNotEmpty) {
    tokens.add(finalToken);
  }
  return tokens;
}
