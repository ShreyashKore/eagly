import 'dart:async';

import 'package:eagly/features/network/services/inspektor/inspektor_frame_codec.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_messages.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_source.dart';

/// The app side of an Inspektor connection, in memory: it sends frames to an
/// [InspektorSource] and reads back what the source asks for. Tests script
/// both directions by hand.
class FakeInspektorServer() {
  this {
    const InspektorFrameDecoder()
        .bind(_fromClient.stream)
        .listen(_received.add, onDone: () => clientClosed = true);
  }

  final StreamController<List<int>> _toClient = StreamController<List<int>>();
  final StreamController<List<int>> _fromClient = StreamController<List<int>>();
  final StreamController<Map<String, Object?>> _received =
      StreamController<Map<String, Object?>>();
  late final StreamIterator<Map<String, Object?>> _requests = StreamIterator(
    _received.stream,
  );

  /// Whether the source closed its half of the connection.
  bool clientClosed = false;

  /// The client's ends of the connection, for building a source by hand.
  (Stream<List<int>>, StreamSink<List<int>>) get connectRaw =>
      (_toClient.stream, _fromClient.sink);

  /// A source connected to this server.
  InspektorSource connect({
    String? afterId,
    int inlineBodyLimit = 0,
    Future<String> Function(InspektorHello hello)? token,
  }) => InspektorSource(
    _toClient.stream,
    _fromClient.sink,
    afterId: afterId,
    inlineBodyLimit: inlineBodyLimit,
    token: token,
  );

  void send(Map<String, Object?> message) =>
      _toClient.add(encodeInspektorFrame(message));

  /// Raw bytes, for frames the encoder would refuse to produce.
  void sendBytes(List<int> bytes) => _toClient.add(bytes);

  void hello({
    int protocol = inspektorProtocolVersion,
    String storeId = 'store-1',
    String auth = 'none',
  }) => send({
    'type': 'hello',
    'protocol': protocol,
    'auth': auth,
    'sdk': {
      'name': 'inspektor',
      'version': '0.9.0',
      'runtime': 'kotlin',
      'adapters': ['okhttp', 'ktor'],
      'overrides': true,
    },
    'app': {
      'id': 'com.example.app',
      'name': 'Example',
      'version': '1.4.0 (51)',
      'pid': 12345,
      'process': 'com.example.app',
    },
    'store': {'id': storeId, 'persistent': true, 'oldestId': '1'},
  });

  void reply(int id, Object? result) => send({'id': id, 'result': result});

  void replyError(int id, String code, String message) => send({
    'id': id,
    'error': {'code': code, 'message': message},
  });

  void event(String name, [Map<String, Object?>? data]) =>
      send({'type': 'event', 'event': name, 'data': ?data});

  /// The next request the source sent.
  Future<Map<String, Object?>> nextRequest() async {
    if (!await _requests.moveNext()) {
      throw StateError('The source closed without another request.');
    }
    return _requests.current;
  }

  /// Answers the `subscribe` that follows `hello`, returning its params.
  Future<Map<String, Object?>> acceptSubscribe() async {
    final request = await nextRequest();
    if (request['method'] != 'subscribe') {
      throw StateError('Expected subscribe, got $request');
    }
    reply(request['id']! as int, const <String, Object?>{});
    return (request['params'] as Map<String, Object?>?) ?? const {};
  }

  /// Ends the app's side of the connection.
  Future<void> close() => _toClient.close();
}

/// A transaction object as Inspektor sends it (docs/NETWORK_INSPECTOR.md
/// §4.7), with the fields a test cares about overridden.
Map<String, Object?> inspektorTransactionJson({
  String id = '1842',
  String method = 'POST',
  String url = 'https://api.example.com/v1/login',
  int? code = 200,
  String? error,
}) => {
  'id': id,
  'adapter': 'okhttp',
  'method': method,
  'url': url,
  'protocol': 'h2',
  'requestDate': '2026-10-18T09:12:03.412Z',
  if (code != null) 'responseDate': '2026-10-18T09:12:03.643Z',
  if (code != null) 'tookMs': 231,
  'request': {
    'headers': [
      ['content-type', 'application/json'],
      ['authorization', '***'],
    ],
    'contentType': 'application/json',
    'size': 64,
    'body': 'available',
  },
  if (code != null)
    'response': {
      'code': code,
      'message': 'OK',
      'headers': [
        ['content-type', 'application/json'],
        ['set-cookie', 'a=1'],
        ['set-cookie', 'b=2'],
      ],
      'contentType': 'application/json',
      'size': 1543,
      'body': 'available',
      'tlsVersion': 'TLSv1.3',
      'cipherSuite': 'TLS_AES_128_GCM_SHA256',
    },
  'error': error,
  'timings': {
    'dnsMs': 4,
    'connectMs': 38,
    'tlsMs': 51,
    'sendMs': 1,
    'waitMs': 120,
    'receiveMs': 17,
  },
};
