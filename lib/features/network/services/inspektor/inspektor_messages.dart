import 'dart:convert';
import 'dart:typed_data';

import '../../data/network_transaction.dart';
import 'inspektor_frame_codec.dart';

/// The protocol version this build of Eagly speaks.
const int inspektorProtocolVersion = 2;

/// The `hello` an Inspektor server sends first on every connection
/// (docs/NETWORK_INSPECTOR.md §4.5). It carries only public identity.
class const InspektorHello({
  required final int protocol,

  /// Whether the client's first request must be `auth` with the token the
  /// app wrote to the device log (§4.3). False when the transport has already
  /// checked who connected, as Android's does.
  final bool requiresToken = false,
  required final String sdkName,
  final String? sdkVersion,

  /// `kotlin` or `dart`.
  final String? runtime,
  final List<String> adapters = const [],

  /// Whether this server lets a client list and edit overrides.
  final bool supportsOverrides = false,
  required final String appId,
  final String? appName,
  final String? appVersion,
  final int? pid,
  final String? process,

  /// Identifies the app's transaction store. It changes when the store is
  /// recreated, which invalidates a remembered `afterId`.
  required final String storeId,

  /// Whether the store outlives the process (a database) or is in memory.
  final bool storePersistent = false,
  final String? oldestId,
}) {
  /// Parses a `hello` frame. Throws [InspektorProtocolException] when it is
  /// not one, or lacks a field the protocol requires.
  factory InspektorHello.parse(Map<String, Object?> json) {
    if (json['type'] != 'hello') {
      throw InspektorProtocolException(
        'Expected the server to start with "hello", got ${_describe(json)}.',
      );
    }
    final protocol = json['protocol'];
    if (protocol is! int) {
      throw InspektorProtocolException('"hello" has no protocol version.');
    }
    final auth = json['auth'] ?? 'none';
    if (auth != 'none' && auth != 'token') {
      throw InspektorProtocolException(
        'This app asks for "$auth" authentication, which this Eagly does not '
        'know; update Eagly to inspect it.',
      );
    }
    final sdk = _map(json, 'sdk') ?? const {};
    final app = _map(json, 'app') ?? const {};
    final store = _map(json, 'store') ?? const {};
    return InspektorHello(
      protocol: protocol,
      requiresToken: auth == 'token',
      sdkName: _string(sdk, 'name') ?? 'inspektor',
      sdkVersion: _string(sdk, 'version'),
      runtime: _string(sdk, 'runtime'),
      adapters: [
        for (final adapter in _list(sdk, 'adapters') ?? const [])
          if (adapter is String) adapter,
      ],
      supportsOverrides: sdk['overrides'] == true,
      appId: _requireString(app, 'id', 'hello.app'),
      appName: _string(app, 'name'),
      appVersion: _string(app, 'version'),
      pid: _int(app, 'pid'),
      process: _string(app, 'process'),
      storeId: _requireString(store, 'id', 'hello.store'),
      storePersistent: store['persistent'] == true,
      oldestId: _string(store, 'oldestId'),
    );
  }

  /// The app's display name, falling back to its id.
  String get displayName =>
      (appName == null || appName!.isEmpty) ? appId : appName!;
}

/// Parses a transaction object (§4.7). Unknown fields are ignored; a missing
/// `id`, `method` or `url` throws [InspektorProtocolException].
NetworkTransaction parseInspektorTransaction(Map<String, Object?> json) {
  final id = _requireString(json, 'id', 'transaction');
  final request = _map(json, 'request') ?? const {};
  final responseJson = _map(json, 'response');
  final error = _string(json, 'error');
  final response = responseJson == null || _int(responseJson, 'code') == null
      ? null
      : NetworkResponseInfo(
          code: _int(responseJson, 'code')!,
          message: _string(responseJson, 'message'),
          headers: _headers(responseJson['headers']),
          contentType: _string(responseJson, 'contentType'),
          size: _int(responseJson, 'size'),
          body: NetworkBodyState.fromWire(_string(responseJson, 'body')),
          tlsVersion: _string(responseJson, 'tlsVersion'),
          cipherSuite: _string(responseJson, 'cipherSuite'),
        );

  return NetworkTransaction(
    id: id,
    state: error != null
        ? NetworkTransactionState.failed
        : response != null
        ? NetworkTransactionState.complete
        : NetworkTransactionState.pending,
    request: NetworkRequestInfo(
      method: _requireString(json, 'method', 'transaction $id'),
      url: _requireString(json, 'url', 'transaction $id'),
      protocol: _string(json, 'protocol'),
      headers: _headers(request['headers']),
      contentType: _string(request, 'contentType'),
      size: _int(request, 'size'),
      body: NetworkBodyState.fromWire(_string(request, 'body')),
    ),
    response: response,
    startedAt: _date(json, 'requestDate'),
    finishedAt: _date(json, 'responseDate'),
    duration: _millis(json, 'tookMs'),
    error: error,
    timings: _timings(_map(json, 'timings')),
    override: _override(_map(json, 'override')),
    adapter: _string(json, 'adapter'),
  );
}

