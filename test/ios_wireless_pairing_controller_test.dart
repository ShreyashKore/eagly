import 'dart:async';

import 'package:eagly/features/wireless_connection/ios_wireless_pairing_controller.dart';
import 'package:eagly/services/ios/ios_wireless_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeIosWirelessService service;
  late IosWirelessPairingController controller;

  setUp(() {
    service = _FakeIosWirelessService();
    controller = IosWirelessPairingController(
      service: service,
      resolveStorageDir: () async => '/tmp/eagly-test',
      hostName: 'Test Mac',
    );
  });

  tearDown(() async {
    controller.dispose();
    await service.close();
  });

  test('start advertises the host and reports the storage dir', () async {
    await controller.start();

    expect(controller.isPairing, isTrue);
    expect(controller.hostName, 'Test Mac');
    expect(service.starts, hasLength(1));
    expect(service.starts.single.$1, 'Test Mac');
    expect(service.starts.single.$3, '/tmp/eagly-test');
  });

  test(
    'a listening event marks the controller as waiting for a device',
    () async {
      await controller.start();
      await service.emit(const IosWirelessPairEvent(kind: 'listening'));

      expect(controller.isAdvertising, isTrue);
      expect(controller.isWaitingForDevice, isTrue);
      expect(controller.pin, isNull);
    },
  );

  test('a pin event surfaces the setup code and stops the wait', () async {
    await controller.start();
    await service.emit(const IosWirelessPairEvent(kind: 'listening'));
    await service.emit(const IosWirelessPairEvent(kind: 'pin', pin: '123456'));

    expect(controller.pin, '123456');
    expect(controller.isWaitingForDevice, isFalse);
  });

  test('a paired event captures the device identity', () async {
    await controller.start();
    await service.emit(const IosWirelessPairEvent(kind: 'listening'));
    await service.emit(
      const IosWirelessPairEvent(
        kind: 'paired',
        deviceName: 'QA iPhone',
        deviceModel: 'iPhone16,2',
        deviceUdid: 'abc123',
      ),
    );

    expect(controller.isPaired, isTrue);
    expect(controller.deviceName, 'QA iPhone');
    expect(controller.deviceModel, 'iPhone16,2');
    expect(controller.deviceUdid, 'abc123');
    expect(controller.error, isNull);
  });

  test('an error event surfaces the message', () async {
    await controller.start();
    await service.emit(const IosWirelessPairEvent(kind: 'listening'));
    await service.emit(
      const IosWirelessPairEvent(kind: 'error', message: 'wrong PIN'),
    );

    expect(controller.error, 'wrong PIN');
    expect(controller.isWaitingForDevice, isFalse);
  });

  test('stop tears down the underlying session', () async {
    await controller.start();
    await controller.stop();

    expect(controller.isPairing, isFalse);
    expect(service.stopCalls, 1);
  });

  group('while the storage dir is still resolving', () {
    late Completer<String> storageDir;

    IosWirelessPairingController slowController() =>
        IosWirelessPairingController(
          service: service,
          resolveStorageDir: () => storageDir.future,
          hostName: 'Test Mac',
        );

    setUp(() => storageDir = Completer<String>());

    test('a second start still advertises only once', () async {
      final slow = slowController();
      addTearDown(slow.dispose);
      final first = slow.start();
      final second = slow.start();
      storageDir.complete('/tmp/eagly-test');
      await Future.wait([first, second]);

      expect(service.starts, hasLength(1));
      expect(slow.isPairing, isTrue);
    });

    test('a stop wins over the start it interrupts', () async {
      final slow = slowController();
      addTearDown(slow.dispose);
      final start = slow.start();
      await slow.stop();
      storageDir.complete('/tmp/eagly-test');
      await start;

      expect(service.starts, isEmpty);
      expect(slow.isPairing, isFalse);
    });

    test('disposing stops the start from advertising', () async {
      final slow = slowController();
      final start = slow.start();
      slow.dispose();
      storageDir.complete('/tmp/eagly-test');
      await start;

      expect(service.starts, isEmpty);
    });
  });

  test('stopping does not report the closing stream as a failure', () async {
    await controller.start();
    await service.emit(const IosWirelessPairEvent(kind: 'listening'));
    await controller.stop();
    await service.close();

    expect(controller.error, isNull);
  });

  test(
    'restart clears the previous outcome and starts a new session',
    () async {
      await controller.start();
      await service.emit(const IosWirelessPairEvent(kind: 'listening'));
      await service.emit(
        const IosWirelessPairEvent(kind: 'paired', deviceUdid: 'abc123'),
      );

      await controller.restart();

      expect(controller.isPaired, isFalse);
      expect(controller.deviceUdid, isNull);
      expect(controller.error, isNull);
      expect(service.starts, hasLength(2));
    },
  );

  test('a stream that ends without an outcome reports an error', () async {
    await controller.start();
    await service.emit(const IosWirelessPairEvent(kind: 'listening'));
    await service.close();

    expect(controller.error, 'Pairing ended without completing.');
  });
}

class _FakeIosWirelessService implements IosWirelessService {
  final List<(String, String, String)> starts = [];
  var stopCalls = 0;
  StreamController<IosWirelessPairEvent>? _controller;

  @override
  IosWirelessPairSession startPairing({
    required String hostName,
    required String hostModel,
    required String storageDir,
  }) {
    starts.add((hostName, hostModel, storageDir));
    _controller = StreamController<IosWirelessPairEvent>();
    return IosWirelessPairSession(
      events: _controller!.stream,
      stop: () async {
        stopCalls++;
      },
    );
  }

  Future<void> emit(IosWirelessPairEvent event) async {
    _controller!.add(event);
    await pumpEventQueue();
  }

  Future<void> close() async {
    await _controller?.close();
    _controller = null;
  }
}
