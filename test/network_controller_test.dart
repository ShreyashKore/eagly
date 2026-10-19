import 'dart:convert';
import 'dart:io';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/network/data/har.dart';
import 'package:eagly/features/network/data/network_transaction.dart';
import 'package:eagly/features/network/network_controller.dart';
import 'package:eagly/features/network/services/network_source.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/network_test_support.dart';
import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DeviceSessionController? session;

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
    session = DeviceSessionController(
      device: device,
      service: FakeSessionService(device),
    );
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
}
