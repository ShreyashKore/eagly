import 'package:eagly/features/logs/data/models/log_level.dart';

enum LogFilterField { message, packageName, pidTid, tag }

enum InlineFilterKey { message, packageName, pidTid, tag, level, age }

/// How a [FilterTerm]'s value is compared against a candidate string. The
/// classic bar only ever produces [contains]; the inline bar's advanced syntax
/// (`[-]key[=|~]:value`) can also select [exact] (`=`) or [regex] (`~`).
enum FilterMatchMode { contains, exact, regex }

/// A single filter value, how it should be matched, and whether the result is
/// negated. Matching is always case-insensitive, matching the classic bar's
/// substring behaviour.
class FilterTerm {
  FilterTerm(
    this.value, {
    this.mode = FilterMatchMode.contains,
    this.negate = false,
  });

  final String value;
  final FilterMatchMode mode;
  final bool negate;

  /// Compiled form of a [FilterMatchMode.regex] [value]; null for other modes,
  /// an empty value, or a pattern that fails to compile. Built once, lazily.
  late final RegExp? _regExp = mode == FilterMatchMode.regex
      ? _tryCompileRegExp(value)
      : null;

  /// True when this is a regex term whose pattern failed to compile. A positive
  /// invalid-regex term matches nothing; negated, it matches everything.
  bool get hasInvalidRegex =>
      mode == FilterMatchMode.regex && value.isNotEmpty && _regExp == null;

  /// Whether [candidate] satisfies this term (with [negate] applied).
  bool matches(String candidate) => matchesAny([candidate]);

  /// Whether *any* of [candidates] satisfies this term. Negation is applied to
  /// the aggregate, so `-pid:1` excludes a log only when none of its pid/tid
  /// forms match.
  bool matchesAny(Iterable<String> candidates) {
    final matched = candidates.any(_rawMatches);
    return negate ? !matched : matched;
  }

  bool _rawMatches(String candidate) => switch (mode) {
    FilterMatchMode.contains => candidate.toLowerCase().contains(
      value.toLowerCase(),
    ),
    FilterMatchMode.exact => candidate.toLowerCase() == value.toLowerCase(),
    FilterMatchMode.regex => _regExp?.hasMatch(candidate) ?? false,
  };

  /// Serializes back to inline syntax under [key] (e.g. `-tag~:value`). The
  /// caller passes an already display-adjusted key.
  String toToken(String key) {
    final negation = negate ? '-' : '';
    final operator = switch (mode) {
      FilterMatchMode.contains => '',
      FilterMatchMode.exact => '=',
      FilterMatchMode.regex => '~',
    };
    return '$negation$key$operator:${_quoteFilterValue(value)}';
  }

