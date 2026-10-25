import 'dart:async';
import 'dart:math' as math;

import '../../../session/device_session_controller.dart';
import '../../network/data/network_filter.dart';
import '../../network/data/network_transaction.dart';
import '../../network/data/network_transaction_store.dart';
import '../../network/network_controller.dart';
import '../mcp_tool.dart';
import 'mcp_tool_context.dart';

const _querySyntax =
    'Eagly Network-pane query syntax, terms ANDed: bare text matches the URL; '
    '/regex/ on the URL; domain:*.example.com, path:, method:POST, '
    'status:4xx or status:404, type: (content type), is:error, is:failed, '
    'is:pending, is:overridden, larger-than:10k, slower-than:500ms, '
    'has-request-header:, has-response-header:, scheme:; a leading - '
    'excludes. Example: "domain:api.example.com is:error -path:/health".';

const _statusValues = ['2xx', '3xx', '4xx', '5xx', 'failed', 'pending'];

const _setupHint =
    'Network capture needs the app to ship Inspektor with remote inspection '
    'turned on (a debug build); see https://github.com/ShreyashKore/inspektor. '
    'Eagly is now watching this device for such apps: launch or reopen the app '
    'and call again in a few seconds.';

/// `list_network_requests`, `get_network_request` and
/// `wait_for_network_request`.
List<McpTool> networkTools(McpToolContext context) => [
  McpTool(
    name: 'list_network_requests',
    title: 'List network requests',
    description:
        'Lists the HTTP requests Eagly captured from apps on the device that '
        'ship Inspektor, newest first: method, URL, status, timing and sizes, '
        'without headers or bodies (use get_network_request with an id). '
        '$untrustedDataNote',
    inputSchema: objectSchema({
      'device': deviceProperty,
      'query': stringProperty(_querySyntax),
      'status': stringListProperty(
        'Only these status classes.',
        enumValues: _statusValues,
      ),
      'limit': integerProperty(
        'Most requests to return.',
        minimum: 1,
        maximum: 500,
        defaultValue: 50,
      ),
      'offset': integerProperty(
        'Skip this many of the newest matches, to page back.',
        minimum: 0,
        defaultValue: 0,
      ),
    }),
    handler: (args) async {
      final session = context.resolve(args.string('device'));
      final network = _network(context, session);
      final filter = _filter(args);
      final limit = args.integer('limit', min: 1, max: 500) ?? 50;
      final offset = args.integer('offset', min: 0) ?? 0;

      final matching = _matching(network, filter).reversed.toList();
      final page = matching.skip(offset).take(limit).toList();
      return McpToolResult.json({
        'device': session.id,
        'requests': [for (final entry in page) _summaryJson(network, entry)],
        'totalMatching': matching.length,
        'returned': page.length,
        'hasMore': offset + page.length < matching.length,
        ..._sourcesJson(network),
        if (network.entries.length >= network.capacity)
          'note':
              'Eagly keeps the newest ${network.capacity} '
              'requests; older ones are gone.',
      });
    },
  ),
  McpTool(
    name: 'get_network_request',
    title: 'Get a network request',
    description:
        'Returns one captured HTTP request in full: request and response '
        'headers, timings, error, Inspektor override details, and the bodies '
        'as text (binary bodies are described, not included). Credentials in '
        'headers are redacted unless the user turned that off in Eagly. '
        '$untrustedDataNote',
    inputSchema: objectSchema(
      {
        'device': deviceProperty,
        'id': stringProperty('The request id from list_network_requests.'),
        'bodies': stringProperty(
          'Which bodies to fetch.',
          enumValues: ['none', 'request', 'response', 'both'],
        ),
        'maxBodyBytes': integerProperty(
          'Longest body to return; longer ones are cut.',
          minimum: 256,
          maximum: 1024 * 1024,
          defaultValue: 64 * 1024,
        ),
      },
      required: ['id'],
    ),
    handler: (args) async {
      final session = context.resolve(args.string('device'));
      final network = _network(context, session);
      final id = args.requiredString('id');
      final bodies = args.string('bodies') ?? 'response';
      if (!const ['none', 'request', 'response', 'both'].contains(bodies)) {
        throw McpToolError('"bodies" must be none, request, response or both.');
      }
      final maxBodyBytes =
          args.integer('maxBodyBytes', min: 256, max: 1024 * 1024) ?? 64 * 1024;

      final entry = network.entries
          .where((e) => _idOf(e.key) == id)
          .firstOrNull;
      if (entry == null) {
        throw McpToolError(
          'No request "$id" on ${session.device.displayName}. It may have '
          'been cleared or evicted; call list_network_requests for current '
          'ids.',
        );
      }
      final t = entry.transaction;
      final redact = context.redactHeaders();

      Future<Map<String, Object?>?> body(
        NetworkBodyPart part,
        NetworkBodyState state,
        String? contentType,
      ) async {
        if (!state.isFetchable) return {'state': state.wireName};
        try {
          final fetched = await network.loadBody(entry.key, part);
          return _bodyJson(fetched, state, contentType, maxBodyBytes);
        } catch (error) {
          return {'state': state.wireName, 'error': '$error'};
        }
      }

      final response = t.response;
      return McpToolResult.json({
        'device': session.id,
        ..._summaryJson(network, entry),
        'request': {
          'protocol': ?t.request.protocol,
          'headers': _headersJson(t.request.headers, redact),
          'contentType': ?t.request.contentType,
          'size': ?t.request.size,
          if (bodies == 'request' || bodies == 'both')
            'body': await body(
              NetworkBodyPart.request,
              t.request.body,
              t.request.contentType,
            ),
        },
        if (response != null)
          'response': {
            'code': response.code,
            'message': ?response.message,
            'headers': _headersJson(response.headers, redact),
            'contentType': ?response.contentType,
            'size': ?response.size,
            'tlsVersion': ?response.tlsVersion,
            if (bodies == 'response' || bodies == 'both')
              'body': await body(
                NetworkBodyPart.response,
                response.body,
                response.contentType,
              ),
          },
        if (t.timings case final timings?) 'timingsMs': _timingsJson(timings),
        if (t.override case final override?)
          'override': {
            'id': override.id,
            'originalResponseCode': ?override.originalResponseCode,
            if (override.originalRequestHeaders case final headers?)
              'originalRequestHeaders': _headersJson(headers, redact),
            if (override.originalResponseHeaders case final headers?)
              'originalResponseHeaders': _headersJson(headers, redact),
          },
        if (redact) 'redacted': 'Credential headers are redacted.',
      });
    },
  ),
  McpTool(
    name: 'wait_for_network_request',
    title: 'Wait for a network request',
    description:
        'Waits for the next HTTP request matching the query to finish (or to '
        'start, with waitForResponse false) and returns its summary. Only '
        'requests that were not already finished when the call began count. '
        '$untrustedDataNote',
    inputSchema: objectSchema({
      'device': deviceProperty,
      'query': stringProperty(_querySyntax),
      'status': stringListProperty(
        'Only these status classes.',
        enumValues: _statusValues,
      ),
      'waitForResponse': booleanProperty(
        'Wait until the request has finished.',
        defaultValue: true,
      ),
      'timeoutSeconds': integerProperty(
        'How long to wait.',
        minimum: 1,
        maximum: 120,
        defaultValue: 30,
      ),
    }),
    handler: (args) async {
      final session = context.resolve(args.string('device'));
      final network = _network(context, session);
      final filter = _filter(args);
      final waitForResponse = args.boolean('waitForResponse') ?? true;
      final timeout = Duration(
        seconds: args.integer('timeoutSeconds', min: 1, max: 120) ?? 30,
      );

      bool done(NetworkEntry entry) =>
          !waitForResponse ||
          entry.transaction.state != NetworkTransactionState.pending;
      final seen = {
        for (final entry in network.entries)
          if (done(entry)) entry.key,
      };
      NetworkEntry? next() {
        for (final entry in _matching(network, filter).reversed) {
          if (!seen.contains(entry.key) && done(entry)) return entry;
        }
        return null;
      }

      final completer = Completer<NetworkEntry?>();
      void check() {
        if (completer.isCompleted) return;
        if (next() case final entry?) completer.complete(entry);
      }

      network.addListener(check);
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });
      final hit = await completer.future;
      timer.cancel();
      network.removeListener(check);

      if (hit == null) {
        return McpToolResult.json({
          'device': session.id,
          'matched': false,
          'timedOut': true,
          ..._sourcesJson(network),
        });
      }
      return McpToolResult.json({
        'device': session.id,
        'matched': true,
        'request': _summaryJson(network, hit),
      });
    },
  ),
];

