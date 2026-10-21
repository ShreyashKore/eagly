import 'package:flutter/foundation.dart';

import 'network_transaction.dart';

/// The status buckets the Network pane's toggle chips filter on.
enum NetworkStatusClass(final String label, final String description) {
  success('2xx', 'Successful responses'),
  redirect('3xx', 'Redirects'),
  clientError('4xx', 'Client errors'),
  serverError('5xx', 'Server errors'),
  failed('Failed', 'No response: a connection error, timeout or cancel'),
  pending('Pending', 'Still waiting for the response');

  /// The bucket [transaction] falls in. A 1xx answer counts as a success.
  static NetworkStatusClass of(NetworkTransaction transaction) =>
      switch (transaction.state) {
        NetworkTransactionState.pending => pending,
        NetworkTransactionState.failed => failed,
        NetworkTransactionState.complete =>
          switch (transaction.response?.code) {
            final code? when code >= 500 => serverError,
            final code? when code >= 400 => clientError,
            final code? when code >= 300 => redirect,
            _ => success,
          },
      };
}

/// What kind of payload an exchange carries, the way DevTools' type chips
/// group requests. Decided by the response's content type, or the request's
/// when there is no response yet.
enum NetworkResourceType(final String label, final String description) {
  json('JSON', 'JSON and other +json payloads'),
  document('Doc', 'HTML and XML'),
  text('Text', 'Plain text, CSS, JavaScript, CSV, form data'),
  image('Img', 'Images'),
  media('Media', 'Audio and video'),
  other('Other', 'Anything else, and exchanges with no content type');

  static NetworkResourceType of(NetworkTransaction transaction) =>
      fromContentType(
        transaction.response?.contentType ?? transaction.request.contentType,
      );

  static NetworkResourceType fromContentType(String? contentType) {
    final type = contentType?.split(';').first.trim().toLowerCase() ?? '';
    if (type.isEmpty) return other;
    if (type.endsWith('json') || type.endsWith('+json')) return json;
    if (type.contains('html') || type.endsWith('xml')) return document;
    if (type.startsWith('image/')) return image;
    if (type.startsWith('audio/') || type.startsWith('video/')) return media;
    if (type.startsWith('text/') ||
        type.contains('javascript') ||
        type == 'application/x-www-form-urlencoded' ||
        type.startsWith('multipart/')) {
      return text;
    }
    return other;
  }
}

/// A slice of the capture's timeline, picked by dragging across the overview.
/// An exchange is inside when any part of it overlaps the slice.
class const NetworkTimeWindow(final DateTime start, final DateTime end) {
  bool overlaps(DateTime from, DateTime to) =>
      !to.isBefore(start) && !from.isAfter(end);

