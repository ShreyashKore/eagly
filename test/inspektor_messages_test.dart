import 'dart:convert';

import 'package:eagly/features/network/data/network_transaction.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_frame_codec.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_messages.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/inspektor_test_support.dart';

void main() {
  group('hello', () {
    test('carries the app, the SDK and the store', () {
      final hello = InspektorHello.parse({
        'type': 'hello',
        'protocol': 1,
        'sdk': {
          'name': 'inspektor',
          'version': '0.9.0',
          'runtime': 'dart',
          'adapters': ['dart:io', 'dio'],
          'overrides': true,
        },
        'app': {'id': 'com.example.app', 'name': 'Example', 'pid': 7},
        'store': {'id': 'abc', 'persistent': false, 'oldestId': '3'},
        'somethingNewer': {'ignored': true},
      });

      expect(hello.protocol, 1);
      expect(hello.runtime, 'dart');
      expect(hello.adapters, ['dart:io', 'dio']);
      expect(hello.supportsOverrides, isTrue);
      expect(hello.displayName, 'Example');
      expect(hello.pid, 7);
      expect(hello.storeId, 'abc');
      expect(hello.storePersistent, isFalse);
      expect(hello.oldestId, '3');
    });

    test('falls back to the app id for a name', () {
      final hello = InspektorHello.parse({
        'type': 'hello',
        'protocol': 1,
        'app': {'id': 'com.example.app'},
        'store': {'id': 's'},
      });
      expect(hello.displayName, 'com.example.app');
    });

    test('rejects a first message that is not hello', () {
      expect(
        () => InspektorHello.parse({'type': 'event', 'event': 'x'}),
        throwsA(isA<InspektorProtocolException>()),
      );
    });

    test('rejects a hello without the fields the protocol requires', () {
      expect(
        () => InspektorHello.parse({'type': 'hello', 'protocol': 1}),
        throwsA(isA<InspektorProtocolException>()),
      );
    });
  });

  group('transactions', () {
    test('map the protocol object onto the model', () {
      final tx = parseInspektorTransaction(inspektorTransactionJson());

      expect(tx.id, '1842');
      expect(tx.state, NetworkTransactionState.complete);
      expect(tx.adapter, 'okhttp');
      expect(tx.request.method, 'POST');
      expect(tx.request.url, 'https://api.example.com/v1/login');
      expect(tx.request.protocol, 'h2');
      expect(tx.request.body, NetworkBodyState.available);
      expect(
        tx.request.headers.first,
        const NetworkHeader('content-type', 'application/json'),
      );
      expect(tx.response!.code, 200);
      expect(tx.response!.tlsVersion, 'TLSv1.3');
      expect(tx.duration, const Duration(milliseconds: 231));
      expect(tx.startedAt, DateTime.utc(2026, 10, 18, 9, 12, 3, 412));
      expect(tx.timings!.wait, const Duration(milliseconds: 120));
    });

    test('keep duplicate headers, in order', () {
      final tx = parseInspektorTransaction(inspektorTransactionJson());
      expect(
        [for (final h in tx.response!.headers) h.toString()],
        [
          'content-type: application/json',
          'set-cookie: a=1',
          'set-cookie: b=2',
        ],
      );
    });

    test('are pending until the response arrives', () {
      final tx = parseInspektorTransaction(
        inspektorTransactionJson(code: null),
      );
      expect(tx.state, NetworkTransactionState.pending);
      expect(tx.response, isNull);
    });

    test('are failed when they carry an error', () {
      final tx = parseInspektorTransaction(
        inspektorTransactionJson(code: null, error: 'timeout'),
      );
      expect(tx.state, NetworkTransactionState.failed);
      expect(tx.error, 'timeout');
    });

    test('read the override and the values it replaced', () {
      final tx = parseInspektorTransaction({
        ...inspektorTransactionJson(),
        'override': {
          'id': 'ov-3',
          'original': {
            'response': {
              'code': 500,
              'headers': [
                ['x', 'y'],
              ],
              'body': 'available',
            },
          },
        },
      });
      final override = tx.override!;
      expect(override.id, 'ov-3');
      expect(override.originalResponseCode, 500);
      expect(override.originalResponseHeaders, [const NetworkHeader('x', 'y')]);
      expect(override.originalResponseBody, NetworkBodyState.available);
      expect(override.originalRequestHeaders, isNull);
    });

    test('treat an unknown body state as not captured', () {
      final json = inspektorTransactionJson();
      (json['request']! as Map<String, Object?>)['body'] = 'streamed';
      expect(
        parseInspektorTransaction(json).request.body,
        NetworkBodyState.notCaptured,
      );
    });

    test('require an id, a method and a URL', () {
      for (final field in ['id', 'method', 'url']) {
        final json = inspektorTransactionJson()..remove(field);
        expect(
          () => parseInspektorTransaction(json),
          throwsA(isA<InspektorProtocolException>()),
          reason: 'without "$field"',
        );
      }
    });
  });

  group('bodies', () {
    test('decode UTF-8 and base64', () {
      final text = parseInspektorBody({'encoding': 'utf8', 'data': '{"a":1}'});
      expect(text.text, '{"a":1}');

      final binary = parseInspektorBody({
        'encoding': 'base64',
        'data': base64.encode([0, 255, 1]),
        'size': 9000,
        'truncated': true,
      });
      expect(binary.bytes, [0, 255, 1]);
      expect(binary.text, isNull);
      expect(binary.truncated, isTrue);
      expect(binary.originalSize, 9000);
    });

    test('reject an encoding this build does not know', () {
      expect(
        () => parseInspektorBody({'encoding': 'gzip', 'data': ''}),
        throwsA(isA<InspektorProtocolException>()),
      );
    });
  });
}
