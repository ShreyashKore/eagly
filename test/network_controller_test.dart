import 'dart:convert';
import 'dart:io';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/network/data/har.dart';
import 'package:eagly/features/network/data/network_filter.dart';
import 'package:eagly/features/network/data/network_transaction.dart';
import 'package:eagly/features/network/network_controller.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_endpoint.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_watcher.dart';
import 'package:eagly/features/network/services/network_source.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:eagly/session/workspace_layout.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/loopback_inspektor_server.dart';
import 'support/network_test_support.dart';
import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DeviceSessionController? session;
  late FakeSessionService service;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  NetworkController createController() {
    final device = Device(
      'emulator-5554',
      'device',
      platform: DevicePlatform.android,
      model: 'Pixel 8',
    );
    service = FakeSessionService(device);
    session = DeviceSessionController(device: device, service: service);
    return session!.networkController;
  }

  setUp(() => NetworkController.notifyInterval = Duration.zero);

  tearDown(() {
    session?.dispose();
    session = null;
    NetworkController.notifyInterval = const Duration(milliseconds: 100);
    NetworkController.transactionCapacity = 5000;
  });

  List<String> ids(NetworkController controller) => [
    for (final entry in controller.entries) entry.key.id,
  ];

  test('shows what an attached source delivers, updates in place', () async {
    final controller = createController();
    final source = FakeNetworkSource();
    final id = controller.attach(source);

    source
      ..upsert(networkTransaction('1', state: NetworkTransactionState.pending))
      ..upsert(networkTransaction('2'))
      ..upsert(networkTransaction('1'));
    await pumpEventQueue();

    expect(ids(controller), ['1', '2']);
    expect(
      controller.entries.first.transaction.state,
      NetworkTransactionState.complete,
    );
    expect(controller.entries.first.key.source, id);
  });

  test('a burst of events notifies once per interval', () {
    fakeAsync((async) {
      NetworkController.notifyInterval = const Duration(milliseconds: 100);
      final controller = createController();
      final source = FakeNetworkSource();
      controller.attach(source);
      var notifications = 0;
      controller.addListener(() => notifications++);

      for (var i = 0; i < 500; i++) {
        source.upsert(networkTransaction('$i'));
      }
      async.flushMicrotasks();
      expect(controller.entries, hasLength(500));
      expect(notifications, 0);

      async.elapse(const Duration(milliseconds: 100));
      expect(notifications, 1);
    });
  });

  test('tracks each source\'s status', () async {
    final controller = createController();
    final source = FakeNetworkSource(label: 'Shop');
    controller.attach(source);
    source
      ..status(NetworkSourceStatus.live, message: 'Shop')
      ..status(NetworkSourceStatus.failed, message: 'The app went away');
    await pumpEventQueue();

    final info = controller.sources.single;
    expect(info.label, 'Shop');
    expect(info.status, NetworkSourceStatus.failed);
    expect(info.message, 'The app went away');
  });

  group('bodies', () {
    test(
      'concurrent loads share one fetch, then come from the cache',
      () async {
        final controller = createController();
        final source = FakeNetworkSource();
        controller.attach(source);
        source.upsert(networkTransaction('1'));
        await pumpEventQueue();
        final key = controller.entries.single.key;

        final first = controller.loadBody(key, NetworkBodyPart.response);
        final second = controller.loadBody(key, NetworkBodyPart.response);
        expect(
          controller.bodyLoad(key, NetworkBodyPart.response),
          isA<NetworkBodyLoading>(),
        );
        expect((await first).text, 'body of 1');
        await second;
        await controller.loadBody(key, NetworkBodyPart.response);

        expect(source.bodyCalls, 1);
        expect(
          controller.bodyLoad(key, NetworkBodyPart.response),
          isA<NetworkBodyLoaded>(),
        );
      },
    );

    test('a failure is remembered until retried', () async {
      final controller = createController();
      final source = FakeNetworkSource()
        ..onBody = (_, _) => Future.error(StateError('gone'));
      controller.attach(source);
      source.upsert(networkTransaction('1'));
      await pumpEventQueue();
      final key = controller.entries.single.key;

      await expectLater(
        controller.loadBody(key, NetworkBodyPart.response),
        throwsStateError,
      );
      final load = controller.bodyLoad(key, NetworkBodyPart.response);
      expect(load, isA<NetworkBodyFailed>());
      expect((load! as NetworkBodyFailed).message, contains('gone'));

      controller.retryBody(key, NetworkBodyPart.response);
      expect(controller.bodyLoad(key, NetworkBodyPart.response), isNull);
    });

    test(
      'a body read while the exchange ran is dropped when it finishes',
      () async {
        final controller = createController();
        final source = FakeNetworkSource();
        controller.attach(source);
        source.upsert(
          networkTransaction('1', state: NetworkTransactionState.pending),
        );
        await pumpEventQueue();
        final key = controller.entries.single.key;
        await controller.loadBody(key, NetworkBodyPart.request);

        source.upsert(networkTransaction('1'));
        await pumpEventQueue();

        expect(controller.bodyLoad(key, NetworkBodyPart.request), isNull);
      },
    );
  });

  test(
    'past capacity the oldest go, with their selection and bodies',
    () async {
      NetworkController.transactionCapacity = 2;
      final controller = createController();
      final source = FakeNetworkSource();
      controller.attach(source);
      source.upsert(networkTransaction('1'));
      await pumpEventQueue();
      final oldest = controller.entries.single.key;
      controller.select(oldest);
      await controller.loadBody(oldest, NetworkBodyPart.response);

      source
        ..upsert(networkTransaction('2'))
        ..upsert(networkTransaction('3'));
      await pumpEventQueue();

      expect(ids(controller), ['2', '3']);
      expect(controller.selected, isNull);
      expect(controller.bodyLoad(oldest, NetworkBodyPart.response), isNull);
    },
  );

  test('clear empties the list but keeps listening', () async {
    final controller = createController();
    final source = FakeNetworkSource();
    controller.attach(source);
    source.upsert(networkTransaction('1'));
    await pumpEventQueue();

    controller.clear();
    expect(controller.isEmpty, isTrue);

    source.upsert(networkTransaction('2'));
    await pumpEventQueue();
    expect(ids(controller), ['2']);
  });

  group('filtering and sorting', () {
    List<String> visible(NetworkController controller) => [
      for (final entry in controller.visibleEntries) entry.key.id,
    ];

    Future<NetworkController> withEntries() async {
      final controller = createController();
      final source = FakeNetworkSource(label: 'Sample app');
      controller.attach(source);
      source
        ..upsert(networkTransaction('1'))
        ..upsert(networkTransaction('2', code: 404))
        ..upsert(networkTransaction('3', code: 500))
        ..upsert(
          networkTransaction('4', state: NetworkTransactionState.pending),
        );
      await pumpEventQueue();
      return controller;
    }

    test('the query and toggles narrow what the list shows', () async {
      final controller = await withEntries();
      expect(visible(controller), ['1', '2', '3', '4']);

      controller.setFilter(NetworkFilter(query: 'status-code:4xx'));
      expect(visible(controller), ['2']);

      controller.setFilter(
        NetworkFilter(
          statusClasses: {
            NetworkStatusClass.serverError,
            NetworkStatusClass.pending,
          },
        ),
      );
      expect(visible(controller), ['3', '4']);

      controller.setFilter(NetworkFilter(query: 'source:sample -items/1'));
      expect(visible(controller), ['2', '3', '4']);
      expect(controller.entries, hasLength(4), reason: 'nothing is dropped');
    });

    test('sorting reorders without touching capture order', () async {
      final controller = await withEntries();
      controller.setSort(const NetworkSort(NetworkSortColumn.status));
      expect(visible(controller), ['4', '1', '2', '3']);
      controller.setSort(
        const NetworkSort(NetworkSortColumn.status, descending: true),
      );
      expect(visible(controller), ['3', '2', '1', '4']);
      controller.setSort(null);
      expect(visible(controller), ['1', '2', '3', '4']);
    });

    test('arrow-key selection walks the visible rows', () async {
      final controller = await withEntries();
      controller.setFilter(NetworkFilter(query: '-items/2'));
      controller.selectAdjacent(1);
      expect(controller.selected?.key.id, '1');
      controller.selectAdjacent(1);
      expect(controller.selected?.key.id, '3');
      controller.selectAdjacent(5);
      expect(controller.selected?.key.id, '4');
      controller.selectAdjacent(-10);
      expect(controller.selected?.key.id, '1');
    });

    test('clearing drops the time window but keeps the query', () async {
      final controller = await withEntries();
      final now = DateTime(2026);
      controller.setFilter(
        NetworkFilter(query: 'items', timeWindow: NetworkTimeWindow(now, now)),
      );
      controller.clear();
      expect(controller.filter.timeWindow, isNull);
      expect(controller.filter.query, 'items');
    });
  });

  test('a source clearing its store drops only its own entries', () async {
    final controller = createController();
    final app = FakeNetworkSource();
    final other = FakeNetworkSource();
    controller
      ..attach(app)
      ..attach(other);
    app.upsert(networkTransaction('1'));
    other.upsert(networkTransaction('2'));
    await pumpEventQueue();

    app.cleared();
    await pumpEventQueue();
    expect(ids(controller), ['2']);
  });

  test('detach drops the source\'s entries and disposes it', () async {
    final controller = createController();
    final source = FakeNetworkSource();
    final id = controller.attach(source);
    source.upsert(networkTransaction('1'));
    await pumpEventQueue();

    await controller.detach(id);

    expect(controller.isEmpty, isTrue);
    expect(controller.sources, isEmpty);
    expect(source.disposed, isTrue);
  });

  test('disposing the session disposes every source', () async {
    final controller = createController();
    final source = FakeNetworkSource();
    controller.attach(source);

    session!.dispose();
    session = null;
    await pumpEventQueue();

    expect(source.disposed, isTrue);
  });

  group('HAR', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('eagly_har_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('export carries every body the sources can still provide', () async {
      final controller = createController();
      final source = FakeNetworkSource()
        ..onBody = (id, part) => part == NetworkBodyPart.request
            ? Future.error(StateError('not kept'))
            : Future.value(NetworkBody(bytes: utf8.encode('{"id":"$id"}')));
      controller.attach(source);
      source
        ..upsert(networkTransaction('1'))
        ..upsert(networkTransaction('2', code: 500));
      await pumpEventQueue();

      final entries = decodeHar(await controller.exportHarText());

      expect(entries, hasLength(2));
      expect(entries[1].transaction.response!.code, 500);
      expect(entries[0].bodies[NetworkBodyPart.response]!.text, '{"id":"1"}');
      expect(entries[0].bodies[NetworkBodyPart.request], isNull);
    });

    test('an exported file opens as a source of its own', () async {
      final controller = createController();
      final source = FakeNetworkSource();
      controller.attach(source);
      source.upsert(networkTransaction('1'));
      await pumpEventQueue();
      final path = '${dir.path}/capture.har';
      await controller.exportHar(path);
      controller.clear();

      final label = await controller.openHar(path);
      await pumpEventQueue();

      expect(label, 'capture.har');
      final entry = controller.entries.single;
      expect(entry.transaction.request.url, 'https://api.example.com/items/1');
      expect(controller.sourceOf(entry.key)!.status, NetworkSourceStatus.ended);
      expect(
        (await controller.loadBody(entry.key, NetworkBodyPart.response)).text,
        'body of 1',
      );
    });

    test(
      'a file that is not a HAR is refused with a readable reason',
      () async {
        final controller = createController();
        final path = '${dir.path}/notes.txt';
        File(path).writeAsStringSync('hello');

        await expectLater(
          controller.openHar(path),
          throwsA(isA<FormatException>()),
        );
        expect(controller.sources, isEmpty);
      },
    );
  });

  group('one store per app', () {
    test('a source attached under a used key replaces the old one, keeps its '
        'transactions, and serves their bodies', () async {
      final controller = createController();
      final first = FakeNetworkSource();
      controller.attach(first, key: 'inspektor:app:store');
      first.upsert(networkTransaction('1'));
      await pumpEventQueue();

      final second = FakeNetworkSource()
        ..onBody = (id, _) async => NetworkBody(bytes: utf8.encode('new $id'));
      controller.attach(second, key: 'inspektor:app:store');
      second.upsert(networkTransaction('2'));
      await pumpEventQueue();

      expect(ids(controller), ['1', '2']);
      expect(controller.sources, hasLength(1));
      expect(first.disposed, isTrue);
      final body = await controller.loadBody(
        controller.entries.first.key,
        NetworkBodyPart.response,
      );
      expect(body.text, 'new 1');
    });

    test('the resume point survives clearing the list', () async {
      final controller = createController();
      final source = FakeNetworkSource();
      controller.attach(source, key: 'k');
      source
        ..upsert(networkTransaction('9'))
        ..upsert(networkTransaction('10'))
        ..upsert(networkTransaction('2'));
      await pumpEventQueue();

      controller.clear();

      expect(controller.lastIdFor('k'), '10');
      expect(controller.lastIdFor('other'), isNull);
    });
  });

  group('watching for apps', () {
    late LoopbackInspektorServer app;

    setUp(() async {
      InspektorWatcher.pollInterval = const Duration(milliseconds: 10);
      app = await LoopbackInspektorServer.start(transactionIds: ['1', '2']);
    });

    tearDown(() async {
      await app.close();
      InspektorWatcher.pollInterval = const Duration(seconds: 2);
    });

    Future<void> eventually(bool Function() done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) fail('Timed out waiting.');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('polls only while the pane is open', () async {
      final controller = createController();
      await pumpEventQueue();
      expect(controller.isWatching, isFalse);

      session!.openPane(WorkspacePane.network);
      expect(controller.isWatching, isTrue);

      session!.closePane(WorkspacePane.network);
      expect(controller.isWatching, isFalse);
    });

    test('an app on the device shows up, and after a restart its list '
        'continues without repeats', () async {
      final controller = createController();
      service
        ..inspektorEndpoints = const [
          InspektorEndpoint(name: 'inspektor_100_kotlin'),
        ]
        ..onOpenInspektorTunnel = (_) async => app.tunnel();
      session!.openPane(WorkspacePane.network);

      await eventually(() => controller.entries.length == 2);
      expect(controller.sources.single.label, 'Example');
      expect(controller.sources.single.status, NetworkSourceStatus.live);

      // The app dies and comes back under a new pid with one more request.
      await app.dropClients();
      app.transactions.add('3');
      service.inspektorEndpoints = const [
        InspektorEndpoint(name: 'inspektor_200_kotlin'),
      ];

      await eventually(() => controller.entries.length == 3);
      expect(ids(controller), ['1', '2', '3']);
      expect(app.subscribes.last['afterId'], '2');
      expect(controller.sources, hasLength(1));

      app.record('4');
      await eventually(() => controller.entries.length == 4);
    });
  });
}
