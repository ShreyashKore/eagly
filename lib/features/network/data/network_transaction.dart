import 'dart:convert';
import 'dart:typed_data';

/// Where a [NetworkTransaction] was captured.
enum NetworkSourceKind(final String label) {
  /// An app that ships Inspektor, over its remote-inspection socket.
  inspektor('Inspektor'),

  /// A HAR file opened from disk.
  har('HAR file'),
}

/// How far an exchange has got.
enum NetworkTransactionState { pending, complete, failed }

/// What the source captured of a request or response body. The bytes
/// themselves are never part of a [NetworkTransaction]: they are fetched on
/// demand through the source, so a list of thousands of exchanges stays small.
enum NetworkBodyState(final String wireName) {
  /// Captured in full; fetch it to show it.
  available('available'),

  /// The exchange had no body.
  empty('empty'),

  /// Captured, but cut at the capturing side's size limit.
  truncated('truncated'),

  /// Not recorded: the capture level skipped bodies, the body could only be
  /// read once (a streamed upload), or the call was filtered out.
  notCaptured('not_captured');

  bool get isFetchable => this == available || this == truncated;

  /// The state named [wireName], or [notCaptured] for a name this build does
  /// not know.
  static NetworkBodyState fromWire(String? wireName) => values.firstWhere(
    (s) => s.wireName == wireName,
    orElse: () => notCaptured,
  );
}

/// Which body of an exchange to fetch. The `original…` parts are the values an
/// Inspektor override replaced.
enum NetworkBodyPart(final String wireName) {
  request('request'),
  response('response'),
  originalRequest('originalRequest'),
  originalResponse('originalResponse'),
}

/// One header line. Headers are kept as an ordered list rather than a map:
/// duplicates (`Set-Cookie`) and order both matter.
class const NetworkHeader(final String name, final String value) {
  @override
  bool operator ==(Object other) =>
      other is NetworkHeader && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);

  @override
  String toString() => '$name: $value';
}

/// The request half of an exchange.
class const NetworkRequestInfo({
  required final String method,
  required final String url,

  /// The HTTP version the source reported (`h2`, `http/1.1`, …).
  final String? protocol,
  final List<NetworkHeader> headers = const [],
  final String? contentType,

  /// Body size in bytes, when the source measured it.
  final int? size,
  final NetworkBodyState body = NetworkBodyState.notCaptured,
}) {
  /// [url] parsed, or null when it is not a valid URI.
  Uri? get uri => Uri.tryParse(url);
}

/// The response half of an exchange.
class const NetworkResponseInfo({
  required final int code,
  final String? message,
  final List<NetworkHeader> headers = const [],
  final String? contentType,

  /// Body size in bytes, when the source measured it.
  final int? size,
  final NetworkBodyState body = NetworkBodyState.notCaptured,
  final String? tlsVersion,
  final String? cipherSuite,
});

/// The phases of an exchange, where the capturing stack exposes them (OkHttp's
/// `EventListener`, `URLSessionTaskMetrics`). Any phase can be missing.
class const NetworkTimings({
  final Duration? dns,
  final Duration? connect,
  final Duration? tls,
  final Duration? send,
  final Duration? wait,
  final Duration? receive,
});

/// The Inspektor override that rewrote an exchange, and the values it
/// replaced. A null field means that part was not overridden.
class const NetworkOverrideInfo({
  required final String id,
  final List<NetworkHeader>? originalRequestHeaders,
  final NetworkBodyState? originalRequestBody,
  final int? originalResponseCode,
  final List<NetworkHeader>? originalResponseHeaders,
  final NetworkBodyState? originalResponseBody,
});

/// One HTTP exchange shown in the Network pane, whichever source captured it.
///
/// Shaped after Inspektor's `HttpTransaction` (itself close to a HAR entry),
/// so the primary source maps onto it without loss; other sources map onto it
/// too. See docs/NETWORK_INSPECTOR.md §3.1.
class const NetworkTransaction({
  /// The capturing source's id for this exchange — unique within that source,
  /// not across sources ([NetworkTransactionKey] pairs it with the source).
  required final String id,
  required final NetworkTransactionState state,
  required final NetworkRequestInfo request,
  final NetworkResponseInfo? response,
  final DateTime? startedAt,
  final DateTime? finishedAt,

  /// Total time, when the source measured it.
  final Duration? duration,

  /// Why the exchange failed: a connection error, a timeout, a cancellation.
  final String? error,
  final NetworkTimings? timings,
  final NetworkOverrideInfo? override,

  /// The HTTP stack that made the request (`okhttp`, `urlsession`, `ktor`,
  /// `dart:io`, …), when the source says.
  final String? adapter,
}) {
  /// [duration], or the gap between [startedAt] and [finishedAt].
  Duration? get elapsed {
    if (duration != null) return duration;
    final start = startedAt;
    final end = finishedAt;
    if (start == null || end == null) return null;
    return end.difference(start);
  }
}

/// A fetched request or response body.
class const NetworkBody({
  required final Uint8List bytes,

  /// The capturing side cut the body at its size limit.
  final bool truncated = false,

  /// The full size before truncation, when known.
  final int? originalSize,
}) {
  /// [bytes] as UTF-8 text, or null for a body that is not valid UTF-8.
  String? get text {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }
}