NetworkController _network(
  McpToolContext context,
  DeviceSessionController session,
) {
  if (!session.canInspectNetwork) {
    throw McpToolError(
      '${McpToolContext.describeDevice(session)} has no network capture.',
    );
  }
  context.holdNetworkWatching(session);
  return session.networkController;
}

NetworkFilter _filter(McpArguments args) {
  final statuses = args.strings('status') ?? const [];
  final classes = <NetworkStatusClass>{};
  for (final status in statuses) {
    final match = NetworkStatusClass.values
        .where((c) => c.label.toLowerCase() == status.toLowerCase())
        .firstOrNull;
    if (match == null) {
      throw McpToolError(
        'Unknown status "$status"; use ${_statusValues.join(', ')}.',
      );
    }
    classes.add(match);
  }
  final filter = NetworkFilter(
    query: args.string('query') ?? '',
    statusClasses: classes,
  );
  if (filter.error case final error?) {
    throw McpToolError('The query has a broken regular expression: $error');
  }
  return filter;
}

/// Every entry [filter] lets through, oldest first.
List<NetworkEntry> _matching(NetworkController network, NetworkFilter filter) =>
    [
      for (final entry in network.entries)
        if (filter.matches(
          entry.transaction,
          sourceLabel: network.sourceOf(entry.key)?.label,
        ))
          entry,
    ];

