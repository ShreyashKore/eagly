import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/network_transaction.dart';
import '../network_source.dart';
import 'inspektor_frame_codec.dart';
import 'inspektor_messages.dart';

/// A request the Inspektor server answered with an error.
class InspektorRequestException(final String code, final String message)
    implements Exception {
  @override
  String toString() => 'InspektorRequestException($code): $message';
}

/// The client side of one connection to an app's Inspektor server
/// (docs/NETWORK_INSPECTOR.md §4).
///
/// The server speaks first with `hello`. The source checks the protocol
/// version, subscribes — asking for everything after [afterId] first, so a
/// reconnect picks up where it left off — and from then on turns
/// `transaction.*` events into [NetworkSourceEvent]s. There is no
/// authentication step (§4.3).
///
/// [input] and [output] are the two halves of the connection: a [Socket] in
/// the app, in-memory pipes in tests. The source owns them, and [dispose]
/// closes [output].
class InspektorSource(
  Stream<List<int>> input,
  final StreamSink<List<int>> _output, {
  final String? afterId,

  /// Picks where to resume once the app's `hello` names its store, for a
  /// caller that keeps a position per store (a restarted app is the same
  /// store behind a new socket). A non-null answer wins over [afterId].
  final String? Function(InspektorHello hello)? resumeAfter,

  /// Bodies up to this many bytes arrive inline with their transaction.
  /// Zero keeps every body on the device until it is asked for.
  final int inlineBodyLimit = 0,
}) implements NetworkSource {
  this {
    // `bind`, not `input.transform`: a Socket is a `Stream<Uint8List>`, and
    // `transform` checks the decoder against that runtime type.
    _subscription = const InspektorFrameDecoder()
        .bind(input)
        .listen(_handleFrame, onError: _handleError, onDone: _handleDone);
    _events.add(
      const NetworkSourceStatusChanged(NetworkSourceStatus.connecting),
    );
  }

  /// Connects to an Inspektor server reachable at [host]:[port] — on the
  /// host side of an `adb forward` or usbmux tunnel.
  static Future<InspektorSource> connect(
    Object host,
    int port, {
    String? afterId,
    String? Function(InspektorHello hello)? resumeAfter,
    int inlineBodyLimit = 0,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return InspektorSource(
      socket,
      socket,
      afterId: afterId,
      resumeAfter: resumeAfter,
      inlineBodyLimit: inlineBodyLimit,
    );
  }

  /// How long a request may wait for its reply before failing.
  @visibleForTesting
  static Duration requestTimeout = const Duration(seconds: 30);

  late final StreamSubscription<Map<String, Object?>> _subscription;
  final StreamController<NetworkSourceEvent> _events =
      StreamController<NetworkSourceEvent>();
  final Map<int, Completer<Object?>> _pending = {};
  final Completer<InspektorHello> _ready = Completer<InspektorHello>();
  int _nextRequestId = 1;
  String? _lastId;
  bool _closed = false;

  /// The server's `hello`, once it has arrived.
  InspektorHello? hello;

  /// Completes with the server's `hello` once the source has subscribed, or
  /// with an error if the connection fails first.
  Future<InspektorHello> get ready => _ready.future;

  /// The highest transaction id seen, to resume from after a reconnect. Only
  /// meaningful together with [InspektorHello.storeId].
  String? get lastId => _lastId;

  @override
  NetworkSourceKind get kind => NetworkSourceKind.inspektor;

  @override
  String get label => hello?.displayName ?? 'Inspektor';

  @override
  Stream<NetworkSourceEvent> get events => _events.stream;

  @override
  Future<NetworkBody> body(String transactionId, NetworkBodyPart part) async {
    final result = await _request('body.get', {
      'id': transactionId,
      'part': part.wireName,
    });
    if (result is! Map<String, Object?>) {
      throw InspektorProtocolException('"body.get" returned no body.');
    }
    return parseInspektorBody(result);
  }

  /// Deletes every transaction from the app's own store — not just from this
  /// view. The server answers with a `transactions.cleared` event.
  Future<void> clearOnDevice() => _request('transactions.clear');

  @override
  Future<void> dispose() async {
    _finish(null);
    await _subscription.cancel();
  }

  // ── Incoming frames ───────────────────────────────────────────────────

  void _handleFrame(Map<String, Object?> frame) {
    if (_closed) return;
    try {
      if (hello == null) {
        _handleHello(InspektorHello.parse(frame));
      } else if (frame.containsKey('id') && !frame.containsKey('method')) {
        _handleReply(frame);
      } else if (frame['type'] == 'event') {
        _handleEvent(frame);
      } else if (frame['type'] == 'error') {
        final message = frame['message'];
        _finish(message is String ? message : 'The app closed the session.');
      }
      // Anything else is a message from a newer protocol revision: ignored.
    } on InspektorProtocolException catch (error) {
      _finish(error.message);
    }
  }

  void _handleHello(InspektorHello received) {
    if (received.protocol != inspektorProtocolVersion) {
      _finish(
        received.protocol > inspektorProtocolVersion
            ? 'This app\'s Inspektor speaks protocol ${received.protocol}; '
                  'update Eagly to inspect it.'
            : 'This app\'s Inspektor speaks protocol ${received.protocol}; '
                  'update Inspektor in the app.',
      );
      return;
    }
    hello = received;
    _events.add(
      NetworkSourceStatusChanged(
        NetworkSourceStatus.live,
        message: received.displayName,
      ),
    );
    unawaited(_subscribe(received));
  }

  Future<void> _subscribe(InspektorHello received) async {
    try {
      final after = resumeAfter?.call(received) ?? afterId;
      await _request('subscribe', {
        'afterId': ?after,
        'inlineBodyLimit': inlineBodyLimit,
      });
      if (!_ready.isCompleted) _ready.complete(received);
    } on Object catch (error) {
      _finish('The app refused the subscription: $error');
    }
  }

  void _handleReply(Map<String, Object?> frame) {
    final id = frame['id'];
    final completer = id is int ? _pending.remove(id) : null;
    if (completer == null) return;
    final error = frame['error'];
    if (error is Map<String, Object?>) {
      completer.completeError(
        InspektorRequestException(
          '${error['code'] ?? 'error'}',
          '${error['message'] ?? 'The app could not complete the request.'}',
        ),
      );
    } else {
      completer.complete(frame['result']);
    }
  }

  void _handleEvent(Map<String, Object?> frame) {
    final data = frame['data'];
    switch (frame['event']) {
      case 'transaction.started' || 'transaction.updated':
        if (data is! Map<String, Object?>) {
          throw InspektorProtocolException('A transaction event had no data.');
        }
        final transaction = parseInspektorTransaction(data);
        _rememberId(transaction.id);
        _events.add(NetworkTransactionUpserted(transaction));
      case 'transactions.cleared':
        _events.add(const NetworkTransactionsCleared());
      default:
        // `overrides.changed` (phase 3) and events from newer revisions.
        break;
    }
  }

  void _rememberId(String id) {
    final last = _lastId;
    if (last == null) {
      _lastId = id;
      return;
    }
    final number = int.tryParse(id);
    final lastNumber = int.tryParse(last);
    if (number == null || lastNumber == null || number > lastNumber) {
      _lastId = id;
    }
  }

  void _handleError(Object error) {
    _finish(
      error is InspektorProtocolException
          ? error.message
          : 'The connection to the app failed: $error',
    );
  }

  void _handleDone() => _finish(null);

  // ── Outgoing requests ─────────────────────────────────────────────────

  Future<Object?> _request(String method, [Map<String, Object?>? params]) {
    if (_closed) {
      return Future.error(StateError('The connection to the app is closed.'));
    }
    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _output.add(
      encodeInspektorFrame({'id': id, 'method': method, 'params': ?params}),
    );
    return completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('The app did not answer "$method".');
      },
    );
  }

  // ── Shutdown ──────────────────────────────────────────────────────────

  /// Ends the session. [failure] explains an error; null is a clean close.
  void _finish(String? failure) {
    if (_closed) return;
    _closed = true;
    final pendingError = StateError(
      failure ?? 'The connection to the app closed.',
    );
    for (final completer in _pending.values) {
      completer.completeError(pendingError);
    }
    _pending.clear();
    if (!_ready.isCompleted) {
      _ready.completeError(pendingError);
      // Nobody may be waiting on [ready]; the status event carries the error.
      unawaited(_ready.future.then<void>((_) {}, onError: (_) {}));
    }
    _events.add(
      NetworkSourceStatusChanged(
        failure == null
            ? NetworkSourceStatus.ended
            : NetworkSourceStatus.failed,
        message: failure,
      ),
    );
    unawaited(_events.close());
    unawaited(_closeOutput());
  }

  Future<void> _closeOutput() async {
    try {
      await _output.close();
    } catch (_) {
      // Already closed by the peer.
    }
  }
}