  /// Compact, stable identity used by the filter-change signature.
  String get signature => '${negate ? '!' : ''}${mode.index}:$value';
}

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
  final List<FilterTerm> messageTerms;
  final List<FilterTerm> rawTerms;
  final List<FilterTerm> packageTerms;
  final List<FilterTerm> pidTidTerms;
  final List<FilterTerm> tagTerms;
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
  /// a single (trimmed) [FilterTerm.contains] term; the message field filters
  /// the message column only (no [rawTerms]).
  factory LogFilters.fromFields({
    required LogLevel level,
    String message = '',
    String package = '',
    String pidTid = '',
    String tag = '',
    Duration? maxAge,
  }) {
    List<FilterTerm> single(String value) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? const [] : [FilterTerm(trimmed)];
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

  /// Serializes [state] into inline `[-]key[=|~]:value` syntax, the inverse of
  /// [parse]. The `level` token is emitted only when it differs from
  /// [defaultLevel]; raw terms are emitted as bare words. On iOS the tag key is
  /// surfaced as `category:` to match the inline bar's display.
  static String compose(
    LogFilters state, {
    required LogLevel defaultLevel,
    required bool isIos,
  }) {
    final tokens = <String>[];
    if (state.level != defaultLevel) {
      tokens.add('level:${state.level.code}');
    }
    final maxAge = state.maxAge;
    if (maxAge != null) {
      tokens.add('age:${formatMaxAge(maxAge)}');
    }
    for (final term in state.packageTerms) {
      tokens.add(term.toToken('package'));
    }
    for (final term in state.pidTidTerms) {
      tokens.add(term.toToken('pid'));
    }
    final tagKey = isIos ? 'category' : 'tag';
    for (final term in state.tagTerms) {
      tokens.add(term.toToken(tagKey));
    }
    for (final term in state.messageTerms) {
      tokens.add(term.toToken('message'));
    }
    for (final term in state.rawTerms) {
      tokens.add(_quoteFilterValue(term.value));
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

RegExp? _tryCompileRegExp(String pattern) {
  if (pattern.isEmpty) return null;
  try {
    return RegExp(pattern, caseSensitive: false, multiLine: true);
  } on FormatException {
    return null;
  }
}

/// Quotes a filter value for inline serialization when it contains whitespace or
/// a double quote, escaping embedded quotes. Plain values pass through as-is.
String _quoteFilterValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';

  final needsQuotes = trimmed.contains(RegExp(r'\s')) || trimmed.contains('"');
  if (!needsQuotes) return trimmed;

  final escaped = trimmed.replaceAll('"', r'\"');
  return '"$escaped"';
}

/// Space-joined values of the plain (case-insensitive contains, non-negated)
/// terms — the only form the classic bar's single-value fields can represent.
/// Advanced terms are omitted, so switching an advanced inline filter to the
/// classic bar shows an empty field rather than a corrupted value.
String _plainValues(List<FilterTerm> terms) => terms
    .where((term) => term.mode == FilterMatchMode.contains && !term.negate)
    .map((term) => term.value)
    .join(' ');

LogFilters _parseInlineFilters(
  String rawText, {
  required LogLevel fallbackLevel,
  required bool isIosLogContext,
}) {
  final messageTerms = <FilterTerm>[];
  final rawTerms = <FilterTerm>[];
  final packageTerms = <FilterTerm>[];
  final pidTidTerms = <FilterTerm>[];
  final tagTerms = <FilterTerm>[];
  var parsedLevel = fallbackLevel;
  Duration? parsedMaxAge;

  for (final token in _tokenizeInlineFilterText(rawText)) {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) continue;

    final parsed = _parseKeyedToken(trimmedToken);
    if (parsed == null) {
      // Not a recognised keyed filter → the whole token is a raw contains term.
      // Bare words (including a leading '-') are always literal.
      final rawValue = _normalizeInlineFilterValue(trimmedToken);
      if (rawValue.isNotEmpty) rawTerms.add(FilterTerm(rawValue));
      continue;
    }

    final term = FilterTerm(
      parsed.value,
      mode: parsed.mode,
      negate: parsed.negate,
    );
    switch (parsed.key) {
      case InlineFilterKey.message:
        messageTerms.add(term);
      case InlineFilterKey.packageName:
        packageTerms.add(term);
      case InlineFilterKey.pidTid:
        pidTidTerms.add(term);
      case InlineFilterKey.tag:
        tagTerms.add(term);
      case InlineFilterKey.level:
        // Level is a hierarchy threshold; operators/negation don't apply.
        parsedLevel = LogLevel.fromStored(
          parsed.value,
        ).normalizeSelectionForPlatform(isIos: isIosLogContext);
      case InlineFilterKey.age:
        final parsedAge = parseMaxAge(parsed.value);
        if (parsedAge != null) parsedMaxAge = parsedAge;
    }
  }

  return LogFilters(
    messageText: _plainValues([...rawTerms, ...messageTerms]),
    packageText: _plainValues(packageTerms),
    pidTidText: _plainValues(pidTidTerms),
    tagText: _plainValues(tagTerms),
    messageTerms: List.unmodifiable(messageTerms),
    rawTerms: List.unmodifiable(rawTerms),
    packageTerms: List.unmodifiable(packageTerms),
    pidTidTerms: List.unmodifiable(pidTidTerms),
    tagTerms: List.unmodifiable(tagTerms),
    level: parsedLevel,
    maxAge: parsedMaxAge,
  );
}

/// The key, value, match mode, and negation extracted from a single inline
/// token shaped `[-]key[=|~]:value`.
class _KeyedToken {
  const _KeyedToken(this.key, this.value, this.mode, this.negate);

  final InlineFilterKey key;
  final String value;
  final FilterMatchMode mode;
  final bool negate;
}

/// Parses [token] as an advanced keyed filter, or returns null when it is not a
/// recognised `key:value` (so the caller keeps it as a literal raw term). A
/// leading `-` negates; a trailing `=`/`~` on the key selects exact/regex.
_KeyedToken? _parseKeyedToken(String token) {
  var rest = token;
  var negate = false;
  if (rest.length > 1 && rest.startsWith('-')) {
    negate = true;
    rest = rest.substring(1);
  }

  final colonIndex = rest.indexOf(':');
  if (colonIndex <= 0) return null;

  var keyText = rest.substring(0, colonIndex);
  final rawValue = rest.substring(colonIndex + 1);

  var mode = FilterMatchMode.contains;
  if (keyText.endsWith('=')) {
    mode = FilterMatchMode.exact;
    keyText = keyText.substring(0, keyText.length - 1);
  } else if (keyText.endsWith('~')) {
    mode = FilterMatchMode.regex;
    keyText = keyText.substring(0, keyText.length - 1);
  }

  final key = _canonicalInlineFilterKey(keyText);
  final value = _normalizeInlineFilterValue(rawValue);
  if (key == null || value.isEmpty) return null;
  return _KeyedToken(key, value, mode, negate);
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
