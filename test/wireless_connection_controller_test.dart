import 'dart:async';

import 'package:eagly/features/wireless_connection/services/wireless_connection_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eagly/data/device.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/data/ios_device_info.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/services/ios/ios_device_service.dart';
import 'package:eagly/services/tools/adb_tool.dart';
import 'package:eagly/features/wireless_connection/wireless_connection_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeWirelessAdbTool adbTool;
  late _FakeWirelessIosDeviceService iosDevicesService;
  late _FakeWirelessSessionService sessionService;
  late DevicesRepository repository;
  WirelessConnectionController? controller;

  setUp(() {
    adbTool = _FakeWirelessAdbTool();
    iosDevicesService = _FakeWirelessIosDeviceService();
    sessionService = _FakeWirelessSessionService();
    repository = DevicesRepository.forTesting(
      adbTool: adbTool,
      iosDeviceService: iosDevicesService,
    );
  });

  tearDown(() async {
    controller?.dispose();
    repository.dispose();
    await adbTool.dispose();
    WirelessConnectionController.scanInterval = const Duration(
      milliseconds: 1200,
    );
  });

  test(
    'the background scan stores discovered services and suggestions',
    () async {
      WirelessConnectionController.scanInterval = const Duration(
        milliseconds: 1,
      );
      adbTool.discoveryResult = WirelessServiceDiscoveryResult.success(
        services: const [
          WirelessDebugService(
            name: 'Pixel 9 pairing',
            type: WirelessDebugServiceType.pairing,
            host: '192.168.0.10',
            port: 37111,
          ),
          WirelessDebugService(
            name: 'Pixel 9 connect',
            type: WirelessDebugServiceType.connect,
            host: '192.168.0.10',
            port: 37112,
          ),
        ],
      );

      controller = _buildController(
        repository: repository,
        sessionService: sessionService,
      );
      controller!.beginPairing();

      await _waitFor(() => controller!.wirelessServices.isNotEmpty);

      expect(controller!.hasAttemptedWirelessDiscovery, isTrue);
      expect(controller!.wirelessServices, hasLength(2));
      expect(controller!.suggestedWirelessPairingAddress, '192.168.0.10:37111');
      expect(controller!.suggestedWirelessConnectAddress, '192.168.0.10:37112');
      expect(controller!.wirelessError, isNull);
    },
  );

  test(
    'the background scan stops and reports when adb discovery fails',
    () async {
      WirelessConnectionController.scanInterval = const Duration(
        milliseconds: 1,
      );
      adbTool.discoveryResult = WirelessServiceDiscoveryResult.failure(
        error: 'adb unavailable',
      );

      controller = _buildController(
        repository: repository,
        sessionService: sessionService,
      );
      controller!.beginPairing();

      await _waitFor(() => !controller!.isScanning);

      expect(controller!.wirelessError, 'adb unavailable');
      // The code stays on screen so the user can retry after fixing adb.
      expect(controller!.qrSession, isNotNull);
    },
  );

  test('beginPairing publishes a QR code without waiting on discovery', () {
    // Regression guard for the original bug: opening the QR pane while a
    // discovery was in flight left the code ungenerated until that discovery
    // timed out (~10 s). adb never answers here, so the probe stays pending —
    // the code still has to be available immediately.
    adbTool.discoveryDelay = const Duration(seconds: 30);

    controller = _buildController(
      repository: repository,
      sessionService: sessionService,
    );
    controller!.beginPairing();

    final session = controller!.qrSession;
    expect(session, isNotNull);
    expect(session!.payload, startsWith('WIFI:T:ADB;S:'));
    expect(controller!.isScanning, isTrue);
    expect(controller!.isWaitingForQrScan, isTrue);
  });

  test(
    'the background scan pairs the device that scanned the QR code',
    () async {
      WirelessConnectionController.scanInterval = const Duration(
        milliseconds: 1,
      );
      const connectAddress = '192.168.0.88:45555';
      WirelessPairResult? qrResult;

      controller = _buildController(
        repository: repository,
        sessionService: sessionService,
        onQrPairingCompleted: (result) => qrResult = result,
      );
      controller!.beginPairing();

      final serviceName = controller!.qrSession!.serviceName;
      adbTool.onConnect = (address) {
        if (address == connectAddress) {
          adbTool.androidDevices = [
            Device(address, 'device', platform: DevicePlatform.android),
          ];
        }
      };
      // The device scans the code and starts advertising the pairing service.
      adbTool.discoveryResult = WirelessServiceDiscoveryResult.success(
        services: [
          WirelessDebugService(
            name: serviceName,
            type: WirelessDebugServiceType.pairing,
            host: '192.168.0.88',
            port: 40000,
          ),
          const WirelessDebugService(
            name: 'Tablet connect',
            type: WirelessDebugServiceType.connect,
            host: '192.168.0.88',
            port: 45555,
          ),
        ],
      );

      await _waitFor(() => qrResult != null);

      expect(qrResult!.isSuccess, isTrue);
      expect(qrResult!.autoConnected, isTrue);
      expect(adbTool.pairRequests.single.$1, '192.168.0.88:40000');
      expect(adbTool.connectRequests, [connectAddress]);
    },
  );

  test('stopScanning ends the background scan', () async {
    WirelessConnectionController.scanInterval = const Duration(milliseconds: 1);

    controller = _buildController(
      repository: repository,
      sessionService: sessionService,
    );
    controller!.beginPairing();
    await _waitFor(() => adbTool.discoveryCallCount > 0);

    controller!.stopScanning();
    expect(controller!.isScanning, isFalse);
    expect(controller!.isWaitingForQrScan, isFalse);

    final callsAfterStop = adbTool.discoveryCallCount;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(adbTool.discoveryCallCount, callsAfterStop);
  });

  test(
    'connectWirelessDevice reuses an already connected wireless device',
    () async {
      adbTool.androidDevices = [
        Device(
          '192.168.0.117:37251',
          'device',
          platform: DevicePlatform.android,
        ),
      ];
      var selectedDeviceId = '';
      var isRunning = false;

      controller = _buildController(
        repository: repository,
        sessionService: sessionService,
        onActivateDevice: (device) async {
          selectedDeviceId = device.id;
          isRunning = true;
        },
        selectedDeviceIdProvider: () =>
            selectedDeviceId.isEmpty ? null : selectedDeviceId,
        isRunningProvider: () => isRunning,
      );

      final result = await controller!.connectWirelessDevice(
        address: '192.168.0.117:37251',
      );

      expect(result.isSuccess, isTrue);
      expect(result.message, contains('already connected'));
      expect(selectedDeviceId, '192.168.0.117:37251');
      expect(sessionService.connectRequests, isEmpty);
    },
  );

  test(
    'pairWirelessDevice auto-connects and activates the discovered device',
    () async {
      const connectAddress = '192.168.0.77:45555';
      adbTool.discoveryResult = WirelessServiceDiscoveryResult.success(
        services: const [
          WirelessDebugService(
            name: 'Tablet connect',
            type: WirelessDebugServiceType.connect,
            host: '192.168.0.77',
            port: 45555,
          ),
        ],
      );
      sessionService.pairResult = DeviceCommandResult.success(
        message: 'Successfully paired',
      );
      adbTool.onConnect = (address) {
        if (address == connectAddress) {
          adbTool.androidDevices = [
            Device(address, 'device', platform: DevicePlatform.android),
          ];
        }
      };

      var activatedDeviceId = '';
      var selectedDeviceId = '';
      var isRunning = false;

      controller = _buildController(
        repository: repository,
        sessionService: sessionService,
        onActivateDevice: (device) async {
          activatedDeviceId = device.id;
          selectedDeviceId = device.id;
          isRunning = true;
        },
        selectedDeviceIdProvider: () =>
            selectedDeviceId.isEmpty ? null : selectedDeviceId,
        isRunningProvider: () => isRunning,
      );

      final result = await controller!.pairWirelessDevice(
        address: '192.168.0.77:40000',
        pairingCode: '123456',
      );

      expect(result.isSuccess, isTrue);
      expect(result.autoConnected, isTrue);
      expect(activatedDeviceId, connectAddress);
      expect(adbTool.pairRequests.single, ('192.168.0.77:40000', '123456'));
      expect(adbTool.connectRequests, [connectAddress]);
      expect(result.message, contains('Live logs are ready in this tab'));
    },
  );
}

