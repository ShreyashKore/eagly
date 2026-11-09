import 'dart:async';

import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_endpoint.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_source.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_token.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/loopback_inspektor_server.dart';

/// Polls [done] until it holds, failing after a few seconds.
Future<void> eventually(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting.');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

InspektorEndpoint endpoint(int pid) =>
    InspektorEndpoint(name: 'inspektor_${pid}_kotlin', pid: pid);

void main() {
  late LoopbackInspektorServer server;
  late List<(InspektorSource, String)> attached;
  late InspektorWatcher watcher;

  setUp(() async {
    InspektorWatcher.pollInterval = const Duration(milliseconds: 10);
    InspektorWatcher.retryDelay = const Duration(milliseconds: 200);
    InspektorWatcher.logStartTimeout = const Duration(milliseconds: 50);
    server = await LoopbackInspektorServer.start(transactionIds: ['1', '2']);
    attached = [];
  });

  tearDown(() async {
    watcher.dispose();
    for (final (source, _) in attached) {
      await source.dispose();
    }
    await server.close();
    InspektorWatcher.pollInterval = const Duration(seconds: 2);
    InspektorWatcher.retryDelay = const Duration(seconds: 10);
    InspektorWatcher.logStartTimeout = const Duration(seconds: 3);
  });

  InspektorWatcher watch(
    List<InspektorEndpoint> Function() endpoints, {
    Future<InspektorTunnel> Function(InspektorEndpoint)? openTunnel,
    String? Function(String key)? resumeAfter,
    InspektorTokenListener? Function(InspektorEndpoint)? listenForToken,
  }) => watcher = InspektorWatcher(
    findEndpoints: () async => endpoints(),
    openTunnel: openTunnel ?? (_) async => server.tunnel(),
    resumeAfter: resumeAfter ?? (_) => null,
    attach: (source, key) => attached.add((source, key)),
    listenForToken: listenForToken,
  )..start();

  test('connects to a new app and files it under its store', () async {
    watch(() => [endpoint(100)]);

    await eventually(() => attached.isNotEmpty);

    expect(attached.single.$2, 'inspektor:com.example.app:store-1');
    expect(server.subscribes.single.containsKey('afterId'), isFalse);
  });

  test('a restarted app resumes after the last id of its store, and the old '
      'tunnel closes', () async {
    var endpoints = [endpoint(100)];
    final closed = <String>[];
    watch(
      () => endpoints,
      openTunnel: (e) async => server.tunnel(onClose: () => closed.add(e.name)),
      resumeAfter: (key) =>
          key == 'inspektor:com.example.app:store-1' ? '2' : null,
    );
    await eventually(() => attached.length == 1);

    endpoints = [endpoint(200)];
    await eventually(() => attached.length == 2);

    expect(server.subscribes.last['afterId'], '2');
    expect(attached.last.$2, attached.first.$2);
    await eventually(() => closed.contains('inspektor_100_kotlin'));
  });

  test(
    'a failed connection is left alone until the retry delay passes',
    () async {
      var attempts = 0;
      watch(
        () => [endpoint(100)],
        openTunnel: (_) async {
          attempts++;
          if (attempts == 1) throw StateError('adb forward failed');
          return server.tunnel();
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(attempts, 1);

      await eventually(() => attached.isNotEmpty);
      expect(attempts, 2);
    },
  );

  test('an app whose connection ends is connected again on the next poll, '
      'through a new tunnel', () async {
    var closes = 0;
    watch(
      () => [endpoint(100)],
      openTunnel: (_) async => server.tunnel(onClose: () => closes++),
    );
    await eventually(() => attached.isNotEmpty);

    // An iOS app that restarts takes the same port: the endpoint never
    // leaves the list, only the connection ends.
    await server.dropClients();

    await eventually(() => attached.length == 2);
    expect(closes, 1);
    expect(attached.last.$2, attached.first.$2);
  });

  test('reads an iOS app\'s token from the log from before it connects, '
      'and stops reading once in', () async {
    const token = '0123456789abcdef0123456789abcdef';
    await server.close();
    server = await LoopbackInspektorServer.start(token: token);
    final log = StreamController<LogEntry>();
    final opened = <String>[];
    watch(
      () => [InspektorEndpoint.tcp(38470)],
      listenForToken: (endpoint) {
        opened.add(endpoint.name);
        return InspektorTokenListener(log.stream, port: endpoint.port!);
      },
      openTunnel: (_) async {
        // The app writes its token line as it accepts the connection; the
        // log is already being read by then.
        expect(log.hasListener, isTrue);
        log.add(
          LogEntry(
            timestamp: '',
            pid: '4242',
            tid: '',
            level: 'Notice',
            tag: 'Example',
            message:
                'Inspektor: remote inspection listening on 127.0.0.1:38470, '
                'token $token',
          ),
        );
        return server.tunnel();
      },
    );

    await eventually(() => attached.isNotEmpty);

    expect(opened, ['tcp:38470']);
    expect(server.subscribes, hasLength(1));
    await eventually(() => !log.hasListener);
  });

  test('an app whose token is wrong is not attached', () async {
    await server.close();
    server = await LoopbackInspektorServer.start(
      token: '0123456789abcdef0123456789abcdef',
    );
    final log = StreamController<LogEntry>.broadcast();
    var attempts = 0;
    watch(
      () => [InspektorEndpoint.tcp(38470)],
      listenForToken: (endpoint) =>
          InspektorTokenListener(log.stream, port: endpoint.port!),
      openTunnel: (_) async {
        attempts++;
        log.add(
          LogEntry(
            timestamp: '',
            pid: '4242',
            tid: '',
            level: 'Notice',
            tag: 'Example',
            message:
                'Inspektor: remote inspection listening on 127.0.0.1:38470, '
                'token fedcba9876543210fedcba9876543210',
          ),
        );
        return server.tunnel();
      },
    );

    await eventually(() => attempts >= 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(attached, isEmpty);
    expect(server.subscribes, isEmpty);
  });

  test('stop stops polling, and reset closes every tunnel', () async {
    var polls = 0;
    var closes = 0;
    watch(() {
      polls++;
      return [endpoint(100)];
    }, openTunnel: (_) async => server.tunnel(onClose: () => closes++));
    await eventually(() => attached.isNotEmpty);

    watcher.stop();
    final pollsAtStop = polls;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(polls, pollsAtStop);
    expect(closes, 0);

    watcher.reset();
    expect(closes, 1);
  });
}
