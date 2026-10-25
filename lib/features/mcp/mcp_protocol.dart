import 'dart:async';
import 'dart:convert';

import 'mcp_tool.dart';

/// The MCP versions this server speaks. **Modern** versions carry the version,
/// client identity and capabilities on every request (2026-07-28 on); **legacy**
/// versions open with an `initialize` handshake. A server that speaks both is
/// "dual-era": it decides per request from how the client opens.
abstract final class McpVersions {
  static const modern = ['2026-07-28'];
  static const legacy = ['2025-11-25', '2025-06-18', '2025-03-26'];
  static const all = [...modern, ...legacy];

  /// What a legacy request without an `MCP-Protocol-Version` header is taken
  /// to be: the spec allows treating it as the version before the header.
  static const headerless = '2025-03-26';
}

/// JSON-RPC and MCP error codes.
abstract final class McpErrorCodes {
  static const parseError = -32700;
  static const invalidRequest = -32600;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;
  static const headerMismatch = -32020;
  static const unsupportedProtocolVersion = -32022;
}

/// Who is calling, as the client describes itself.
class const McpClientInfo(final String name, {final String? version}) {
  static McpClientInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['title'] ?? json['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final version = json['version'];
    return McpClientInfo(
      name.trim(),
      version: version is String ? version : null,
    );
  }
}

/// What the HTTP layer sends back: a status, and a JSON body unless null.
class const McpResponse(
  final int statusCode, [
  final Map<String, Object?>? body,
]);

/// A finished tool call, for the server's activity log.
class const McpToolCall({
  required final String tool,
  required final McpClientInfo? client,
  required final Duration elapsed,
  required final bool isError,
  final String? errorMessage,
});