WirelessConnectionController _buildController({
  required DevicesRepository repository,
  required _FakeWirelessSessionService sessionService,
  Future<void> Function(Device device)? onActivateDevice,
  String? Function()? selectedDeviceIdProvider,
  bool Function()? isRunningProvider,
  void Function(WirelessPairResult result)? onQrPairingCompleted,
}) {
  return WirelessConnectionController(
    devicesRepository: repository,
    onDevicesApplied: (_) async {},
    onActivateDevice: onActivateDevice ?? (_) async {},
    selectedDeviceIdProvider: selectedDeviceIdProvider,
    isRunningProvider: isRunningProvider,
    onQrPairingCompleted: onQrPairingCompleted,
  );
}

/// Pumps the event loop until [condition] holds, or fails the test.
Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the expected condition.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _FakeWirelessSessionService extends WirelessConnectionService {
  _FakeWirelessSessionService() : super(adbPath: '/usr/bin/true');

  final List<(String, String)> pairRequests = [];
  final List<String> connectRequests = [];
  DeviceCommandResult pairResult = DeviceCommandResult.success(
    message: 'Paired successfully',
  );
  final Map<String, DeviceCommandResult> connectResults = {};
  void Function(String address)? onConnect;

  @override
  Future<DeviceCommandResult> pairDevice({
    required String address,
    required String pairingCode,
  }) async {
    pairRequests.add((address, pairingCode));
    return pairResult;
  }

  @override
  Future<DeviceCommandResult> connectDevice(String address) async {
    connectRequests.add(address);
    onConnect?.call(address);
    return connectResults[address] ??
        DeviceCommandResult.success(message: 'Connected to $address.');
  }
}

