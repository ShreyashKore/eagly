import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mcp_protocol.dart';

/// Serves [McpProtocol] at `POST http://127.0.0.1:<port>/mcp`, and refuses
/// anything a web page could send.
///
/// Any page open in the user's browser can try to reach a localhost port,
/// so the checks below stop it (docs/MCP_SERVER.md §3):
/// - **Loopback only.** Nothing off the machine can connect.
/// - **Host header** must name loopback and this port, which defeats DNS
///   rebinding (a page on `evil.example` re-pointed at 127.0.0.1).
/// - **Origin header**, which browsers send on every cross-origin POST, must
///   be absent (agents send none) or loopback on this port.
/// - **Content-Type** must be JSON. A browser can only send that cross-origin
///   after a CORS preflight, and this server answers no `OPTIONS` and sends
///   no `Access-Control-*` header.
/// - **Bearer token**, when [token] is set, for machines shared between
///   accounts: another user's processes can reach loopback too.
class McpHttpServer({
  required final McpProtocol protocol,
  required final int port,

  /// When non-null, every request must carry `Authorization: Bearer <token>`.
  final String? token,
}) {
  static const path = '/mcp';

  /// The largest request body accepted. Tool arguments are small.
  static const maxBodyBytes = 1024 * 1024;

  HttpServer? _server;

  /// The port actually bound: [port], or the one the OS picked for port 0.
  int get boundPort => _server?.port ?? port;

  bool get isRunning => _server != null;

  /// Binds the port. Throws a [SocketException] when it is taken.
  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server.autoCompress = false;
    _server = server;
    server.listen(
      (request) => unawaited(_handle(request)),
      onError: (Object _) {},
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final refusal = _refusal(request);
      if (refusal != null) {
        await _send(response, refusal);
        return;
      }

      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
        if (bytes.length > maxBodyBytes) {
          await _send(response, const _Refusal(413, 'Request body too large.'));
          return;
        }
      }
      final String body;
      try {
        body = utf8.decode(bytes);
      } on FormatException {
        await _send(response, const _Refusal(400, 'The body is not UTF-8.'));
        return;
      }

      final result = await protocol.handle(request.headers.value, body);
      response.statusCode = result.statusCode;
      if (result.body case final json?) {
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(json));
      }
      await response.close();
    } catch (_) {
      // The client went away, or the response was already closed.
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// Why [request] must be turned away before its body is read, or null.
  _Refusal? _refusal(HttpRequest request) {
    if (!_isAllowedHost(request.headers.value(HttpHeaders.hostHeader))) {
      return const _Refusal(403, 'Forbidden: unexpected Host header.');
    }
    final origin = request.headers.value('origin');
    if (origin != null && !_isAllowedOrigin(origin)) {
      return const _Refusal(
        403,
        'Forbidden: cross-origin requests are refused.',
      );
    }
    if (request.uri.path != path) {
      return const _Refusal(404, 'Not found. The MCP endpoint is $path.');
    }
    if (request.method != 'POST') {
      // GET (a legacy client's event stream), DELETE (ending a legacy
      // session) and OPTIONS (a CORS preflight) are all refused.
      return const _Refusal(
        405,
        'Method not allowed: POST only.',
        allowPost: true,
      );
    }
    if (token case final expected?) {
      final given = request.headers.value(HttpHeaders.authorizationHeader);
      if (given == null || !_constantTimeEquals(given, 'Bearer $expected')) {
        return const _Refusal(
          401,
          'Unauthorized: a valid bearer token is required.',
        );
      }
    }
    final contentType = request.headers.contentType;
    if (contentType == null || contentType.mimeType != 'application/json') {
      return const _Refusal(415, 'Content-Type must be application/json.');
    }
    return null;
  }

  bool _isAllowedHost(String? host) {
    if (host == null) return false;
    final lower = host.toLowerCase();
    return lower == '127.0.0.1:$boundPort' ||
        lower == 'localhost:$boundPort' ||
        lower == '[::1]:$boundPort';
  }

  bool _isAllowedOrigin(String origin) {
    final lower = origin.toLowerCase();
    return lower == 'http://127.0.0.1:$boundPort' ||
        lower == 'http://localhost:$boundPort';
  }

  /// Compares [given] with [expected] in time that depends only on
  /// [given]'s length, so a timing attack can't guess the token byte by byte.
  static bool _constantTimeEquals(String given, String expected) {
    final x = utf8.encode(given);
    final y = utf8.encode(expected);
    var diff = x.length ^ y.length;
    for (var i = 0; i < x.length; i++) {
      diff |= x[i] ^ y[i % y.length];
    }
    return diff == 0;
  }

  static Future<void> _send(HttpResponse response, _Refusal refusal) async {
    response.statusCode = refusal.statusCode;
    if (refusal.allowPost) {
      response.headers.set(HttpHeaders.allowHeader, 'POST');
    }
    if (refusal.statusCode == 401) {
      response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Bearer');
    }
    response.headers.contentType = ContentType.json;
    response.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': null,
        'error': {
          'code': McpErrorCodes.invalidRequest,
          'message': refusal.message,
        },
      }),
    );
    await response.close();
  }
}

class const _Refusal(
  final int statusCode,
  final String message, {
  final bool allowPost = false,
});
