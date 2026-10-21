import 'package:eagly/features/network/data/network_copy.dart';
import 'package:eagly/features/network/data/network_filter.dart';
import 'package:eagly/features/network/data/network_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkTransaction _transaction({
  String method = 'GET',
  String url = 'https://api.example.com/v1/users?page=2',
  NetworkTransactionState state = NetworkTransactionState.complete,
  int? code = 200,
  String? contentType = 'application/json; charset=utf-8',
  int? size = 2048,
  Duration? duration = const Duration(milliseconds: 120),
  List<NetworkHeader> requestHeaders = const [],
  List<NetworkHeader> responseHeaders = const [],
  DateTime? startedAt,
  NetworkOverrideInfo? override,
}) => NetworkTransaction(
  id: '1',
  state: state,
  request: NetworkRequestInfo(
    method: method,
    url: url,
    headers: requestHeaders,
  ),
  response: code == null
      ? null
      : NetworkResponseInfo(
          code: code,
          contentType: contentType,
          size: size,
          headers: responseHeaders,
        ),
  duration: duration,
  startedAt: startedAt,
  override: override,
);

bool _matches(String query, NetworkTransaction transaction, {String? source}) =>
    NetworkFilter(query: query).matches(transaction, sourceLabel: source);

void main() {
  group('query', () {
    test('bare text matches the URL, case-insensitively', () {
      final t = _transaction();
      expect(_matches('USERS', t), isTrue);
      expect(_matches('orders', t), isFalse);
      expect(_matches('', t), isTrue);
    });

    test('every term must match, and - negates one', () {
      final t = _transaction();
      expect(_matches('users page', t), isTrue);
      expect(_matches('users orders', t), isFalse);
      expect(_matches('-users', t), isFalse);
      expect(_matches('-orders', t), isTrue);
    });

    test('domain takes wildcards and the host alias', () {
      final t = _transaction();
      expect(_matches('domain:api.example.com', t), isTrue);
      expect(_matches('domain:*.example.com', t), isTrue);
      expect(_matches('host:example.com', t), isFalse);
      expect(_matches('-domain:api.example.com', t), isFalse);
    });

    test('method, status-code, path and mime-type', () {
      final t = _transaction(method: 'POST', code: 404);
      expect(_matches('method:post', t), isTrue);
      expect(_matches('method:get', t), isFalse);
      expect(_matches('status-code:404', t), isTrue);
      expect(_matches('status:4xx', t), isTrue);
      expect(_matches('status-code:5xx', t), isFalse);
      expect(_matches('path:/v1/users', t), isTrue);
      expect(_matches('path:page', t), isFalse, reason: 'query is not path');
      expect(_matches('mime-type:json', t), isTrue);
      expect(_matches('type:xml', t), isFalse);
    });

    test('larger-than and slower-than read units', () {
      final t = _transaction();
      expect(_matches('larger-than:1k', t), isTrue);
      expect(_matches('larger-than:2k', t), isFalse);
      expect(_matches('slower-than:100ms', t), isTrue);
      expect(_matches('slower-than:0.2s', t), isFalse);
      expect(parseNetworkSize('1.5m'), 1572864);
      expect(parseNetworkDuration('2s'), const Duration(seconds: 2));
    });

    test('is: covers pending, failed, error and overridden', () {
      final pending = _transaction(
        state: NetworkTransactionState.pending,
        code: null,
      );
      final failed = _transaction(
        state: NetworkTransactionState.failed,
        code: null,
      );
      final notFound = _transaction(code: 404);
      final overridden = _transaction(
        override: const NetworkOverrideInfo(id: 'o1'),
      );
      expect(_matches('is:pending', pending), isTrue);
      expect(_matches('is:pending', failed), isFalse);
      expect(_matches('is:failed', failed), isTrue);
      expect(_matches('is:error', notFound), isTrue);
      expect(_matches('is:error', overridden), isFalse);
      expect(_matches('is:overridden', overridden), isTrue);
    });

    test('headers and source', () {
      final t = _transaction(
        requestHeaders: const [NetworkHeader('Authorization', 'Bearer x')],
        responseHeaders: const [NetworkHeader('Set-Cookie', 'a=b')],
      );
      expect(_matches('has-request-header:authorization', t), isTrue);
      expect(_matches('has-response-header:set-cookie', t), isTrue);
      expect(_matches('has-response-header:authorization', t), isFalse);
      expect(_matches('source:sample', t, source: 'Sample app'), isTrue);
      expect(_matches('source:other', t, source: 'Sample app'), isFalse);
    });

    test('a /regex/ matches the URL; a broken one is reported and ignored', () {
      final t = _transaction();
      expect(_matches(r'/v\d+\/users/', t), isTrue);
      expect(_matches('/^http:/', t), isFalse);
      final broken = NetworkFilter(query: '/[/ users');
      expect(broken.error, isNotNull);
      expect(broken.matches(t), isTrue);
    });

    test('an unknown key is plain text', () {
      expect(_matches('foo:bar', _transaction()), isFalse);
      expect(
        _matches('foo:bar', _transaction(url: 'https://x.dev/foo:bar')),
        isTrue,
      );
    });

    test('quotes keep spaces in one term', () {
      expect(tokenizeNetworkQuery('a "b c" -d:"e f"'), ['a', 'b c', '-d:e f']);
      expect(
        NetworkFilter().withTerm('source:My app').query,
        'source:"My app"',
      );
    });

    test('withTerm appends once', () {
      final filter = NetworkFilter(query: 'users').withTerm('method:GET');
      expect(filter.query, 'users method:GET');
      expect(filter.withTerm('method:GET').query, 'users method:GET');
    });
  });

  test('status and type toggles match any picked bucket', () {
    final json404 = _transaction(code: 404);
    final image = _transaction(contentType: 'image/png');
    final filter = NetworkFilter(
      statusClasses: {NetworkStatusClass.clientError},
    );
    expect(filter.matches(json404), isTrue);
    expect(filter.matches(image), isFalse);
    expect(
      NetworkFilter(
        types: {NetworkResourceType.image, NetworkResourceType.json},
      ).matches(image),
      isTrue,
    );
    expect(
      NetworkResourceType.fromContentType('text/html'),
      NetworkResourceType.document,
    );
    expect(
      NetworkResourceType.fromContentType('application/problem+json'),
      NetworkResourceType.json,
    );
    expect(
      NetworkResourceType.fromContentType(null),
      NetworkResourceType.other,
    );
  });

  test('the time window keeps exchanges that overlap it', () {
    final base = DateTime(2026, 10, 20, 12);
    final t = _transaction(
      startedAt: base,
      duration: const Duration(seconds: 1),
    );
    NetworkFilter window(int fromMs, int toMs) => NetworkFilter(
      timeWindow: NetworkTimeWindow(
        base.add(Duration(milliseconds: fromMs)),
        base.add(Duration(milliseconds: toMs)),
      ),
    );
    expect(window(500, 2000).matches(t), isTrue);
    expect(window(-500, 100).matches(t), isTrue);
    expect(window(1500, 2000).matches(t), isFalse);
    expect(window(0, 10).matches(_transaction()), isFalse, reason: 'no start');
  });

  group('curlCommand', () {
    test('long options, one per line, like Inspektor\'s Curl.kt', () {
      final command = curlCommand(
        _transaction(
          requestHeaders: const [
            NetworkHeader('Accept', 'application/json'),
            NetworkHeader('Content-Length', '0'),
          ],
        ),
      );
      expect(
        command,
        "curl \\\n"
        "  --request GET \\\n"
        "  --url 'https://api.example.com/v1/users?page=2' \\\n"
        "  --header 'Accept: application/json'",
      );
    });

    test('a body is sent raw, with quotes escaped for the shell', () {
      final command = curlCommand(
        _transaction(method: 'PUT'),
        body: "{\"name\":\"O'Brien\"}",
      );
      expect(command, contains('--request PUT'));
      expect(command, contains(r"""--data-raw '{"name":"O'\''Brien"}'"""));
    });

    test('a method that is not plain letters is quoted for the shell', () {
      expect(
        curlCommand(_transaction(method: 'get|`id`')),
        contains("--request 'GET|`ID`'"),
      );
      expect(curlCommand(_transaction(method: '')), contains("--request ''"));
    });

    test('the content type is sent when no header carries it', () {
      final transaction = NetworkTransaction(
        id: '1',
        state: NetworkTransactionState.complete,
        request: const NetworkRequestInfo(
          method: 'POST',
          url: 'https://x.dev',
          contentType: 'application/json',
        ),
      );
      expect(
        curlCommand(transaction, body: '{}'),
        contains("--header 'Content-Type: application/json'"),
      );
    });
  });
}