  @override
  bool operator ==(Object other) =>
      other is NetworkTimeWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// One key the filter field understands, with what it matches. The pane's
/// suggestions and its syntax help are both built from [networkFilterKeys].
class const NetworkFilterKey(
  final String name,
  final String description, {
  final List<String> aliases = const [],
  final String example = '',
});

const networkFilterKeys = [
  NetworkFilterKey(
    'domain',
    'Host name; * is a wildcard',
    aliases: ['host'],
    example: 'domain:*.example.com',
  ),
  NetworkFilterKey('path', 'Text in the path', example: 'path:/users'),
  NetworkFilterKey('method', 'HTTP method', example: 'method:POST'),
  NetworkFilterKey(
    'status-code',
    'Status code; x is a wildcard digit',
    aliases: ['status'],
    example: 'status-code:4xx',
  ),
  NetworkFilterKey(
    'mime-type',
    'Text in the content type',
    aliases: ['type'],
    example: 'mime-type:json',
  ),
  NetworkFilterKey(
    'larger-than',
    'Response size, in bytes or with k / m',
    example: 'larger-than:10k',
  ),
  NetworkFilterKey(
    'slower-than',
    'Time taken, in ms or with s',
    example: 'slower-than:500ms',
  ),
  NetworkFilterKey(
    'is',
    'pending, failed, error (4xx/5xx/failed) or overridden',
    example: 'is:failed',
  ),
  NetworkFilterKey('scheme', 'URL scheme', example: 'scheme:http'),
  NetworkFilterKey(
    'has-request-header',
    'A request header is present',
    example: 'has-request-header:authorization',
  ),
  NetworkFilterKey(
    'has-response-header',
    'A response header is present',
    example: 'has-response-header:set-cookie',
  ),
  NetworkFilterKey(
    'source',
    'Text in the app or file it came from',
    example: 'source:sample',
  ),
];

/// The values `is:` accepts.
const networkFilterIsValues = ['pending', 'failed', 'error', 'overridden'];

/// What the Network list shows: a DevTools-style query plus the status and
/// type toggles and the timeline window. An empty set of toggles means "all".
///
/// The query is space-separated terms, all of which must match:
/// - bare text matches anywhere in the URL, case-insensitively;
/// - `/regex/` matches the URL against a regular expression;
/// - `key:value` matches one property (see [networkFilterKeys]);
/// - a leading `-` negates a term;
/// - `"double quotes"` keep spaces inside one term.
///
/// Immutable; the parsed terms are built on first use.
class NetworkFilter({
  final String query = '',
  final Set<NetworkStatusClass> statusClasses = const {},
  final Set<NetworkResourceType> types = const {},
  final NetworkTimeWindow? timeWindow,
}) {
  static final NetworkFilter none = NetworkFilter();

  late final List<_Term> _terms = _parse(query);

  /// Whether anything is hidden by this filter.
  bool get isActive =>
      _terms.isNotEmpty ||
      statusClasses.isNotEmpty ||
      types.isNotEmpty ||
      timeWindow != null;

  /// The first query term that could not be understood (a broken regex), or
  /// null. Such a term is ignored rather than hiding everything.
  String? get error {
    for (final term in _terms) {
      if (term.error case final error?) return error;
    }
    return null;
  }

  NetworkFilter copyWith({
    String? query,
    Set<NetworkStatusClass>? statusClasses,
    Set<NetworkResourceType>? types,
    NetworkTimeWindow? Function()? timeWindow,
  }) => NetworkFilter(
    query: query ?? this.query,
    statusClasses: statusClasses ?? this.statusClasses,
    types: types ?? this.types,
    timeWindow: timeWindow == null ? this.timeWindow : timeWindow(),
  );

  /// This filter with [term] added to the query, unless it is already there.
  /// Terms with spaces are quoted.
  NetworkFilter withTerm(String term) {
    final tokens = tokenizeNetworkQuery(query);
    if (tokens.contains(term)) return this;
    final quoted = _quoteIfNeeded(term);
    final trimmed = query.trimRight();
    return copyWith(query: trimmed.isEmpty ? quoted : '$trimmed $quoted');
  }

  /// Whether [transaction], delivered by the source labelled [sourceLabel],
  /// passes every part of this filter.
  bool matches(NetworkTransaction transaction, {String? sourceLabel}) {
    if (statusClasses.isNotEmpty &&
        !statusClasses.contains(NetworkStatusClass.of(transaction))) {
      return false;
    }
    if (types.isNotEmpty &&
        !types.contains(NetworkResourceType.of(transaction))) {
      return false;
    }
    if (timeWindow case final window?) {
      final start = transaction.startedAt;
      if (start == null) return false;
      final end =
          transaction.finishedAt ??
          (transaction.elapsed == null
              ? start
              : start.add(transaction.elapsed!));
      if (!window.overlaps(start, end)) return false;
    }
    for (final term in _terms) {
      if (term.error != null) continue;
      if (term.test(transaction, sourceLabel) == term.negated) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is NetworkFilter &&
      other.query == query &&
      setEquals(other.statusClasses, statusClasses) &&
      setEquals(other.types, types) &&
      other.timeWindow == timeWindow;

  @override
  int get hashCode => Object.hash(
    query,
    Object.hashAllUnordered(statusClasses),
    Object.hashAllUnordered(types),
    timeWindow,
  );
}

/// Splits [query] into terms on whitespace, keeping `"quoted runs"` together
/// (the quotes are dropped).
List<String> tokenizeNetworkQuery(String query) {
  final tokens = <String>[];
  final current = StringBuffer();
  var quoted = false;
  for (final rune in query.runes) {
    final char = String.fromCharCode(rune);
    if (char == '"') {
      quoted = !quoted;
    } else if (!quoted && char.trim().isEmpty) {
      if (current.isNotEmpty) tokens.add(current.toString());
      current.clear();
    } else {
      current.write(char);
    }
  }
  if (current.isNotEmpty) tokens.add(current.toString());
  return tokens;
}

String _quoteIfNeeded(String term) {
  if (!term.contains(RegExp(r'\s'))) return term;
  final negated = term.startsWith('-');
  final body = negated ? term.substring(1) : term;
  final colon = body.indexOf(':');
  if (colon <= 0) return '${negated ? '-' : ''}"$body"';
  return '${negated ? '-' : ''}${body.substring(0, colon + 1)}'
      '"${body.substring(colon + 1)}"';
}

class _Term {
  _Term(this.negated, this.test, {this.error});

  final bool negated;
  final bool Function(NetworkTransaction transaction, String? source) test;
  final String? error;
}

List<_Term> _parse(String query) => [
  for (final token in tokenizeNetworkQuery(query))
    if (_parseTerm(token) case final term?) term,
];

_Term? _parseTerm(String token) {
  var negated = false;
  var body = token;
  if (body.length > 1 && body.startsWith('-')) {
    negated = true;
    body = body.substring(1);
  }
  if (body.isEmpty) return null;

  if (body.length > 2 && body.startsWith('/') && body.endsWith('/')) {
    try {
      final pattern = RegExp(
        body.substring(1, body.length - 1),
        caseSensitive: false,
      );
      return _Term(negated, (t, _) => pattern.hasMatch(t.request.url));
    } on FormatException catch (error) {
      return _Term(negated, (_, _) => true, error: error.message);
    }
  }

  final colon = body.indexOf(':');
  if (colon > 0) {
    final key = body.substring(0, colon).toLowerCase();
    final value = body.substring(colon + 1);
    if (value.isEmpty) return null;
    final test = _keyTest(key, value);
    if (test != null) return _Term(negated, test);
  }

  final needle = body.toLowerCase();
  return _Term(negated, (t, _) => t.request.url.toLowerCase().contains(needle));
}

bool Function(NetworkTransaction, String?)? _keyTest(String key, String raw) {
  final value = raw.toLowerCase();
  switch (key) {
    case 'domain' || 'host':
      final pattern = _wildcard(value);
      return (t, _) => pattern.hasMatch(t.request.uri?.host ?? '');
    case 'path':
      return (t, _) =>
          (t.request.uri?.path ?? t.request.url).toLowerCase().contains(value);
    case 'method':
      return (t, _) => t.request.method.toLowerCase() == value;
    case 'status-code' || 'status':
      final pattern = RegExp(
        '^${RegExp.escape(value).replaceAll(RegExp('[x*]'), r'\d')}\$',
      );
      return (t, _) {
        final code = t.response?.code;
        return code != null && pattern.hasMatch('$code');
      };
    case 'mime-type' || 'type':
      return (t, _) => (t.response?.contentType ?? t.request.contentType ?? '')
          .toLowerCase()
          .contains(value);
    case 'larger-than':
      final bytes = parseNetworkSize(value);
      if (bytes == null) return null;
      return (t, _) => (t.response?.size ?? 0) > bytes;
    case 'slower-than':
      final limit = parseNetworkDuration(value);
      if (limit == null) return null;
      return (t, _) {
        final elapsed = t.elapsed;
        return elapsed != null && elapsed > limit;
      };
    case 'is':
      return switch (value) {
        'pending' ||
        'running' => (t, _) => t.state == NetworkTransactionState.pending,
        'failed' => (t, _) => t.state == NetworkTransactionState.failed,
        'error' =>
          (t, _) =>
              t.state == NetworkTransactionState.failed ||
              (t.response?.code ?? 0) >= 400,
        'overridden' || 'mocked' => (t, _) => t.override != null,
        'complete' ||
        'finished' => (t, _) => t.state == NetworkTransactionState.complete,
        _ => null,
      };
    case 'scheme':
      return (t, _) => t.request.uri?.scheme.toLowerCase() == value;
    case 'has-request-header':
      return (t, _) =>
          t.request.headers.any((h) => h.name.toLowerCase() == value);
    case 'has-response-header':
      return (t, _) =>
          t.response?.headers.any((h) => h.name.toLowerCase() == value) ??
          false;
    case 'source':
      return (_, source) => source?.toLowerCase().contains(value) ?? false;
  }
  return null;
}

RegExp _wildcard(String value) => RegExp(
  '^${value.split('*').map(RegExp.escape).join('.*')}\$',
  caseSensitive: false,
);

/// `512`, `10k`, `1.5m` (powers of 1024) as bytes; null when unreadable.
@visibleForTesting
int? parseNetworkSize(String value) {
  final match = RegExp(r'^(\d+(?:\.\d+)?)\s*([kmg]?)b?$').firstMatch(value);
  if (match == null) return null;
  final number = double.parse(match[1]!);
  final multiplier = switch (match[2]) {
    'k' => 1024,
    'm' => 1024 * 1024,
    'g' => 1024 * 1024 * 1024,
    _ => 1,
  };
  return (number * multiplier).round();
}

/// `250`, `250ms`, `1.5s`, `2m` as a duration; a bare number is milliseconds.
@visibleForTesting
Duration? parseNetworkDuration(String value) {
  final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(ms|s|m|min)?$').firstMatch(value);
  if (match == null) return null;
  final number = double.parse(match[1]!);
  final ms = switch (match[2]) {
    's' => number * 1000,
    'm' || 'min' => number * 60000,
    _ => number,
  };
  return Duration(microseconds: (ms * 1000).round());
}
