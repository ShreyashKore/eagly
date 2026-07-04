import 'package:eagly/features/logs/data/models/log_level.dart';

enum LogFilterField { message, packageName, pidTid, tag }

enum InlineFilterKey { message, packageName, pidTid, tag, level }

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
  }) {
    final tokens = <String>[];
    if (level != defaultLevel) {
      tokens.add(_composeToken('level', level.code));
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
  );
}

InlineFilterKey? _canonicalInlineFilterKey(String rawKey) {
  return switch (rawKey.trim().toLowerCase()) {
    'message' || 'msg' || 'text' => InlineFilterKey.message,
    'package' || 'pkg' || 'app' || 'process' => InlineFilterKey.packageName,
    'pid' || 'tid' || 'thread' || 'pidtid' => InlineFilterKey.pidTid,
    'tag' || 'category' => InlineFilterKey.tag,
    'level' || 'lvl' || 'priority' => InlineFilterKey.level,
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