/// The id agents use for a request. Opaque to them; looked up by equality.
String _idOf(NetworkTransactionKey key) => '${key.source}#${key.id}';

Map<String, Object?> _summaryJson(
  NetworkController network,
  NetworkEntry entry,
) {
  final t = entry.transaction;
  return {
    'id': _idOf(entry.key),
    'method': t.request.method,
    'url': t.request.url,
    'state': t.state.name,
    'status': ?t.response?.code,
    'statusClass': NetworkStatusClass.of(t).label,
    'startedAt': ?t.startedAt?.toIso8601String(),
    'durationMs': ?t.elapsed?.inMilliseconds,
    'requestSize': ?t.request.size,
    'responseSize': ?t.response?.size,
    'contentType': ?(t.response?.contentType ?? t.request.contentType),
    'error': ?t.error,
    if (t.override != null) 'overridden': true,
    'adapter': ?t.adapter,
    'app': ?network.sourceOf(entry.key)?.label,
  };
}

Map<String, Object?> _sourcesJson(NetworkController network) {
  final sources = network.sources;
  return {
    'apps': [
      for (final source in sources)
        {
          'label': source.label,
          'kind': source.kind.label,
          'status': source.status.name,
          'message': ?source.message,
        },
    ],
    if (sources.isEmpty) 'hint': _setupHint,
  };
}

final _sensitiveHeader = RegExp(
  r'^(authorization|proxy-authorization|cookie|set-cookie)$|token|secret|api[-_]?key|password|session',
  caseSensitive: false,
);

List<String> _headersJson(List<NetworkHeader> headers, bool redact) => [
  for (final header in headers)
    redact && _sensitiveHeader.hasMatch(header.name)
        ? '${header.name}: <redacted, ${header.value.length} chars>'
        : '${header.name}: ${header.value}',
];

Map<String, Object?> _bodyJson(
  NetworkBody body,
  NetworkBodyState state,
  String? contentType,
  int maxBytes,
) {
  final size = body.bytes.length;
  final text = body.text;
  if (text == null) {
    return {
      'state': state.wireName,
      'binary': true,
      'size': size,
      'contentType': ?contentType,
    };
  }
  final cut = size > maxBytes;
  // Cut on a character boundary near maxBytes.
  final shown = cut ? text.substring(0, math.min(text.length, maxBytes)) : text;
  return {
    'state': state.wireName,
    'text': shown,
    'size': size,
    if (cut) 'truncated': 'Cut to about $maxBytes of $size bytes.',
    if (body.truncated)
      'capturedTruncated':
          'The app cut this body when capturing it'
          '${body.originalSize == null ? '' : ' (${body.originalSize} bytes in full)'}.',
  };
}

Map<String, Object?> _timingsJson(NetworkTimings timings) => {
  'dns': ?timings.dns?.inMilliseconds,
  'connect': ?timings.connect?.inMilliseconds,
  'tls': ?timings.tls?.inMilliseconds,
  'send': ?timings.send?.inMilliseconds,
  'wait': ?timings.wait?.inMilliseconds,
  'receive': ?timings.receive?.inMilliseconds,
};
