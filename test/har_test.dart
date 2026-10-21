import 'dart:convert';
import 'dart:typed_data';

import 'package:eagly/features/network/data/har.dart';
import 'package:eagly/features/network/data/network_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

final _complete = NetworkTransaction(
  id: '7',
  state: NetworkTransactionState.complete,
  adapter: 'okhttp',
  request: const NetworkRequestInfo(
    method: 'POST',
    url: 'https://api.example.com/v1/items?page=2&tag=a&tag=b',
    protocol: 'h2',
    headers: [NetworkHeader('content-type', 'application/json')],
    contentType: 'application/json',
    size: 9,
    body: NetworkBodyState.available,
  ),
  response: const NetworkResponseInfo(
    code: 201,
    message: 'Created',
    headers: [
      NetworkHeader('set-cookie', 'a=1'),
      NetworkHeader('set-cookie', 'b=2'),
    ],
    contentType: 'image/png',
    size: 3,
    body: NetworkBodyState.available,
  ),
  startedAt: DateTime.utc(2026, 10, 18, 9, 12, 3, 412),
  duration: const Duration(microseconds: 231500),
  timings: const NetworkTimings(
    dns: Duration(milliseconds: 4),
    wait: Duration(milliseconds: 120),
  ),
);

final _bodies = {
  NetworkBodyPart.request: NetworkBody(bytes: utf8.encode('{"name":1}')),
  NetworkBodyPart.response: NetworkBody(
    bytes: Uint8List.fromList([0x89, 0x50, 0x4E]),
  ),
};

Map<String, Object?> _onlyEntry(String har) {
  final log = (jsonDecode(har) as Map<String, Object?>)['log']! as Map;
  return ((log['entries']! as List).single as Map).cast<String, Object?>();
}

void main() {
  group('export', () {
    late Map<String, Object?> entry;
    setUp(() {
      entry = _onlyEntry(
        encodeHar(
          [HarEntry(_complete, bodies: _bodies)],
          creatorName: 'Eagly',
          creatorVersion: '1.6.0',
        ),
      );
    });

    test('writes the request line, query and headers', () {
      final request = entry['request']! as Map;
      expect(request['method'], 'POST');
      expect(request['httpVersion'], 'h2');
      expect(request['queryString'], [
        {'name': 'page', 'value': '2'},
        {'name': 'tag', 'value': 'a'},
        {'name': 'tag', 'value': 'b'},
      ]);
      expect((request['postData']! as Map)['text'], '{"name":1}');
      expect(entry['startedDateTime'], '2026-10-18T09:12:03.412Z');
      expect(entry['time'], 231.5);
      expect(entry['_adapter'], 'okhttp');
    });

    test('base64-encodes a binary response, as HAR defines', () {
      final content = (entry['response']! as Map)['content']! as Map;
      expect(content['encoding'], 'base64');
      expect(base64.decode(content['text']! as String), [0x89, 0x50, 0x4E]);
    });

    test('fills the timing fields HAR requires', () {
      final timings = entry['timings']! as Map;
      expect(timings['dns'], 4);
      expect(timings['wait'], 120);
      expect(timings['send'], 0);
      expect(timings['connect'], -1);
    });

    test('marks a failed request with status 0 and _error', () {
      final failed = _onlyEntry(
        encodeHar(
          [
            HarEntry(
              const NetworkTransaction(
                id: '1',
                state: NetworkTransactionState.failed,
                error: 'Connection refused',
                request: NetworkRequestInfo(
                  method: 'GET',
                  url: 'https://down.example.com/',
                ),
              ),
            ),
          ],
          creatorName: 'Eagly',
          creatorVersion: '1',
        ),
      );
      expect((failed['response']! as Map)['status'], 0);
      expect(failed['_error'], 'Connection refused');
    });
  });

  group('import', () {
    test('round-trips an export', () {
      final har = encodeHar(
        [HarEntry(_complete, bodies: _bodies)],
        creatorName: 'Eagly',
        creatorVersion: '1',
      );
      final decoded = decodeHar(har).single;
      final tx = decoded.transaction;

      expect(tx.id, '1');
      expect(tx.state, NetworkTransactionState.complete);
      expect(tx.request.method, 'POST');
      expect(tx.request.url, _complete.request.url);
      expect(tx.request.headers, _complete.request.headers);
      expect(tx.response!.code, 201);
      expect(tx.response!.headers, _complete.response!.headers);
      expect(tx.response!.body, NetworkBodyState.available);
      expect(tx.startedAt, _complete.startedAt);
      expect(tx.duration, _complete.duration);
      expect(tx.adapter, 'okhttp');
      expect(decoded.bodies[NetworkBodyPart.request]!.text, '{"name":1}');
      expect(decoded.bodies[NetworkBodyPart.response]!.bytes, [
        0x89,
        0x50,
        0x4E,
      ]);
    });

    test('reads a browser HAR, failures included', () {
      final har = jsonEncode({
        'log': {
          'version': '1.2',
          'creator': {'name': 'WebInspector', 'version': '537.36'},
          'entries': [
            {
              'startedDateTime': '2026-10-18T09:00:00.000Z',
              'time': 12.5,
              'request': {
                'method': 'GET',
                'url': 'https://example.com/a.js',
                'httpVersion': 'http/1.1',
                'headers': [
                  {'name': 'accept', 'value': '*/*'},
                ],
                'bodySize': 0,
              },
              'response': {
                'status': 200,
                'statusText': '',
                'headers': [],
                'content': {
                  'size': 4,
                  'mimeType': 'text/javascript',
                  'text': 'x=1;',
                },
              },
              'timings': {'send': 0.1, 'wait': 10, 'receive': 2.4, 'ssl': -1},
            },
            {
              'startedDateTime': '2026-10-18T09:00:01.000Z',
              'time': -1,
              'request': {'method': 'GET', 'url': 'https://gone.example.com/'},
              'response': {
                'status': 0,
                'content': {'size': 0},
              },
              '_error': 'net::ERR_NAME_NOT_RESOLVED',
            },
            {
              'request': {'method': 'GET'},
            },
          ],
        },
      });

      final entries = decodeHar(har);
      expect(entries, hasLength(2));

      final ok = entries[0].transaction;
      expect(ok.response!.code, 200);
      expect(ok.response!.message, isNull);
      expect(ok.request.body, NetworkBodyState.empty);
      expect(ok.duration, const Duration(microseconds: 12500));
      expect(ok.timings!.tls, isNull);
      expect(entries[0].bodies[NetworkBodyPart.response]!.text, 'x=1;');

      final failed = entries[1].transaction;
      expect(failed.state, NetworkTransactionState.failed);
      expect(failed.error, 'net::ERR_NAME_NOT_RESOLVED');
      expect(failed.duration, isNull);
    });

    test('explains a file that is not a HAR', () {
      expect(
        () => decodeHar('not json'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('not JSON'),
          ),
        ),
      );
      expect(
        () => decodeHar('{"log": {}}'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('no entries'),
          ),
        ),
      );
    });
  });
}
