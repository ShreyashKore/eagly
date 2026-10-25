import 'dart:convert';
import 'dart:typed_data';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/mcp/mcp_tool.dart';
import 'package:eagly/features/mcp/tools/device_tools.dart';
import 'package:eagly/features/mcp/tools/log_tools.dart';
import 'package:eagly/features/mcp/tools/mcp_tool_context.dart';
import 'package:eagly/features/mcp/tools/network_tools.dart';
import 'package:eagly/features/network/data/network_transaction.dart';
import 'package:eagly/features/network/network_controller.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_manager.dart';
import 'package:eagly/session/workspace_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/network_test_support.dart';
import 'support/session_test_support.dart';

/// The phase-1 tools against fake devices: they read what the session
/// already holds and leave the user's layout alone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdbTool adbTool;
  late DevicesRepository repository;
  late Map<String, FakeSessionService> services;
  DeviceSessionManager? manager;
  McpToolContext? context;
  var redact = true;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() {
    adbTool = FakeAdbTool();
    repository = DevicesRepository.forTesting(
      adbTool: adbTool,
      iosDeviceService: FakeIosDeviceService(),
    );
    services = {};
    redact = true;
    NetworkController.notifyInterval = Duration.zero;
  });

  tearDown(() async {
    context?.dispose();
    context = null;
    manager?.dispose();
    manager = null;
    repository.dispose();
    await adbTool.disposeTool();
    NetworkController.notifyInterval = const Duration(milliseconds: 100);
  });

  Future<void> connect(List<Device> devices) async {
    adbTool.androidDevices = devices;
    manager = DeviceSessionManager(
      repository: repository,
      serviceFactory: (device) =>
          services[device.id] = FakeSessionService(device),
    );
    await repository.refreshDevices(force: true);
    await Future<void>.delayed(Duration.zero);
    context = McpToolContext(manager: manager!, redactHeaders: () => redact);
  }

  Map<String, McpTool> tools() => {
    for (final tool in [
      ...deviceTools(context!),
      ...logTools(context!),
      ...networkTools(context!),
    ])
      tool.name: tool,
  };

  Future<Map<String, Object?>> call(
    String name, [
    Map<String, Object?> args = const {},
  ]) async {
    final result = await tools()[name]!.handler(McpArguments(args));
    expect(result.isError, isFalse, reason: result.text);
    return result.structured!;
  }

  Future<String> callError(
    String name, [
    Map<String, Object?> args = const {},
  ]) async {
    try {
      final result = await tools()[name]!.handler(McpArguments(args));
      fail('Expected an error, got ${result.structured}');
    } on McpToolError catch (error) {
      return error.message;
    }
  }

  LogEntry line(String tag, String message, {String level = 'I'}) => LogEntry(
    timestamp: '10-25 12:00:00.000',
    pid: '100',
    tid: '100',
    level: level,
    tag: tag,
    message: message,
  );

  /// Past `LogController`'s 300 ms flush.
  Future<void> flush() =>
      Future<void>.delayed(const Duration(milliseconds: 350));

  final pixel = Device('emulator-5554', 'device', model: 'Pixel 8');
  final tablet = Device('R5CT', 'device', model: 'Galaxy Tab');

  group('devices', () {
    test('list_devices names every device and the selected one', () async {
      await connect([pixel, tablet]);
      manager!.select('R5CT');

      final result = await call('list_devices');

      final devices = {
        for (final d in result['devices']! as List) (d as Map)['id']: d,
      };
      expect(devices.keys, unorderedEquals(['emulator-5554', 'R5CT']));
      expect(devices['R5CT']!['selectedInEagly'], isTrue);
      expect(devices['emulator-5554']!['selectedInEagly'], isFalse);
      expect(devices['emulator-5554']!['platform'], 'android');
    });

    test('with no device argument, two connected and none selected, '
        'the error lists them', () async {
      await connect([pixel, tablet]);

      final message = await callError('query_logs');

      expect(message, contains('pass "device"'));
      expect(message, contains('emulator-5554'));
      expect(message, contains('R5CT'));
    });

    test('an unknown device is named in the error', () async {
      await connect([pixel]);

      final message = await callError('query_logs', {'device': 'nope'});

      expect(message, contains('No device "nope"'));
    });
  });

  group('logs', () {
    test('query_logs filters with Eagly syntax and returns a cursor', () async {
      await connect([pixel]); // A single device is selected and activated.
      final service = services['emulator-5554']!;
      service
        ..emit(line('Auth', 'login ok'))
        ..emit(line('Net', 'GET /items'))
        ..emit(line('Auth', 'token refreshed', level: 'W'));
      await flush();

      final result = await call('query_logs', {'filter': 'tag:Auth'});

      final entries = result['entries']! as List;
      expect(entries.map((e) => (e as Map)['message']), [
        'login ok',
        'token refreshed',
      ]);
      final cursor = result['cursor']! as Map;
      expect(cursor['newestId'], (entries.last as Map)['id']);

      service.emit(line('Auth', 'logout'));
      await flush();
      final newer = await call('query_logs', {
        'filter': 'tag:Auth',
        'sinceId': cursor['newestId'],
      });
      expect((newer['entries']! as List).map((e) => (e as Map)['message']), [
        'logout',
      ]);
    });

    test('without a filter, only warnings and errors come back', () async {
      await connect([pixel]);
      services['emulator-5554']!
        ..emit(line('A', 'chatty'))
        ..emit(line('A', 'careful', level: 'W'))
        ..emit(line('A', 'broken', level: 'E'));
      await flush();

      final result = await call('query_logs');

      expect((result['entries']! as List).map((e) => (e as Map)['message']), [
        'careful',
        'broken',
      ]);
    });

    test('limit keeps the newest lines and reports hasMore', () async {
      await connect([pixel]);
      final service = services['emulator-5554']!;
      for (var i = 0; i < 5; i++) {
        service.emit(line('T', 'line $i'));
      }
      await flush();

      final result = await call('query_logs', {'filter': 'tag:T', 'limit': 2});

      expect((result['entries']! as List).map((e) => (e as Map)['message']), [
        'line 3',
        'line 4',
      ]);
      expect(result['hasMore'], isTrue);
    });

    test(
      'wait_for_log returns the first new match and the lines before it',
      () async {
        await connect([pixel]);
        final service = services['emulator-5554']!;
        service.emit(line('App', 'old ready')); // Before the wait: not matched.
        await flush();

        final waiting = call('wait_for_log', {
          'filter': 'message:ready',
          'timeoutSeconds': 5,
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
        service
          ..emit(line('App', 'starting'))
          ..emit(line('App', 'now ready'));
        final result = await waiting;

        expect(result['matched'], isTrue);
        expect((result['entry']! as Map)['message'], 'now ready');
        expect(
          (result['before']! as List).map((e) => (e as Map)['message']),
          containsAllInOrder(['starting']),
        );
      },
    );

    test('wait_for_log finds a line logged after sinceId at once', () async {
      await connect([pixel]);
      final service = services['emulator-5554']!;
      service.emit(line('App', 'before'));
      await flush();
      final cursor =
          ((await call('query_logs', {'filter': 'tag:App'}))['cursor']!
              as Map)['newestId'];
      service.emit(line('App', 'crashed'));
      await flush();

      final result = await call('wait_for_log', {
        'filter': 'crashed',
        'sinceId': cursor,
        'timeoutSeconds': 1,
      });

      expect(result['matched'], isTrue);
    });

    test('wait_for_log times out with a cursor', () async {
      await connect([pixel]);

      final result = await call('wait_for_log', {
        'filter': 'never',
        'timeoutSeconds': 1,
      });

      expect(result['matched'], isFalse);
      expect(result['timedOut'], isTrue);
    });
  });

  group('network', () {
    late FakeNetworkSource source;

    Future<void> attach() async {
      await connect([pixel]);
      source = FakeNetworkSource();
      manager!.selected!.networkController.attach(source);
    }

    test('list_network_requests lists newest first, filtered', () async {
      await attach();
      source
        ..upsert(networkTransaction('1'))
        ..upsert(networkTransaction('2', code: 500))
        ..upsert(networkTransaction('3'));
      await Future<void>.delayed(Duration.zero);

      final all = await call('list_network_requests');
      expect((all['requests']! as List).map((r) => (r as Map)['url']), [
        'https://api.example.com/items/3',
        'https://api.example.com/items/2',
        'https://api.example.com/items/1',
      ]);

      final errors = await call('list_network_requests', {'query': 'is:error'});
      expect((errors['requests']! as List).single, containsPair('status', 500));
      expect(errors['totalMatching'], 1);
    });

    test(
      'a network tool keeps the watcher running without opening the pane',
      () async {
        await attach();
        final session = manager!.selected!;

        await call('list_network_requests');

        expect(session.networkController.isWatching, isTrue);
        expect(session.isPaneOpen(WorkspacePane.network), isFalse);
        context!.dispose();
        expect(session.networkController.isWatching, isFalse);
      },
    );

    test('get_network_request returns headers redacted and the body', () async {
      await attach();
      source.onBody = (id, part) async =>
          NetworkBody(bytes: Uint8List.fromList(utf8.encode('{"ok":true}')));
      source.upsert(
        NetworkTransaction(
          id: '9',
          state: NetworkTransactionState.complete,
          request: const NetworkRequestInfo(
            method: 'POST',
            url: 'https://api.example.com/login',
            headers: [
              NetworkHeader('Authorization', 'Bearer abc123'),
              NetworkHeader('Accept', 'application/json'),
            ],
          ),
          response: const NetworkResponseInfo(
            code: 401,
            contentType: 'application/json',
            body: NetworkBodyState.available,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final id =
          ((await call('list_network_requests'))['requests']! as List).single
              as Map;

      final detail = await call('get_network_request', {'id': id['id']});

      final request = detail['request']! as Map;
      expect(request['headers'], [
        'Authorization: <redacted, 13 chars>',
        'Accept: application/json',
      ]);
      final body = (detail['response']! as Map)['body']! as Map;
      expect(body['text'], '{"ok":true}');

      redact = false;
      final open = await call('get_network_request', {'id': id['id']});
      expect(
        (open['request']! as Map)['headers'],
        contains('Authorization: Bearer abc123'),
      );
    });

    test(
      'get_network_request with an unknown id says how to recover',
      () async {
        await attach();

        final message = await callError('get_network_request', {'id': 'x#1'});

        expect(message, contains('list_network_requests'));
      },
    );

    test('with no app attached, the list carries a set-up hint', () async {
      await connect([pixel]);

      final result = await call('list_network_requests');

      expect(result['apps'], isEmpty);
      expect(result['hint'], contains('Inspektor'));
    });

    test('wait_for_network_request returns the next finished match', () async {
      await attach();
      source.upsert(networkTransaction('1')); // Already done: ignored.
      await Future<void>.delayed(Duration.zero);

      final waiting = call('wait_for_network_request', {
        'query': 'items',
        'timeoutSeconds': 5,
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      source.upsert(
        networkTransaction('2', state: NetworkTransactionState.pending),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      source.upsert(networkTransaction('2'));
      final result = await waiting;

      expect(result['matched'], isTrue);
      expect(
        (result['request']! as Map)['url'],
        'https://api.example.com/items/2',
      );
    });
  });
}