class _FakeWirelessAdbTool extends AdbTool {
  _FakeWirelessAdbTool() : super(executablePath: '/usr/bin/true');

  List<Device> androidDevices = const [];
  WirelessServiceDiscoveryResult discoveryResult =
      const WirelessServiceDiscoveryResult();
  Duration? discoveryDelay;
  var discoveryCallCount = 0;
  final StreamController<List<Device>> _watchController =
      StreamController<List<Device>>.broadcast();
  final List<(String, String)> pairRequests = [];
  final List<String> connectRequests = [];
  void Function(String address)? onConnect;

  @override
  Future<DeviceCommandResult> pairDevice({
    required String address,
    required String pairingCode,
  }) async {
    pairRequests.add((address, pairingCode));
    return DeviceCommandResult.success(
      message: 'Successfully paired with $address.',
    );
  }

  @override
  Future<List<Device>> getDevices() async => List.of(androidDevices);

  @override
  Stream<List<Device>> watchDeviceChanges() => _watchController.stream;

  @override
  Future<WirelessServiceDiscoveryResult> discoverMdnsServices() async {
    discoveryCallCount++;
    final delay = discoveryDelay;
    if (delay != null) await Future<void>.delayed(delay);
    return discoveryResult;
  }

  @override
  Future<DeviceCommandResult> connectDevice(String address) async {
    connectRequests.add(address);
    onConnect?.call(address);
    return DeviceCommandResult.success(message: 'Connected to $address.');
  }

  Future<void> dispose() async {
    await _watchController.close();
  }
}

class _FakeWirelessIosDeviceService implements IosDeviceService {
  @override
  Future<List<String>> listDeviceIds() async => const [];

  @override
  Future<IosDeviceInfo> describeDevice(String deviceId) async =>
      IosDeviceInfo(deviceId: deviceId, status: 'device');

  @override
  bool get usbmuxdUnavailable => false;
}
