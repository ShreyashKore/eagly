import 'dart:convert';
import 'dart:io';

import 'package:eagly/features/mcp/mcp_http_server.dart';
import 'package:eagly/features/mcp/mcp_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// The browser-facing checks: what a web page in the user's browser could
/// send is refused before any tool runs (docs/MCP_SERVER.md §3).
void main() {
  late McpHttpServer server;
  late HttpClient client;

  McpProtocol protocol() => McpProtocol(
    serverName: 'eagly',
    serverTitle: 'Eagly',
    serverVersion: '1.0.0',
    instructions: '',
    tools: const [],
  );

  Future<void> startServer({String? token}) async {
    server = McpHttpServer(protocol: protocol(), port: 0, token: token);
    await server.start();
  }

  setUp(() => client = HttpClient());

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  const ping = '{"jsonrpc":"2.0","id":1,"method":"ping"}';

  Future<HttpClientResponse> request({
    String method = 'POST',
    String path = McpHttpServer.path,
    Map<String, String> headers = const {},
    String? contentType = 'application/json',
    String body = ping,
    String? host,
  }) async {
    final port = server.boundPort;
    final req = await client.open(method, '127.0.0.1', port, path);
    if (host != null) {
      req.headers
        ..host = host
        ..port = port;
    }
    if (contentType != null) {
      req.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    headers.forEach(req.headers.set);
    if (method == 'POST') req.write(body);
    return req.close();
  }

  test('answers a plain POST from an agent', () async {
    await startServer();

    final response = await request();

    expect(response.statusCode, 200);
    final json = jsonDecode(await utf8.decodeStream(response)) as Map;
    expect(json['result'], isEmpty);
    expect(response.headers.value('access-control-allow-origin'), isNull);
  });

  test('refuses a foreign Origin, but allows its own', () async {
    await startServer();

    final foreign = await request(headers: {'Origin': 'https://evil.example'});
    expect(foreign.statusCode, 403);

    final own = await request(
      headers: {'Origin': 'http://127.0.0.1:${server.boundPort}'},
    );
    expect(own.statusCode, 200);
  });

  test('refuses a Host header that is not loopback (DNS rebinding)', () async {
    await startServer();

    final response = await request(host: 'evil.example');

    expect(response.statusCode, 403);
  });

  test('accepts localhost as the Host', () async {
    await startServer();

    final response = await request(host: 'localhost');

    expect(response.statusCode, 200);
  });

  test('refuses GET, DELETE and a CORS preflight', () async {
    await startServer();

    for (final method in ['GET', 'DELETE', 'OPTIONS']) {
      final response = await request(method: method, contentType: null);
      expect(response.statusCode, 405, reason: method);
      expect(response.headers.value(HttpHeaders.allowHeader), 'POST');
      expect(response.headers.value('access-control-allow-origin'), isNull);
      await response.drain<void>();
    }
  });

  test('refuses a body a browser could send without a preflight', () async {
    await startServer();

    final response = await request(contentType: 'text/plain');

    expect(response.statusCode, 415);
  });

  test('refuses other paths', () async {
    await startServer();

    final response = await request(path: '/');

    expect(response.statusCode, 404);
  });

  test('requires the bearer token when one is set', () async {
    await startServer(token: 'secret-token');

    final missing = await request();
    expect(missing.statusCode, 401);
    expect(missing.headers.value(HttpHeaders.wwwAuthenticateHeader), 'Bearer');

    final wrong = await request(headers: {'Authorization': 'Bearer nope'});
    expect(wrong.statusCode, 401);

    final right = await request(
      headers: {'Authorization': 'Bearer secret-token'},
    );
    expect(right.statusCode, 200);
  });

  test('a taken port fails to start with a SocketException', () async {
    await startServer();
    final second = McpHttpServer(protocol: protocol(), port: server.boundPort);

    await expectLater(second.start(), throwsA(isA<SocketException>()));
  });
}
