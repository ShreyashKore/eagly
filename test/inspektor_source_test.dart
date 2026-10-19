import 'dart:async';
import 'dart:io';

import 'package:eagly/features/network/data/network_transaction.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_frame_codec.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_source.dart';
import 'package:eagly/features/network/services/network_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/inspektor_test_support.dart';

void main() {
  late FakeInspektorServer server;
  late InspektorSource source;
  late List<NetworkSourceEvent> events;
  late Completer<void> eventsDone;

  void connect({String? afterId, int inlineBodyLimit = 0}) {
    server = FakeInspektorServer();
    source = server.connect(afterId: afterId, inlineBodyLimit: inlineBodyLimit);
    events = [];
    eventsDone = Completer<void>();
    source.events.listen(events.add, onDone: eventsDone.complete);
  }

  List<NetworkTransaction> upserts() => [
    for (final event in events)
      if (event case NetworkTransactionUpserted(:final transaction))
        transaction,
  ];

  List<NetworkSourceStatus> statuses() => [
    for (final event in events)
      if (event case NetworkSourceStatusChanged(:final status)) status,
  ];

  tearDown(() async {
    await source.dispose();
  });

  test('subscribes after hello, resuming after the last id it saw', () async {
    connect(afterId: '41', inlineBodyLimit: 4096);
    server.hello();

    final params = await server.acceptSubscribe();
    final hello = await source.ready;

    expect(params, {'afterId': '41', 'inlineBodyLimit': 4096});
    expect(hello.displayName, 'Example');
    expect(source.label, 'Example');
    expect(statuses(), [
      NetworkSourceStatus.connecting,
      NetworkSourceStatus.live,
    ]);
  });

  test('leaves afterId out on a first connection', () async {
    connect();
    server.hello();
    expect(await server.acceptSubscribe(), {'inlineBodyLimit': 0});
  });

  test(
    'turns transaction events into upserts and tracks the last id',
    () async {
      connect();
      server.hello();
      await server.acceptSubscribe();

      server
        ..event(
          'transaction.started',
          inspektorTransactionJson(id: '9', code: null),
        )
        ..event('transaction.updated', inspektorTransactionJson(id: '9'))
        ..event('transaction.updated', inspektorTransactionJson(id: '10'))
        ..event('transactions.cleared')
        ..event('overrides.changed', {'overrides': <Object>[]})
        ..event('something.from.a.newer.server');
      await pumpEventQueue();

      expect(
        [for (final tx in upserts()) (tx.id, tx.state)],
        [
          ('9', NetworkTransactionState.pending),
          ('9', NetworkTransactionState.complete),
          ('10', NetworkTransactionState.complete),
        ],
      );
      expect(events.whereType<NetworkTransactionsCleared>(), hasLength(1));
      expect(source.lastId, '10');
    },
  );

  test('fetches a body on demand', () async {
    connect();
    server.hello();
    await server.acceptSubscribe();

    final body = source.body('9', NetworkBodyPart.response);
    final request = await server.nextRequest();
    expect(request['method'], 'body.get');
    expect(request['params'], {'id': '9', 'part': 'response'});
    server.reply(request['id']! as int, {
      'encoding': 'utf8',
      'data': '{"ok":true}',
      'size': 11,
      'truncated': false,
    });

    expect((await body).text, '{"ok":true}');
  });

  test('passes an error reply to the caller', () async {
    connect();
    server.hello();
    await server.acceptSubscribe();

    final body = source.body('404', NetworkBodyPart.request);
    final request = await server.nextRequest();
    server.replyError(
      request['id']! as int,
      'not_found',
      'No such transaction',
    );

    await expectLater(
      body,
      throwsA(
        isA<InspektorRequestException>().having(
          (e) => e.code,
          'code',
          'not_found',
        ),
      ),
    );
  });

  test('asks the app to clear its store', () async {
    connect();
    server.hello();
    await server.acceptSubscribe();

    final cleared = source.clearOnDevice();
    final request = await server.nextRequest();
    expect(request['method'], 'transactions.clear');
    server.reply(request['id']! as int, const <String, Object?>{});
    await cleared;
  });

  test('ends cleanly when the app closes the connection', () async {
    connect();
    server.hello();
    await server.acceptSubscribe();
    final pending = expectLater(
      source.body('1', NetworkBodyPart.request),
      throwsStateError,
    );
    await server.nextRequest();

    await server.close();
    await eventsDone.future;

    expect(statuses().last, NetworkSourceStatus.ended);
    await pending;
    expect(server.clientClosed, isTrue);
  });

  group('fails', () {
    Future<String?> failureMessage() async {
      await eventsDone.future;
      final last = events.last as NetworkSourceStatusChanged;
      expect(last.status, NetworkSourceStatus.failed);
      return last.message;
    }

    test('on a newer protocol, asking for a newer Eagly', () async {
      connect();
      server.hello(protocol: 2);
      expect(await failureMessage(), contains('update Eagly'));
      await expectLater(source.ready, throwsStateError);
    });

    test('on an older protocol, asking for a newer Inspektor', () async {
      connect();
      server.hello(protocol: 0);
      expect(await failureMessage(), contains('update Inspektor'));
    });

    test('when the first message is not hello', () async {
      connect();
      server.event('transaction.updated', inspektorTransactionJson());
      expect(await failureMessage(), contains('hello'));
    });

    test('on a frame over the cap, and closes its side', () async {
      connect();
      server.hello();
      await server.acceptSubscribe();
      server.sendBytes([0x7F, 0xFF, 0xFF, 0xFF]);

      expect(await failureMessage(), contains('limit'));
      await pumpEventQueue();
      expect(server.clientClosed, isTrue);
    });

    test('on a transaction without an id', () async {
      connect();
      server.hello();
      await server.acceptSubscribe();
      server.event(
        'transaction.updated',
        inspektorTransactionJson()..remove('id'),
      );
      expect(await failureMessage(), contains('"id"'));
    });
  });

  test('connects over a real socket', () async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(listener.close);
    final serverSide = Completer<Socket>();
    listener.listen(serverSide.complete);

    final client = await InspektorSource.connect(
      InternetAddress.loopbackIPv4,
      listener.port,
    );
    // Assigned so tearDown disposes it.
    source = client;
    final socket = await serverSide.future;
    final requests = const InspektorFrameDecoder().bind(socket);
    socket.add(
      encodeInspektorFrame({
        'type': 'hello',
        'protocol': 1,
        'app': {'id': 'com.example.app'},
        'store': {'id': 's'},
      }),
    );

    final subscribe = await requests.first;
    expect(subscribe['method'], 'subscribe');
    socket.add(encodeInspektorFrame({'id': subscribe['id'], 'result': {}}));

    expect((await client.ready).appId, 'com.example.app');
    socket.destroy();
  });
}
