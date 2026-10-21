import 'dart:convert';
import 'dart:typed_data';

import 'network_transaction.dart';

/// One HAR entry's worth: a transaction and whichever of its bodies are known.
class const HarEntry(
  final NetworkTransaction transaction, {
  final Map<NetworkBodyPart, NetworkBody> bodies = const {},
});

/// Encodes [entries] as a HAR 1.2 document — the format Chrome, Firefox,
/// proxies and Inspektor all export, so a capture opens in any of them.
///
/// HAR has no field for a few things the Network pane knows; those travel as
/// `_`-prefixed custom fields, which the spec allows and readers ignore:
/// `_error` (also Chrome's name), `_adapter`, and `_encoding` on a binary
/// request body. HAR also has no notion of an unfinished request: a pending
/// one is written with status 0 and `_pending: true`.
String encodeHar(
  Iterable<HarEntry> entries, {
  required String creatorName,
  required String creatorVersion,
}) {
  final document = {
    'log': {
      'version': '1.2',
      'creator': {'name': creatorName, 'version': creatorVersion},
      'pages': const <Object>[],
      'entries': [for (final entry in entries) _entryToJson(entry)],
    },
  };
  return const JsonEncoder.withIndent('  ').convert(document);
}

/// Decodes a HAR document into entries, numbering them from 1 in file order.
/// Entries without a URL are skipped. Throws a [FormatException] whose
/// message can be shown as-is when [text] is not a HAR at all.
List<HarEntry> decodeHar(String text) {
  final Object? document;
  try {
    document = jsonDecode(text);
  } on FormatException {
    throw const FormatException('This file is not JSON, so it is not a HAR.');
  }
  final log = document is Map<String, Object?> ? document['log'] : null;
  final entries = log is Map<String, Object?> ? log['entries'] : null;
  if (entries is! List) {
    throw const FormatException('This file is not a HAR: it has no entries.');
  }
  return [
    for (final (index, entry) in entries.indexed)
      if (entry is Map<String, Object?>)
        if (_entryFromJson('${index + 1}', entry) case final decoded?) decoded,
  ];
}

// ── Encoding ────────────────────────────────────────────────────────────

Map<String, Object?> _entryToJson(HarEntry entry) {
  final tx = entry.transaction;
  final request = tx.request;
  final response = tx.response;
  final started =
      tx.startedAt ?? tx.finishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final elapsedMs = _ms(tx.elapsed) ?? 0;
  final requestBody = entry.bodies[NetworkBodyPart.request];
  final responseBody = entry.bodies[NetworkBodyPart.response];
  final timings = tx.timings;

  return {
    'startedDateTime': started.toUtc().toIso8601String(),
    'time': elapsedMs,
    'request': {
      'method': request.method,
      'url': request.url,
      'httpVersion': request.protocol ?? '',
      'cookies': const <Object>[],
      'headers': _headersToJson(request.headers),
      'queryString': [
        for (final MapEntry(:key, :value)
            in request.uri?.queryParametersAll.entries ??
                const <MapEntry<String, List<String>>>[])
          for (final item in value) {'name': key, 'value': item},
      ],
      'headersSize': -1,
      'bodySize': request.size ?? requestBody?.bytes.length ?? -1,
      if (requestBody != null)
        'postData': {
          'mimeType': request.contentType ?? '',
          ..._bodyText(requestBody, encodingKey: '_encoding'),
        },
    },
    'response': {
      'status': response?.code ?? 0,
      'statusText': response?.message ?? '',
      'httpVersion': request.protocol ?? '',
      'cookies': const <Object>[],
      'headers': _headersToJson(response?.headers ?? const []),
      'content': {
        'size': response?.size ?? responseBody?.bytes.length ?? 0,
        'mimeType': response?.contentType ?? '',
        if (responseBody != null)
          ..._bodyText(responseBody, encodingKey: 'encoding'),
      },
      'redirectURL': _header(response?.headers, 'location') ?? '',
      'headersSize': -1,
      'bodySize': response?.size ?? responseBody?.bytes.length ?? -1,
    },
    'cache': const <String, Object>{},
    'timings': {
      'blocked': -1,
      'dns': _ms(timings?.dns) ?? -1,
      'connect': _ms(timings?.connect) ?? -1,
      'ssl': _ms(timings?.tls) ?? -1,
      // HAR requires these three; with no breakdown, the whole exchange is
      // counted as waiting.
      'send': _ms(timings?.send) ?? 0,
      'wait': _ms(timings?.wait) ?? (timings == null ? elapsedMs : 0),
      'receive': _ms(timings?.receive) ?? 0,
    },
    '_error': ?tx.error,
    '_adapter': ?tx.adapter,
    if (tx.state == NetworkTransactionState.pending) '_pending': true,
  };
}

/// A body as HAR text: UTF-8 as is, anything else base64 under
/// [encodingKey] (`encoding` for responses, which HAR defines; `_encoding`
/// for requests, which it does not).
Map<String, Object?> _bodyText(
  NetworkBody body, {
  required String encodingKey,
}) {
  final text = body.text;
  if (text != null) return {'text': text};
  return {'text': base64.encode(body.bytes), encodingKey: 'base64'};
}

