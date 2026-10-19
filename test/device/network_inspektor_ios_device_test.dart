/// Checks, against a real iPhone, that the Network pane finds an app that
/// serves its traffic with Inspektor over usbmux, follows it, and carries on
/// across an app restart. Opt-in, so skipped in CI.
///
/// Needs an app on the phone that calls `InspektorRemote.start()` — any one
/// that makes requests when it launches, since nothing here can tap. The phone
/// must be unlocked: the test relaunches the app with `devicectl`.
///
/// ```bash
/// cd rust && cargo build --release && cd ..
/// EAGLY_TEST_IOS_UDID=<udid> EAGLY_TEST_INSPEKTOR_BUNDLE=<bundle id> \
///   fvm flutter test test/device/network_inspektor_ios_device_test.dart
/// ```
///
/// It also prints what probing the port range costs (docs/NETWORK_INSPECTOR.md
/// §8): Eagly does that every two seconds while the Network pane is open.
library;

import 'dart:io';
import 'dart:math';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/network/data/network_transaction.dart';
import 'package:eagly/features/network/network_controller.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_endpoint.dart';
import 'package:eagly/features/network/services/network_source.dart';
import 'package:eagly/services/device_session_repository.dart';
import 'package:eagly/services/ios/rust_ios_network_service.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:eagly/session/workspace_layout.dart';
import 'package:eagly/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _udid = Platform.environment['EAGLY_TEST_IOS_UDID'];
final _bundle =
    Platform.environment['EAGLY_TEST_INSPEKTOR_BUNDLE'] ??
    'com.gyanoba.inspektor.sample.InspektorSample';

final bool _rustLibraryBuilt = File(
  'rust/target/release/librust_lib_eagly.dylib',
).existsSync();

/// (Re)launches the app, ending a running copy first.
Future<void> _relaunch() async {
  final result = await Process.run('xcrun', [
    'devicectl',
    'device',
    'process',
    'launch',
    '--terminate-existing',
    '--device',
    _udid!,
    _bundle,
  ]);
  if (result.exitCode != 0) fail('Could not launch $_bundle: ${result.stderr}');
}

/// The real repository, remembering the port of every tunnel it opens.
class _RecordingRepository({required super.device})
    extends DeviceSessionRepository {
  final List<int> openedPorts = [];

  @override
  Future<InspektorTunnel> openInspektorTunnel(
    InspektorEndpoint endpoint,
  ) async {
    final tunnel = await super.openInspektorTunnel(endpoint);
    openedPorts.add(tunnel.port);
    return tunnel;
  }
}

Future<void> _eventually(
  String what,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for $what.');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Waits until no transaction has arrived for two seconds.
Future<void> _settle(NetworkController network) async {
  var count = network.entries.length;
  var quietSince = DateTime.now();
  while (DateTime.now().difference(quietSince) < const Duration(seconds: 2)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (network.entries.length != count) {
      count = network.entries.length;
      quietSince = DateTime.now();
    }
  }
}

int _maxId(NetworkController network) => network.entries.fold(
  0,
  (highest, e) => max(highest, int.tryParse(e.key.id) ?? 0),
);

Future<bool> _accepts(int port) async {
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 1),
    );
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'iOS: an Inspektor app is found over usbmux, followed, and continued '
    'across a restart',
    () async {
      await RustLib.init();
      SharedPreferences.setMockInitialValues({});
      await PreferencesService.init();
      await _relaunch();

      // The app opens its server a moment after it launches.
      final probe = RustIosNetworkService();
      final serving = DateTime.now().add(const Duration(seconds: 30));
      while ((await probe.probePorts(_udid!, inspektorPorts)).isEmpty) {
        if (DateTime.now().isAfter(serving)) fail('$_bundle never served.');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      // What a poll costs: every port in the range, probed in parallel.
      final timings = <int>[];
      var open = <int>[];
      for (var i = 0; i < 10; i++) {
        final watch = Stopwatch()..start();
        open = await probe.probePorts(_udid!, inspektorPorts);
        timings.add(watch.elapsedMilliseconds);
      }
      timings.sort();
      // ignore: avoid_print
      print(
        'Probing ${inspektorPorts.length} ports: median ${timings[5]} ms, '
        'max ${timings.last} ms; open: $open',
      );
      expect(open, isNotEmpty, reason: '$_bundle must be serving');

      final device = IosDevice(_udid!, 'device');
      final repository = _RecordingRepository(device: device);
      final session = DeviceSessionController(
        device: device,
        service: repository,
      );
      var disposed = false;
      addTearDown(() {
        if (!disposed) session.dispose();
      });
      final network = session.networkController;
      session.openPane(WorkspacePane.network);

      await _eventually(
        'the app to be attached',
        () => network.sources.any((s) => s.status == NetworkSourceStatus.live),
      );
      expect(network.sources.single.id, startsWith('inspektor:$_bundle:'));

      // The requests the app made while launching, and their bodies.
      await _eventually(
        'a finished request',
        () => network.entries.any(
          (e) => e.transaction.state == NetworkTransactionState.complete,
        ),
      );
      await _settle(network);
      final finished = network.entries.lastWhere(
        (e) =>
            e.transaction.state == NetworkTransactionState.complete &&
            e.transaction.response?.body == NetworkBodyState.available,
      );
      final body = await network.loadBody(
        finished.key,
        NetworkBodyPart.response,
      );
      expect(body.bytes, isNotEmpty);

      // Restart: the same port, most likely, and the same store. The list
      // continues with nothing repeated, through a new forward.
      final idsBefore = [for (final e in network.entries) e.key.id];
      final maxBefore = _maxId(network);
      final firstPort = repository.openedPorts.last;
      await _relaunch();
      await _eventually(
        'the connection to end',
        () => network.sources.single.status != NetworkSourceStatus.live,
      );
      await _eventually(
        'the app to come back',
        () => network.sources.single.status == NetworkSourceStatus.live,
      );
      await _eventually(
        'the relaunched app\'s requests',
        () => _maxId(network) > maxBefore,
      );
      final idsAfter = [for (final e in network.entries) e.key.id];
      expect(idsAfter.take(idsBefore.length), idsBefore);
      expect(idsAfter.toSet(), hasLength(idsAfter.length));
      expect(network.sources, hasLength(1));
      expect(repository.openedPorts.last, isNot(firstPort));
      expect(await _accepts(firstPort), isFalse);

      // Closing the session closes its forwards.
      final lastPort = repository.openedPorts.last;
      session.dispose();
      disposed = true;
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (await _accepts(lastPort) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(await _accepts(lastPort), isFalse);
    },
    skip: _udid == null
        ? 'set EAGLY_TEST_IOS_UDID'
        : !_rustLibraryBuilt
        ? 'run `cargo build --release` in rust/ first'
        : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