/// Parses a `body.get` result: `{encoding, data, size, truncated}`.
NetworkBody parseInspektorBody(Map<String, Object?> json) {
  final data = _string(json, 'data') ?? '';
  final Uint8List bytes;
  switch (_string(json, 'encoding')) {
    case 'base64':
      try {
        bytes = base64.decode(data);
      } on FormatException {
        throw InspektorProtocolException('A body was not valid base64.');
      }
    case 'utf8' || null:
      bytes = utf8.encode(data);
    case final other:
      throw InspektorProtocolException('Unknown body encoding "$other".');
  }
  return NetworkBody(
    bytes: bytes,
    truncated: json['truncated'] == true,
    originalSize: _int(json, 'size'),
  );
}

NetworkTimings? _timings(Map<String, Object?>? json) {
  if (json == null) return null;
  return NetworkTimings(
    dns: _millis(json, 'dnsMs'),
    connect: _millis(json, 'connectMs'),
    tls: _millis(json, 'tlsMs'),
    send: _millis(json, 'sendMs'),
    wait: _millis(json, 'waitMs'),
    receive: _millis(json, 'receiveMs'),
  );
}

NetworkOverrideInfo? _override(Map<String, Object?>? json) {
  if (json == null) return null;
  final original = _map(json, 'original') ?? const {};
  final request = _map(original, 'request');
  final response = _map(original, 'response');
  return NetworkOverrideInfo(
    id: _string(json, 'id') ?? '',
    originalRequestHeaders: request == null || request['headers'] == null
        ? null
        : _headers(request['headers']),
    originalRequestBody: request?['body'] == null
        ? null
        : NetworkBodyState.fromWire(_string(request!, 'body')),
    originalResponseCode: response == null ? null : _int(response, 'code'),
    originalResponseHeaders: response == null || response['headers'] == null
        ? null
        : _headers(response['headers']),
    originalResponseBody: response?['body'] == null
        ? null
        : NetworkBodyState.fromWire(_string(response!, 'body')),
  );
}

/// Headers travel as `[[name, value], …]`; anything else is skipped.
List<NetworkHeader> _headers(Object? json) {
  if (json is! List) return const [];
  return [
    for (final pair in json)
      if (pair is List && pair.length == 2 && pair[0] is String)
        NetworkHeader(pair[0] as String, '${pair[1] ?? ''}'),
  ];
}

Map<String, Object?>? _map(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is Map<String, Object?> ? value : null;
}

List<Object?>? _list(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is List ? value : null;
}

String? _string(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String ? value : null;
}

int? _int(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is num ? value.toInt() : null;
}

Duration? _millis(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is num ? Duration(microseconds: (value * 1000).round()) : null;
}

DateTime? _date(Map<String, Object?> json, String key) {
  final value = _string(json, key);
  return value == null ? null : DateTime.tryParse(value);
}

String _requireString(Map<String, Object?> json, String key, String where) {
  final value = _string(json, key);
  if (value == null || value.isEmpty) {
    throw InspektorProtocolException('$where has no "$key".');
  }
  return value;
}

String _describe(Map<String, Object?> json) {
  final type = json['type'] ?? json['method'];
  return type == null ? 'a message without a type' : '"$type"';
}
