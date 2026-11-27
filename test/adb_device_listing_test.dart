import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/app_log/app_logger.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/services/tools/adb_tool.dart';
import 'package:eagly/services/tools/tool_process_runner.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/session_test_support.dart' show FakeIosDeviceService;

/// The device lines `adb devices -l` prints for [serials], without its
/// header: also the payload of an `adb track-devices -l` frame.
String _deviceLines(List<String> serials, {String status = 'device'}) => [
  for (final serial in serials)
    '$serial          $status usb:1-1 product:p model:M_$serial device:d '
        'transport_id:1\n',
].join();

/// One `adb track-devices` frame: four hex digits of byte length, then the
/// payload.
List<int> _frame(String payload) {
  final bytes = utf8.encode(payload);
  return [
    ...ascii.encode(bytes.length.toRadixString(16).padLeft(4, '0')),
    ...bytes,
  ];
}

const _fourPhones = ['R58M1', 'R58M2', 'R58M3', 'R58M4'];

/// Real [AdbTool] logic over a fake process boundary: every `adb devices -l`
/// is counted, can be held open with [gate], and answers [serials];
/// `adb track-devices` is a [_FakeTrackerProcess] the test writes frames to.
class _CountingAdbTool() extends AdbTool {
  this : super(executablePath: '/usr/bin/true');

  List<String> serials = const [];
  int listCalls = 0;
  bool failListing = false;

  /// While set, `adb devices -l` does not return until it completes.
  Completer<void>? gate;

  final List<_FakeTrackerProcess> trackers = [];

  @override
  Future<void> ensureServerRunning() async {}

  @override
  Future<ToolCommandResult> runText(List<String> arguments) async {
    if (arguments.length == 2 &&
        arguments[0] == 'devices' &&
        arguments[1] == '-l') {
      listCalls++;
      await gate?.future;
      if (failListing) {
        return const ToolCommandResult(
          exitCode: 1,
          stdout: '',
          stderr: 'error: protocol fault',
        );
      }
      return ToolCommandResult(
        exitCode: 0,
        stdout: 'List of devices attached\n${_deviceLines(serials)}\n',
        stderr: '',
      );
    }
    return const ToolCommandResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<Process> startProcess(
    List<String> arguments, {
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    expect(arguments, ['track-devices', '-l']);
    final tracker = _FakeTrackerProcess();
    trackers.add(tracker);
    return tracker;
  }

  @override
  Future<Device> describeDevice(String deviceId) async =>
      Device(deviceId, 'device', platform: DevicePlatform.android);
}

class _FakeTrackerProcess implements Process {
  final StreamController<List<int>> _stdout = StreamController();
  final Completer<int> _exit = Completer();

  void write(List<int> bytes) => _stdout.add(bytes);

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 4242;

  bool get killed => _exit.isCompleted;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_exit.isCompleted) return false;
    unawaited(_stdout.close());
    _exit.complete(-15);
    return true;
  }
}

int _foundLogCount() => AppLogger.global.entries
    .where((entry) => entry.message.startsWith('Found '))
    .length;

