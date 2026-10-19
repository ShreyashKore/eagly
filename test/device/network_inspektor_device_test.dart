/// Checks, against a real Android device or emulator, that the Network pane
/// finds an app that serves its traffic with Inspektor, follows it live, and
/// carries on across an app restart. Opt-in, so skipped in CI.
///
/// Needs Inspektor's sample app, dev flavour, installed and running. It calls
/// `InspektorRemote.start()`:
///
/// ```bash
/// (cd ../inspektor && ./gradlew :sample:installDevDebug)   # JDK 17
/// adb shell monkey -p com.gyanoba.inspektor.sample -c android.intent.category.LAUNCHER 1
/// EAGLY_TEST_ANDROID_SERIAL=<adb serial> \
///   fvm flutter test test/device/network_inspektor_device_test.dart
/// ```
///
/// It taps the sample's "GET todo" button (OkHttp, a real request to
/// jsonplaceholder.typicode.com), so the device needs the network, and it
/// force-stops and relaunches the app once.
library;

import 'dart:io';
import 'dart:math';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/network/data/network_transaction.dart';
import 'package:eagly/features/network/data/network_transaction_store.dart';
import 'package:eagly/features/network/network_controller.dart';
import 'package:eagly/features/network/services/network_source.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_endpoint.dart';
import 'package:eagly/services/device_session_repository.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:eagly/session/workspace_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _serial = Platform.environment['EAGLY_TEST_ANDROID_SERIAL'];
final _package =
    Platform.environment['EAGLY_TEST_INSPEKTOR_PACKAGE'] ??
    'com.gyanoba.inspektor.sample';

final String _adb = () {
  final os = Platform.isMacOS
      ? 'macos'
      : Platform.isWindows
      ? 'windows'
      : 'linux';
  return '${Directory.current.path}/platform-tools/$os/adb';
}();

Future<String> _shell(List<String> args) async {
  final result = await Process.run(_adb, ['-s', _serial!, 'shell', ...args]);
  return (result.stdout as String).trim();
}

/// The host ports adb forwards right now, for any device.
Future<Set<int>> _forwardedPorts() async {
  final list =
      (await Process.run(_adb, ['forward', '--list'])).stdout as String;
  return {
    for (final match in RegExp(r' tcp:(\d+) ').allMatches(list))
      int.parse(match.group(1)!),
  };
}

/// The real repository, remembering the port of every tunnel it opens. Only
/// those are checked: another Eagly watching the same device makes its own.
class _RecordingRepository({required super.device, super.adbPath})
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

/// Taps the on-screen element whose text is [text], found in a UI dump.
Future<void> _tapText(String text) async {
  await _shell(['uiautomator', 'dump', '/sdcard/eagly-ui.xml']);
  final dump = await _shell(['cat', '/sdcard/eagly-ui.xml']);
  final match = RegExp(
    'text="${RegExp.escape(text)}"[^>]*?bounds="\\[(\\d+),(\\d+)\\]\\[(\\d+),(\\d+)\\]"',
  ).firstMatch(dump);
  if (match == null) fail('No "$text" on screen.');
  final [x1, y1, x2, y2] = [
    for (var i = 1; i <= 4; i++) int.parse(match.group(i)!),
  ];
  await _shell(['input', 'tap', '${(x1 + x2) ~/ 2}', '${(y1 + y2) ~/ 2}']);
}

Future<void> _eventually(
  String what,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for $what.');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Waits until no transaction has arrived for a second: after connecting, the
/// backfill streams in for a while.
Future<void> _settle(NetworkController network) async {
  var count = network.entries.length;
  var quietSince = DateTime.now();
  while (DateTime.now().difference(quietSince) < const Duration(seconds: 1)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (network.entries.length != count) {
      count = network.entries.length;
      quietSince = DateTime.now();
    }
  }
}

/// Taps the sample's OkHttp "GET todo" button and returns the request it
/// made. A tap can land on a screen still settling after a launch, so it is
/// retried; only a `/todos/1` request newer than the tap counts.
Future<NetworkEntry> _requestTodo(NetworkController network) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    final floor = _maxId(network);
    await _tapText('GET todo');
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      for (final entry in network.entries) {
        if ((int.tryParse(entry.key.id) ?? 0) > floor &&
            entry.transaction.request.url.endsWith('/todos/1') &&
            entry.transaction.state == NetworkTransactionState.complete) {
          return entry;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  fail('Tapping "GET todo" made no request.');
}

int _maxId(NetworkController network) => network.entries.fold(
  0,
  (highest, e) => max(highest, int.tryParse(e.key.id) ?? 0),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android: an Inspektor app is found, followed live, and continued across '
    'a restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      await PreferencesService.init();
      expect(
        await _shell(['pidof', _package]),
        isNotEmpty,
        reason: '$_package must be running',
      );

      final device = Device(
        _serial!,
        'device',
        platform: DevicePlatform.android,
      );
      final repository = _RecordingRepository(device: device, adbPath: _adb);
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
      expect(network.sources.single.id, startsWith('inspektor:$_package:'));

      // Live: a request made while connected arrives, and its body loads.
      await _settle(network);
      final live = await _requestTodo(network);
      expect(live.transaction.response?.code, 200);
      final body = await network.loadBody(live.key, NetworkBodyPart.response);
      expect(body.text, contains('"userId"'));

      // Restart: a new pid and socket, the same store. The list continues
      // with nothing repeated, through a new forward.
      await _settle(network);
      final idsBefore = [for (final e in network.entries) e.key.id];
      final firstPort = repository.openedPorts.last;
      await _shell(['am', 'force-stop', _package]);
      await _eventually(
        'the connection to end',
        () => network.sources.single.status == NetworkSourceStatus.ended,
      );
      await _shell([
        'monkey',
        '-p',
        _package,
        '-c',
        'android.intent.category.LAUNCHER',
        '1',
      ]);
      await _eventually(
        'the app to come back',
        () => network.sources.single.status == NetworkSourceStatus.live,
      );
      await _settle(network);
      expect([for (final e in network.entries) e.key.id], idsBefore);
      expect(network.sources, hasLength(1));
      expect(repository.openedPorts.last, isNot(firstPort));
      expect(await _forwardedPorts(), isNot(contains(firstPort)));

      await _requestTodo(network);

      // Closing the session removes its forwards. adb can be slow to answer
      // on a busy transport, so give it a while.
      session.dispose();
      disposed = true;
      Future<bool> anyLeft() async {
        final ports = await _forwardedPorts();
        return repository.openedPorts.any(ports.contains);
      }

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (await anyLeft() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(await anyLeft(), isFalse);
    },
    skip: _serial == null ? 'set EAGLY_TEST_ANDROID_SERIAL' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
