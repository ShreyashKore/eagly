import 'dart:convert';

import 'package:eagly/features/mcp/mcp_protocol.dart';
import 'package:eagly/features/mcp/mcp_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<McpToolCall> calls;
  late List<McpClientInfo> clients;
  late McpProtocol protocol;

  setUp(() {
    calls = [];
    clients = [];
    protocol = McpProtocol(
      serverName: 'eagly',
      serverTitle: 'Eagly',
      serverVersion: '1.0.0',
      instructions: 'Use the tools.',
      tools: [
        McpTool(
          name: 'echo',
          title: 'Echo',
          description: 'Echoes its text.',
          inputSchema: objectSchema(
            {'text': stringProperty('What to echo.')},
            required: ['text'],
          ),
          handler: (args) async =>
              McpToolResult.json({'text': args.requiredString('text')}),
        ),
        McpTool(
          name: 'boom',
          title: 'Boom',
          description: 'Throws.',
          inputSchema: objectSchema({}),
          handler: (_) async => throw StateError('bug'),
        ),
      ],
      onClient: clients.add,
      onToolCall: calls.add,
    );
  });

  Map<String, Object?> modernMeta({String version = '2026-07-28'}) => {
    'io.modelcontextprotocol/protocolVersion': version,
    'io.modelcontextprotocol/clientInfo': {
      'name': 'claude-code',
      'title': 'Claude Code',
      'version': '3.0.0',
    },
    'io.modelcontextprotocol/clientCapabilities': {},
  };

  Future<McpResponse> send(
    Map<String, Object?> message, {
    Map<String, String> headers = const {},
  }) {
    final lower = {
      for (final MapEntry(:key, :value) in headers.entries)
        key.toLowerCase(): value,
    };
    return protocol.handle((name) => lower[name], jsonEncode(message));
  }

  Future<McpResponse> modern(
    String method, {
    Map<String, Object?> params = const {},
    Map<String, String>? headers,
    String version = '2026-07-28',
  }) => send(
    {
      'jsonrpc': '2.0',
      'id': 1,
      'method': method,
      'params': {...params, '_meta': modernMeta(version: version)},
    },
    headers:
        headers ??
        {
          'MCP-Protocol-Version': version,
          'Mcp-Method': method,
          if (params['name'] case final String name) 'Mcp-Name': name,
        },
  );

  Map<String, Object?> resultOf(McpResponse response) =>
      response.body!['result']! as Map<String, Object?>;

  Map<String, Object?> errorOf(McpResponse response) =>
      response.body!['error']! as Map<String, Object?>;

  group('modern requests', () {
    test(
      'server/discover reports versions, capabilities and identity',
      () async {
        final response = await modern('server/discover');

        expect(response.statusCode, 200);
        final result = resultOf(response);
        expect(result['resultType'], 'complete');
        expect(result['supportedVersions'], contains('2026-07-28'));
        expect(result['supportedVersions'], contains('2025-11-25'));
        expect(result['capabilities'], {
          'tools': {'listChanged': false},
        });
        expect(
          (result['_meta']! as Map)['io.modelcontextprotocol/serverInfo'],
          containsPair('name', 'eagly'),
        );
        expect(result['instructions'], 'Use the tools.');
        expect(clients.single.name, 'Claude Code');
      },
    );

    test('tools/list describes every tool as read-only', () async {
      final tools = resultOf(await modern('tools/list'))['tools']! as List;

      expect(tools.map((t) => (t as Map)['name']), ['echo', 'boom']);
      final annotations = (tools.first as Map)['annotations'] as Map;
      expect(annotations['readOnlyHint'], isTrue);
      expect(annotations['destructiveHint'], isFalse);
    });

    test('tools/call returns structured content and a text copy', () async {
      final response = await modern(
        'tools/call',
        params: {
          'name': 'echo',
          'arguments': {'text': 'hi'},
        },
      );

      final result = resultOf(response);
      expect(result['resultType'], 'complete');
      expect(result['isError'], isFalse);
      expect(result['structuredContent'], {'text': 'hi'});
      expect((result['content']! as List).single, {
        'type': 'text',
        'text': '{"text":"hi"}',
      });
      expect(calls.single.tool, 'echo');
      expect(calls.single.client?.name, 'Claude Code');
    });

    test('a missing argument is a tool error the agent can read', () async {
      final result = resultOf(
        await modern('tools/call', params: {'name': 'echo', 'arguments': {}}),
      );

      expect(result['isError'], isTrue);
      expect(
        ((result['content']! as List).single as Map)['text'],
        '"text" is required.',
      );
    });

    test('a handler that throws is reported, not propagated', () async {
      final result = resultOf(
        await modern('tools/call', params: {'name': 'boom'}),
      );

      expect(result['isError'], isTrue);
      expect(calls.single.isError, isTrue);
    });

    test('an unknown tool is a protocol error', () async {
      final response = await modern('tools/call', params: {'name': 'nope'});

      expect(errorOf(response)['code'], McpErrorCodes.invalidParams);
    });

    test('an unknown method is 404 with method-not-found', () async {
      final response = await modern('resources/list');

      expect(response.statusCode, 404);
      expect(errorOf(response)['code'], McpErrorCodes.methodNotFound);
    });

    test('an unsupported version lists the supported ones', () async {
      final response = await modern('tools/list', version: '2099-01-01');

      expect(response.statusCode, 400);
      final error = errorOf(response);
      expect(error['code'], McpErrorCodes.unsupportedProtocolVersion);
      expect((error['data']! as Map)['supported'], McpVersions.all);
    });

    test('headers must match the body', () async {
      Future<int?> codeFor(Map<String, String> headers) async {
        final response = await modern(
          'tools/call',
          params: {
            'name': 'echo',
            'arguments': {'text': 'x'},
          },
          headers: headers,
        );
        expect(response.statusCode, 400);
        return errorOf(response)['code'] as int?;
      }

      const base = {
        'MCP-Protocol-Version': '2026-07-28',
        'Mcp-Method': 'tools/call',
        'Mcp-Name': 'echo',
      };
      expect(
        await codeFor({...base}..remove('MCP-Protocol-Version')),
        McpErrorCodes.headerMismatch,
      );
      expect(
        await codeFor({...base, 'Mcp-Method': 'tools/list'}),
        McpErrorCodes.headerMismatch,
      );
      expect(
        await codeFor({...base, 'Mcp-Name': 'boom'}),
        McpErrorCodes.headerMismatch,
      );
      expect(
        await codeFor({...base}..remove('Mcp-Name')),
        McpErrorCodes.headerMismatch,
      );
    });

    test('a base64 Mcp-Name is decoded before comparing', () async {
      final response = await modern(
        'tools/call',
        params: {
          'name': 'echo',
          'arguments': {'text': 'x'},
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': '=?base64?${base64Encode(utf8.encode('echo'))}?=',
        },
      );

      expect(response.statusCode, 200);
    });
  });

  group('legacy requests', () {
    test('initialize negotiates a legacy version', () async {
      final response = await send({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-06-18',
          'capabilities': {},
          'clientInfo': {'name': 'cursor', 'version': '1.0'},
        },
      });

      final result = resultOf(response);
      expect(result['protocolVersion'], '2025-06-18');
      expect(result['serverInfo'], containsPair('name', 'eagly'));
      expect(result['instructions'], 'Use the tools.');
      expect(clients.single.name, 'cursor');
    });

    test(
      'initialize offers the newest legacy version for one it lacks',
      () async {
        final result = resultOf(
          await send({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'initialize',
            'params': {'protocolVersion': '2024-11-05'},
          }),
        );

        expect(result['protocolVersion'], McpVersions.legacy.first);
      },
    );

    test('notifications are accepted with 202 and no body', () async {
      final response = await send({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });

      expect(response.statusCode, 202);
      expect(response.body, isNull);
    });

    test('tools/call works with a legacy header, without resultType', () async {
      final response = await send(
        {
          'jsonrpc': '2.0',
          'id': 7,
          'method': 'tools/call',
          'params': {
            'name': 'echo',
            'arguments': {'text': 'old'},
          },
        },
        headers: {'MCP-Protocol-Version': '2025-11-25'},
      );

      final result = resultOf(response);
      expect(response.body!['id'], 7);
      expect(result.containsKey('resultType'), isFalse);
      expect(result['structuredContent'], {'text': 'old'});
    });

    test('a request without the version header counts as 2025-03-26', () async {
      final response = await send({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/list',
      });

      expect(response.statusCode, 200);
    });

    test('a modern version header without _meta is refused', () async {
      final response = await send(
        {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
        headers: {'MCP-Protocol-Version': '2026-07-28'},
      );

      expect(response.statusCode, 400);
      expect(errorOf(response)['code'], McpErrorCodes.headerMismatch);
    });
  });

  test('malformed bodies are refused', () async {
    final notJson = await protocol.handle((_) => null, '{');
    expect(notJson.statusCode, 400);
    expect(errorOf(notJson)['code'], McpErrorCodes.parseError);

    final batch = await protocol.handle((_) => null, '[]');
    expect(batch.statusCode, 400);

    final notRpc = await protocol.handle((_) => null, '{"id": 1}');
    expect(errorOf(notRpc)['code'], McpErrorCodes.invalidRequest);
  });
}