void main() {
  late _CountingAdbTool adb;

  setUp(() {
    adb = _CountingAdbTool()..serials = _fourPhones;
    AppLogger.global.clear();
  });

  tearDown(AppLogger.global.clear);

  group('AdbTool.getDevices', () {
    test('concurrent callers share one adb devices process', () async {
      adb.gate = Completer<void>();
      final calls = [for (var i = 0; i < 20; i++) adb.getDevices()];
      // Callers that only want a recent list join the same read.
      calls.add(adb.getDevices(maxAge: AdbTool.recentDeviceListAge));
      adb.gate!.complete();

      final results = await Future.wait(calls);

      expect(adb.listCalls, 1);
      for (final result in results) {
        expect(result.map((device) => device.id), _fourPhones);
      }
      // Each caller owns its list.
      results.first.clear();
      expect(results.last, hasLength(4));
    });

    test('a recent listing is served from cache within maxAge', () async {
      var now = DateTime(2026, 11, 27, 5, 47, 23);
      adb.clock = () => now;

      await adb.getDevices();
      now = now.add(const Duration(milliseconds: 900));
      final cached = await adb.getDevices(maxAge: AdbTool.recentDeviceListAge);
      expect(adb.listCalls, 1);
      expect(cached.map((device) => device.id), _fourPhones);

      now = now.add(const Duration(milliseconds: 200));
      await adb.getDevices(maxAge: AdbTool.recentDeviceListAge);
      expect(adb.listCalls, 2, reason: 'older than maxAge, so re-read');
    });

    test('a caller that passes no maxAge always gets a real read', () async {
      final now = DateTime(2026, 11, 27);
      adb.clock = () => now;

      await adb.getDevices();
      adb.serials = const ['R58M1'];
      final fresh = await adb.getDevices();

      expect(adb.listCalls, 2);
      expect(fresh.map((device) => device.id), ['R58M1']);
    });

    test('a failed listing is not cached as "no devices"', () async {
      final now = DateTime(2026, 11, 27);
      adb.clock = () => now;

      adb.failListing = true;
      expect(await adb.getDevices(), isEmpty);
      adb.failListing = false;
      final retried = await adb.getDevices(maxAge: AdbTool.recentDeviceListAge);

      expect(adb.listCalls, 2);
      expect(retried, hasLength(4));
    });

    test('logs "Found N device(s)" only when the list changes', () async {
      await adb.getDevices();
      await adb.getDevices();
      await adb.getDevices();
      expect(_foundLogCount(), 1);

      adb.serials = const ['R58M1', 'R58M2'];
      await adb.getDevices();
      expect(_foundLogCount(), 2);
    });
  });

  group('AdbTool.watchDeviceChanges', () {
    test('emits one list per track-devices frame, without listing devices '
        'again', () async {
      final lists = <List<Device>>[];
      final sub = adb.watchDeviceChanges().listen(lists.add);
      await pumpEventQueue();
      final tracker = adb.trackers.single;

      // Twenty-five changes on four phones: the old line-by-line watcher ran
      // `adb devices -l` once per device line, a hundred serial calls.
      for (var i = 0; i < 25; i++) {
        tracker.write(_frame(_deviceLines(_fourPhones)));
      }
      await pumpEventQueue();

      expect(lists, hasLength(25));
      expect(lists.last.map((device) => device.id), _fourPhones);
      expect(adb.listCalls, 0);
      await sub.cancel();
    });

    test('sees the last device leave (a bare 0000 frame)', () async {
      final lists = <List<Device>>[];
      final sub = adb.watchDeviceChanges().listen(lists.add);
      await pumpEventQueue();
      final tracker = adb.trackers.single;

      tracker.write(_frame(_deviceLines(const ['R58M1'])));
      tracker.write(ascii.encode('0000'));
      await pumpEventQueue();

      expect(lists, hasLength(2));
      expect(lists.last, isEmpty);
      await sub.cancel();
    });

    test('cancelling an idle watcher stops the tracker', () async {
      final sub = adb.watchDeviceChanges().listen((_) {});
      await pumpEventQueue();

      await sub.cancel().timeout(const Duration(seconds: 1));

      expect(adb.trackers.single.killed, isTrue);
    });

    test(
      'ends when the tracker exits, so the repository restarts it',
      () async {
        var done = false;
        adb.watchDeviceChanges().listen((_) {}, onDone: () => done = true);
        await pumpEventQueue();

        adb.trackers.single.kill();
        await pumpEventQueue();

        expect(done, isTrue);
      },
    );
  });

  group('TrackDevicesFrameDecoder', () {
    test('reassembles frames split across chunks and splits joined ones', () {
      final decoder = TrackDevicesFrameDecoder();
      final one = _frame(_deviceLines(const ['A']));
      final two = _frame(_deviceLines(const ['B', 'C']));
      final bytes = [...one, ...two, ...ascii.encode('0000')];

      expect(decoder.add(bytes.sublist(0, 2)), isEmpty);
      expect(decoder.add(bytes.sublist(2, one.length - 1)), isEmpty);
      expect(decoder.add(bytes.sublist(one.length - 1)), [
        _deviceLines(const ['A']),
        _deviceLines(const ['B', 'C']),
        '',
      ]);
    });

    test('reports output that is not framed', () {
      final decoder = TrackDevicesFrameDecoder();
      expect(decoder.add(ascii.encode('emulator-5554\tdevice\n')), isNull);
      // Starts clean after dropping the garbage.
      expect(decoder.add(ascii.encode('0000')), ['']);
    });
  });

  group('DevicesRepository over AdbTool', () {
    test('a burst of track-devices frames costs one adb devices call', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime(2026, 11, 27, 5, 47, 23));
        adb.clock = clock.now;
        final repository = DevicesRepository.forTesting(
          adbTool: adb,
          iosDeviceService: FakeIosDeviceService(),
          clock: clock.now,
        );
        unawaited(repository.ensureStarted(refreshImmediately: true));
        async.flushMicrotasks();
        expect(adb.listCalls, 1, reason: 'the initial load');
        expect(repository.devices, hasLength(4));
        final tracker = adb.trackers.single;

        // ~20 changes a second for a second and a half, as in the crash
        // report's breadcrumbs.
        for (var i = 0; i < 30; i++) {
          tracker.write(_frame(_deviceLines(_fourPhones)));
          async.elapse(const Duration(milliseconds: 50));
        }
        async.elapse(const Duration(milliseconds: 400));

        expect(adb.listCalls, 2, reason: 'one debounced re-read');

        repository.dispose();
        async.flushMicrotasks();
      });
    });

    test('an unplugged phone still drops out promptly', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime(2026, 11, 27));
        adb.clock = clock.now;
        final repository = DevicesRepository.forTesting(
          adbTool: adb,
          iosDeviceService: FakeIosDeviceService(),
          clock: clock.now,
        );
        unawaited(repository.ensureStarted(refreshImmediately: true));
        async.flushMicrotasks();
        expect(repository.devices.where((d) => d.isConnected), hasLength(4));

        // Unplugged a moment after the last read, well inside the cache age.
        async.elapse(const Duration(milliseconds: 100));
        adb.serials = const ['R58M1', 'R58M2', 'R58M3'];
        adb.trackers.single.write(
          _frame(_deviceLines(const ['R58M1', 'R58M2', 'R58M3'])),
        );
        async.elapse(const Duration(milliseconds: 400));

        expect(repository.devices.where((d) => d.isConnected), hasLength(3));
        expect(
          repository.devices.singleWhere((d) => d.id == 'R58M4').isConnected,
          isFalse,
        );

        repository.dispose();
        async.flushMicrotasks();
      });
    });

    test('the periodic refresh keeps re-reading adb', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime(2026, 11, 27));
        adb.clock = clock.now;
        final repository = DevicesRepository.forTesting(
          adbTool: adb,
          iosDeviceService: FakeIosDeviceService(),
          clock: clock.now,
        );
        unawaited(repository.ensureStarted(refreshImmediately: true));
        async.flushMicrotasks();
        expect(adb.listCalls, 1);

        // A phone plugged in with no track-devices frame (a wedged tracker)
        // is still found by the periodic refresh.
        adb.serials = [..._fourPhones, 'R58M5'];
        async.elapse(const Duration(seconds: 4));
        expect(adb.listCalls, 2);
        expect(repository.devices, hasLength(5));

        async.elapse(const Duration(seconds: 8));
        expect(adb.listCalls, 4);

        repository.dispose();
        async.flushMicrotasks();
      });
    });

    test('an explicit refresh re-reads adb even within the cache age', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime(2026, 11, 27));
        adb.clock = clock.now;
        final repository = DevicesRepository.forTesting(
          adbTool: adb,
          iosDeviceService: FakeIosDeviceService(),
          clock: clock.now,
        );
        unawaited(repository.ensureStarted(refreshImmediately: true));
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 100));
        unawaited(repository.refreshDevices(force: true, showLoading: true));
        async.flushMicrotasks();

        expect(adb.listCalls, 2);

        repository.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
