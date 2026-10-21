import 'dart:typed_data';

import 'package:eagly/features/network/data/network_transaction.dart';
import 'package:eagly/features/network/data/network_transaction_store.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkTransaction tx(
  String id, {
  NetworkTransactionState state = NetworkTransactionState.complete,
}) => NetworkTransaction(
  id: id,
  state: state,
  request: NetworkRequestInfo(method: 'GET', url: 'https://example.com/$id'),
);

NetworkBody bodyOf(int length) => NetworkBody(bytes: Uint8List(length));

void main() {
  group('NetworkTransactionStore', () {
    test('keeps entries oldest first, and an update keeps its place', () {
      final store = NetworkTransactionStore()
        ..upsert('s1', tx('1', state: NetworkTransactionState.pending))
        ..upsert('s1', tx('2'))
        ..upsert('s1', tx('1'));

      expect([for (final e in store.entries) e.key.id], ['1', '2']);
      expect(
        store[(source: 's1', id: '1')]!.state,
        NetworkTransactionState.complete,
      );
    });

    test('keeps the same id from two sources apart', () {
      final store = NetworkTransactionStore()
        ..upsert('s1', tx('1'))
        ..upsert('s2', tx('1'));
      expect(store.length, 2);
    });

    test('drops the oldest past its capacity and says which', () {
      final store = NetworkTransactionStore(capacity: 2);
      store
        ..upsert('s1', tx('1'))
        ..upsert('s1', tx('2'));
      final evicted = store.upsert('s1', tx('3'));

      expect(evicted, [(source: 's1', id: '1')]);
      expect([for (final e in store.entries) e.key.id], ['2', '3']);
    });

    test('removes one source without touching the others', () {
      final store = NetworkTransactionStore()
        ..upsert('s1', tx('1'))
        ..upsert('s2', tx('2'))
        ..upsert('s1', tx('3'));

      expect(store.removeSource('s1'), hasLength(2));
      expect([for (final e in store.entries) e.key], [(source: 's2', id: '2')]);
    });

    test('rebuilds its entry list only after a change', () {
      final store = NetworkTransactionStore()..upsert('s1', tx('1'));
      final first = store.entries;
      expect(identical(store.entries, first), isTrue);
      store.upsert('s1', tx('2'));
      expect(identical(store.entries, first), isFalse);
    });
  });

  group('NetworkBodyCache', () {
    const a = (source: 's1', id: '1');
    const b = (source: 's1', id: '2');
    const c = (source: 's1', id: '3');

    test('evicts the least recently used body over its budget', () {
      final cache = NetworkBodyCache(maxBytes: 10)
        ..put(a, NetworkBodyPart.response, bodyOf(4))
        ..put(b, NetworkBodyPart.response, bodyOf(4));
      // Touch `a`, so `b` is now the least recently used.
      cache.get(a, NetworkBodyPart.response);
      cache.put(c, NetworkBodyPart.response, bodyOf(4));

      expect(cache.get(a, NetworkBodyPart.response), isNotNull);
      expect(cache.get(b, NetworkBodyPart.response), isNull);
      expect(cache.get(c, NetworkBodyPart.response), isNotNull);
      expect(cache.bytes, 8);
    });

    test('does not keep a body larger than the whole budget', () {
      final cache = NetworkBodyCache(maxBytes: 10)
        ..put(a, NetworkBodyPart.response, bodyOf(11));
      expect(cache.get(a, NetworkBodyPart.response), isNull);
      expect(cache.bytes, 0);
    });

    test('drops every part of the transactions it is told to forget', () {
      final cache = NetworkBodyCache()
        ..put(a, NetworkBodyPart.request, bodyOf(1))
        ..put(a, NetworkBodyPart.response, bodyOf(2))
        ..put(b, NetworkBodyPart.response, bodyOf(3))
        ..removeAll([a]);

      expect(cache.get(a, NetworkBodyPart.request), isNull);
      expect(cache.get(a, NetworkBodyPart.response), isNull);
      expect(cache.get(b, NetworkBodyPart.response), isNotNull);
      expect(cache.bytes, 3);
    });
  });
}
