import 'dart:async';
import 'dart:io';

import 'package:eagly/features/network/services/inspektor/inspektor_endpoint.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_frame_codec.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_messages.dart';

import 'inspektor_test_support.dart';

/// An Inspektor server on a real loopback socket, for tests that go through
/// [InspektorSource.connect]: the app side of a tunnel.
///
/// Every connection gets a `hello` for [appId]/[storeId]. With a [token], the
/// hello asks for it, and a client whose first request isn't `auth` with it
/// gets `unauthorized` and a closed connection, as an iOS app does. A
/// `subscribe` is
/// recorded in [subscribes] and answered with every transaction in
/// [transactions] whose id is above its `afterId`; `body.get` answers
/// `body of <id>`.
class LoopbackInspektorServer._(
  final ServerSocket _server, {
  required final String appId,
  required final String storeId,
  final String? token,
}) {
  static Future<LoopbackInspektorServer> start({
    String appId = 'com.example.app',
    String storeId = 'store-1',
    String? token,
    List<String> transactionIds = const [],
  }) async {
    final server = LoopbackInspektorServer._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      appId: appId,
      storeId: storeId,
      token: token,
    );
    server.transactions.addAll(transactionIds);
    server._server.listen(server._serve);
    return server;
  }

  /// Ids of the transactions the app has stored, oldest first.
  final List<String> transactions = [];

  /// The params of every `subscribe`, in order.
  final List<Map<String, Object?>> subscribes = [];

  final List<Socket> _clients = [];

  int get port => _server.port;

  /// A tunnel to this server, counting how often it is closed.
  InspektorTunnel tunnel({void Function()? onClose}) => InspektorTunnel(
    host: InternetAddress.loopbackIPv4,
    port: port,
    close: () async => onClose?.call(),
  );

  /// Records a new transaction and pushes it to every subscribed client.
  void record(String id) {
    transactions.add(id);
    for (final client in List.of(_clients)) {
      client.add(
        encodeInspektorFrame({
          'type': 'event',
          'event': 'transaction.started',
          'data': inspektorTransactionJson(id: id),
        }),
      );
    }
  }

  /// Drops every client, as an app that died would.
  Future<void> dropClients() async {
    // destroy() can run the socket's onDone, which edits the list.
    final clients = List.of(_clients);
    _clients.clear();
    for (final client in clients) {
      client.destroy();
    }
  }

  Future<void> close() async {
    await dropClients();
    await _server.close();
  }

  void _serve(Socket socket) {
    socket.add(
      encodeInspektorFrame({
        'type': 'hello',
        'protocol': inspektorProtocolVersion,
        'auth': token == null ? 'none' : 'token',
        'sdk': {'name': 'inspektor', 'runtime': 'kotlin', 'overrides': true},
        'app': {'id': appId, 'name': 'Example', 'pid': 4242},
        'store': {'id': storeId, 'persistent': true},
      }),
    );
    var authenticated = token == null;
    final Stream<List<int>> incoming = socket;
    const InspektorFrameDecoder()
        .bind(incoming)
        .listen(
          (frame) {
            final id = frame['id'];
            final params =
                (frame['params'] as Map<String, Object?>?) ?? const {};
            if (!authenticated) {
              if (frame['method'] == 'auth' && params['token'] == token) {
                authenticated = true;
                socket.add(encodeInspektorFrame({'id': id, 'result': {}}));
              } else {
                socket.add(
                  encodeInspektorFrame({
                    'id': id,
                    'error': {'code': 'unauthorized', 'message': 'No token.'},
                  }),
                );
                socket.destroy();
              }
              return;
            }
            switch (frame['method']) {
              case 'subscribe':
                subscribes.add(params);
                _clients.add(socket);
                socket.add(encodeInspektorFrame({'id': id, 'result': {}}));
                final after = int.tryParse('${params['afterId'] ?? ''}') ?? 0;
                for (final tx in transactions) {
                  if ((int.tryParse(tx) ?? 0) <= after) continue;
                  socket.add(
                    encodeInspektorFrame({
                      'type': 'event',
                      'event': 'transaction.updated',
                      'data': inspektorTransactionJson(id: tx),
                    }),
                  );
                }
              case 'body.get':
                socket.add(
                  encodeInspektorFrame({
                    'id': id,
                    'result': {
                      'encoding': 'utf8',
                      'data': 'body of ${params['id']}',
                    },
                  }),
                );
            }
          },
          onError: (_) => socket.destroy(),
          onDone: () {
            _clients.remove(socket);
            socket.destroy();
          },
        );
  }
}