/// Answers MCP JSON-RPC requests over Streamable HTTP, statelessly: no
/// sessions, every request stands alone. Speaks both eras (see
/// [McpVersions]); answers with JSON, never an SSE stream. Security checks
/// (Host, Origin, token) are the HTTP layer's job, not this one's.
class McpProtocol({
  required final String serverName,
  required final String serverTitle,
  required final String serverVersion,
  required final String instructions,
  required final List<McpTool> tools,

  /// Told about every client that identifies itself.
  final void Function(McpClientInfo client)? onClient,

  /// Told about every tool call once it finishes.
  final void Function(McpToolCall call)? onToolCall,
}) {
  late final Map<String, McpTool> _toolsByName = {
    for (final tool in tools) tool.name: tool,
  };

  /// Handles one POST to the MCP endpoint. [header] reads a request header
  /// by name, case-insensitively.
  Future<McpResponse> handle(
    String? Function(String name) header,
    String body,
  ) async {
    final Object? message;
    try {
      message = jsonDecode(body);
    } on FormatException catch (error) {
      return _error(
        400,
        null,
        McpErrorCodes.parseError,
        'Parse error: ${error.message}',
      );
    }
    if (message is List) {
      return _error(
        400,
        null,
        McpErrorCodes.invalidRequest,
        'Batched requests are not supported; send one message per POST.',
      );
    }
    if (message is! Map<String, Object?> || message['jsonrpc'] != '2.0') {
      return _error(
        400,
        null,
        McpErrorCodes.invalidRequest,
        'Not a JSON-RPC 2.0 message.',
      );
    }

    final method = message['method'];
    final id = message['id'];
    if (method is! String) {
      // A response to a request we never send, or junk. Nothing to answer.
      return const McpResponse(202);
    }
    // Notifications (`notifications/initialized`, `…/cancelled`) need no
    // answer and change nothing: the server keeps no state.
    if (!message.containsKey('id')) return const McpResponse(202);
    if (id is! String && id is! num) {
      return _error(
        400,
        null,
        McpErrorCodes.invalidRequest,
        'The id must be a string or a number.',
      );
    }

    final params = message['params'];
    if (params != null && params is! Map<String, Object?>) {
      return _error(
        400,
        id,
        McpErrorCodes.invalidParams,
        'params must be an object.',
      );
    }
    final paramMap = (params as Map<String, Object?>?) ?? const {};
    final meta = paramMap['_meta'];
    final modernVersion = meta is Map
        ? meta['io.modelcontextprotocol/protocolVersion']
        : null;

    return modernVersion != null
        ? _handleModern(
            header,
            id!,
            method,
            paramMap,
            meta as Map,
            modernVersion,
          )
        : _handleLegacy(header, id!, method, paramMap);
  }

  // ── Modern (2026-07-28 on): per-request metadata ─────────────────────

  Future<McpResponse> _handleModern(
    String? Function(String name) header,
    Object id,
    String method,
    Map<String, Object?> params,
    Map meta,
    Object? version,
  ) async {
    final headerVersion = header('mcp-protocol-version');
    if (headerVersion == null) {
      return _mismatch(id, 'The MCP-Protocol-Version header is missing.');
    }
    if (headerVersion != version) {
      return _mismatch(
        id,
        'MCP-Protocol-Version header "$headerVersion" does not match the '
        'body\'s protocol version "$version".',
      );
    }
    if (!McpVersions.modern.contains(version)) {
      return McpResponse(400, {
        'jsonrpc': '2.0',
        'id': id,
        'error': {
          'code': McpErrorCodes.unsupportedProtocolVersion,
          'message': 'Unsupported protocol version',
          'data': {'supported': McpVersions.all, 'requested': version},
        },
      });
    }
    final headerMethod = header('mcp-method');
    if (headerMethod != method) {
      return _mismatch(
        id,
        headerMethod == null
            ? 'The Mcp-Method header is missing.'
            : 'Mcp-Method header "$headerMethod" does not match the body\'s '
                  'method "$method".',
      );
    }
    if (method == 'tools/call') {
      final headerName = _decodeHeaderValue(header('mcp-name'));
      final name = params['name'];
      if (headerName != name) {
        return _mismatch(
          id,
          headerName == null
              ? 'The Mcp-Name header is missing.'
              : 'Mcp-Name header "$headerName" does not match the body\'s '
                    'name "$name".',
        );
      }
    }

    final client = McpClientInfo.fromJson(
      meta['io.modelcontextprotocol/clientInfo'],
    );
    if (client != null) onClient?.call(client);

    final result = switch (method) {
      'server/discover' => _discover(),
      'tools/list' => _listTools(),
      'tools/call' => await _callTool(id, params, client),
      'ping' => <String, Object?>{},
      _ => null,
    };
    if (result == null) {
      return _error(
        404,
        id,
        McpErrorCodes.methodNotFound,
        'Method not found: $method',
      );
    }
    if (result case _RpcError(:final code, :final message)) {
      return _error(200, id, code, message);
    }
    return McpResponse(200, {
      'jsonrpc': '2.0',
      'id': id,
      'result': {'resultType': 'complete', ...result as Map<String, Object?>},
    });
  }

  Map<String, Object?> _discover() => {
    'supportedVersions': McpVersions.all,
    'capabilities': _capabilities,
    '_meta': {'io.modelcontextprotocol/serverInfo': _serverInfo},
    'instructions': instructions,
  };

  // ── Legacy (2025-11-25 and earlier): `initialize` first ──────────────

  McpClientInfo? _legacyClient;

  Future<McpResponse> _handleLegacy(
    String? Function(String name) header,
    Object id,
    String method,
    Map<String, Object?> params,
  ) async {
    if (method == 'initialize') {
      final requested = params['protocolVersion'];
      final client = McpClientInfo.fromJson(params['clientInfo']);
      if (client != null) {
        _legacyClient = client;
        onClient?.call(client);
      }
      return McpResponse(200, {
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          // Echo the client's version when we speak it; otherwise offer our
          // newest legacy one and let the client decide.
          'protocolVersion': McpVersions.legacy.contains(requested)
              ? requested
              : McpVersions.legacy.first,
          'capabilities': _capabilities,
          'serverInfo': _serverInfo,
          'instructions': instructions,
        },
      });
    }

    final version = header('mcp-protocol-version') ?? McpVersions.headerless;
    if (McpVersions.modern.contains(version)) {
      return _mismatch(
        id,
        'Protocol version $version requires '
        '_meta["io.modelcontextprotocol/protocolVersion"] in params.',
      );
    }
    if (!McpVersions.legacy.contains(version)) {
      return McpResponse(400, {
        'jsonrpc': '2.0',
        'id': id,
        'error': {
          'code': McpErrorCodes.unsupportedProtocolVersion,
          'message': 'Unsupported protocol version',
          'data': {'supported': McpVersions.all, 'requested': version},
        },
      });
    }

    final result = switch (method) {
      'tools/list' => _listTools(),
      'tools/call' => await _callTool(id, params, _legacyClient),
      'ping' => <String, Object?>{},
      _ => null,
    };
    if (result == null) {
      return _error(
        200,
        id,
        McpErrorCodes.methodNotFound,
        'Method not found: $method',
      );
    }
    if (result case _RpcError(:final code, :final message)) {
      return _error(200, id, code, message);
    }
    return McpResponse(200, {'jsonrpc': '2.0', 'id': id, 'result': result});
  }

  // ── Shared ───────────────────────────────────────────────────────────

  Map<String, Object?> get _capabilities => {
    'tools': {'listChanged': false},
  };

  Map<String, Object?> get _serverInfo => {
    'name': serverName,
    'title': serverTitle,
    'version': serverVersion,
  };

  Map<String, Object?> _listTools() => {
    'tools': [for (final tool in tools) tool.toJson()],
  };

  Future<Object> _callTool(
    Object id,
    Map<String, Object?> params,
    McpClientInfo? client,
  ) async {
    final name = params['name'];
    final tool = name is String ? _toolsByName[name] : null;
    if (tool == null) {
      return _RpcError(McpErrorCodes.invalidParams, 'Unknown tool: $name');
    }
    final arguments = params['arguments'] ?? const <String, Object?>{};
    if (arguments is! Map<String, Object?>) {
      return const _RpcError(
        McpErrorCodes.invalidParams,
        'arguments must be an object.',
      );
    }

    final stopwatch = Stopwatch()..start();
    McpToolResult result;
    try {
      result = await tool.handler(McpArguments(arguments));
    } on McpToolError catch (error) {
      result = McpToolResult.error(error.message);
    } catch (error) {
      result = McpToolResult.error('Eagly failed to run ${tool.name}: $error');
    }
    onToolCall?.call(
      McpToolCall(
        tool: tool.name,
        client: client,
        elapsed: stopwatch.elapsed,
        isError: result.isError,
        errorMessage: result.isError ? result.text : null,
      ),
    );
    return result.toJson();
  }

  McpResponse _mismatch(Object id, String message) => _error(
    400,
    id,
    McpErrorCodes.headerMismatch,
    'Header mismatch: $message',
  );

  McpResponse _error(int status, Object? id, int code, String message) =>
      McpResponse(status, {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      });

  /// Decodes the `=?base64?…?=` sentinel clients use for header values that
  /// aren't plain ASCII.
  static String? _decodeHeaderValue(String? value) {
    if (value == null) return null;
    if (value.startsWith('=?base64?') && value.endsWith('?=')) {
      try {
        return utf8.decode(base64Decode(value.substring(9, value.length - 2)));
      } on FormatException {
        return value;
      }
    }
    return value;
  }
}

class const _RpcError(final int code, final String message);