List<Map<String, String>> _headersToJson(List<NetworkHeader> headers) => [
  for (final header in headers) {'name': header.name, 'value': header.value},
];

String? _header(List<NetworkHeader>? headers, String name) {
  for (final header in headers ?? const <NetworkHeader>[]) {
    if (header.name.toLowerCase() == name) return header.value;
  }
  return null;
}

/// Milliseconds as HAR writes them: a number, fractional below 1 ms.
num? _ms(Duration? duration) {
  if (duration == null) return null;
  final micros = duration.inMicroseconds;
  return micros % 1000 == 0 ? micros ~/ 1000 : micros / 1000;
}

// ── Decoding ────────────────────────────────────────────────────────────

HarEntry? _entryFromJson(String id, Map<String, Object?> json) {
  final request = _map(json['request']);
  final url = request?['url'];
  if (request == null || url is! String || url.isEmpty) return null;

  final response = _map(json['response']);
  final content = _map(response?['content']);
  final postData = _map(request['postData']);
  final status = response?['status'];
  final error = json['_error'] is String ? json['_error'] as String : null;
  final pending = json['_pending'] == true;

  final bodies = <NetworkBodyPart, NetworkBody>{};
  final requestBody = _decodeBody(
    postData?['text'],
    base64Encoded: postData?['_encoding'] == 'base64',
  );
  if (requestBody != null) bodies[NetworkBodyPart.request] = requestBody;
  final responseBody = _decodeBody(
    content?['text'],
    base64Encoded: content?['encoding'] == 'base64',
  );
  if (responseBody != null) bodies[NetworkBodyPart.response] = responseBody;

  final requestHeaders = _headersFromJson(request['headers']);
  final requestSize = _nonNegative(request['bodySize']);
  final responseInfo = status is num && status > 0
      ? NetworkResponseInfo(
          code: status.toInt(),
          message: _nonEmpty(response?['statusText']),
          headers: _headersFromJson(response?['headers']),
          contentType: _nonEmpty(content?['mimeType']),
          size: _nonNegative(content?['size']),
          body: _bodyState(responseBody, _nonNegative(content?['size'])),
        )
      : null;

  final startedAt = json['startedDateTime'] is String
      ? DateTime.tryParse(json['startedDateTime'] as String)
      : null;
  final duration = _duration(json['time']);
  final timings = _map(json['timings']);

  return HarEntry(
    NetworkTransaction(
      id: id,
      state: error != null || (responseInfo == null && !pending)
          ? NetworkTransactionState.failed
          : responseInfo == null
          ? NetworkTransactionState.pending
          : NetworkTransactionState.complete,
      request: NetworkRequestInfo(
        method: _nonEmpty(request['method']) ?? 'GET',
        url: url,
        protocol: _nonEmpty(request['httpVersion']),
        headers: requestHeaders,
        contentType:
            _nonEmpty(postData?['mimeType']) ??
            _header(requestHeaders, 'content-type'),
        size: requestSize ?? requestBody?.bytes.length,
        body: _bodyState(requestBody, requestSize),
      ),
      response: responseInfo,
      startedAt: startedAt,
      finishedAt: startedAt != null && duration != null
          ? startedAt.add(duration)
          : null,
      duration: duration,
      error:
          error ??
          (responseInfo == null && !pending
              ? 'The request got no response.'
              : null),
      timings: timings == null
          ? null
          : NetworkTimings(
              dns: _duration(timings['dns']),
              connect: _duration(timings['connect']),
              tls: _duration(timings['ssl']),
              send: _duration(timings['send']),
              wait: _duration(timings['wait']),
              receive: _duration(timings['receive']),
            ),
      adapter: json['_adapter'] is String ? json['_adapter'] as String : null,
    ),
    bodies: bodies,
  );
}

NetworkBody? _decodeBody(Object? text, {required bool base64Encoded}) {
  if (text is! String) return null;
  final Uint8List bytes;
  if (base64Encoded) {
    try {
      bytes = base64.decode(text);
    } on FormatException {
      return null;
    }
  } else {
    bytes = utf8.encode(text);
  }
  return NetworkBody(bytes: bytes);
}

NetworkBodyState _bodyState(NetworkBody? body, int? size) {
  if (body != null) {
    return body.bytes.isEmpty
        ? NetworkBodyState.empty
        : NetworkBodyState.available;
  }
  return size == 0 ? NetworkBodyState.empty : NetworkBodyState.notCaptured;
}

List<NetworkHeader> _headersFromJson(Object? json) {
  if (json is! List) return const [];
  return [
    for (final header in json)
      if (header case {'name': final String name, 'value': final Object? value})
        NetworkHeader(name, '${value ?? ''}'),
  ];
}

Map<String, Object?>? _map(Object? value) =>
    value is Map<String, Object?> ? value : null;

String? _nonEmpty(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _nonNegative(Object? value) =>
    value is num && value >= 0 ? value.toInt() : null;

/// HAR times are milliseconds, possibly fractional; -1 means "not known".
Duration? _duration(Object? value) => value is num && value >= 0
    ? Duration(microseconds: (value * 1000).round())
    : null;
