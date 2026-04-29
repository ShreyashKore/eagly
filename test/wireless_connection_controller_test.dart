import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logview/ui/wireless_connection/wireless_connection_controller.dart';
import 'package:logview/data/device.dart';
import 'package:logview/data/wireless_debug_models.dart';
import 'package:logview/services/device_repository.dart';
import 'package:logview/services/device_session_service.dart';
import 'package:logview/services/tools/adb_tool.dart';
import 'package:logview/services/tools/idevice_id_tool.dart';
import 'package:logview/services/tools/idevice_info_tool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeWirelessAdbTool adbTool;
  late _FakeWirelessIdeviceIdTool ideviceIdTool;
  late _FakeWirelessIdeviceInfoTool ideviceInfoTool;
  late _FakeWirelessSessionService sessionService;
  late DeviceRepository repository;
  WirelessConnectionController? controller;

  setUp(() {
    adbTool = _FakeWirelessAdbTool();
    ideviceIdTool = _FakeWirelessIdeviceIdTool();
    ideviceInfoTool = _FakeWirelessIdeviceInfoTool();
    sessionService = _FakeWirelessSessionService();
    repository = DeviceRepository.forTesting(
      adbTool: adbTool,
      ideviceIdTool: ideviceIdTool,
      ideviceInfoTool: ideviceInfoTool,
    );
  });

  tearDown(() async {
    controller?.dispose();
    repository.dispose();
    await adbTool.dispose();
  });

  test('discoverWirelessServices stores discovered services and suggestions', () async {
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

    controller = _buildController();

    final result = await controller!.discoverWirelessServices();

    expect(result.isSuccess, isTrue);
    expect(controller!.hasAttemptedWirelessDiscovery, isTrue);
    expect(controller!.wirelessServices, hasLength(2));
    expect(controller!.suggestedWirelessPairingAddress, '192.168.0.10:37111');
    expect(controller!.suggestedWirelessConnectAddress, '192.168.0.10:37112');
    expect(controller!.wirelessMessage, contains('Found 2 wireless ADB services'));
    expect(controller!.wirelessError, isNull);
  });

  test('connectWirelessDevice reuses an already connected wireless device', () async {
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
      onActivateDevice: (device) async {
        selectedDeviceId = device.id;
        isRunning = true;
      },
      selectedDeviceIdProvider: () => selectedDeviceId.isEmpty ? null : selectedDeviceId,
      isRunningProvider: () => isRunning,
    );

    final result = await controller!.connectWirelessDevice(
      address: '192.168.0.117:37251',
    );

    expect(result.isSuccess, isTrue);
    expect(result.message, contains('already connected'));
    expect(selectedDeviceId, '192.168.0.117:37251');
    expect(sessionService.connectRequests, isEmpty);
  });

  test('pairWirelessDevice auto-connects and activates the discovered device', () async {
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
    sessionService.connectResults[connectAddress] = DeviceCommandResult.success(
      message: 'Connected to $connectAddress.',
    );
    sessionService.onConnect = (address) {
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
      onActivateDevice: (device) async {
        activatedDeviceId = device.id;
        selectedDeviceId = device.id;
        isRunning = true;
      },
      selectedDeviceIdProvider: () => selectedDeviceId.isEmpty ? null : selectedDeviceId,
      isRunningProvider: () => isRunning,
    );

    final result = await controller!.pairWirelessDevice(
      address: '192.168.0.77:40000',
      pairingCode: '123456',
    );

    expect(result.isSuccess, isTrue);
    expect(result.autoConnected, isTrue);
    expect(activatedDeviceId, connectAddress);
    expect(sessionService.pairRequests.single, ('192.168.0.77:40000', '123456'));
    expect(sessionService.connectRequests, [connectAddress]);
    expect(result.message, contains('Live logs are ready in this tab'));
  });
}

WirelessConnectionController _buildController({
  required DeviceRepository repository,
  required _FakeWirelessSessionService sessionService,
  Future<void> Function(Device device)? onActivateDevice,
  String? Function()? selectedDeviceIdProvider,
  bool Function()? isRunningProvider,
}) {
  return WirelessConnectionController(
    deviceRepository: repository,
    deviceSessionService: sessionService,
    onDevicesApplied: (_) async {},
    onActivateDevice: onActivateDevice ?? (_) async {},
    selectedDeviceIdProvider: selectedDeviceIdProvider,
    isRunningProvider: isRunningProvider,
  );
}

class _FakeWirelessSessionService extends DeviceSessionService {
  _FakeWirelessSessionService()
    : super(adbPath: '/usr/bin/true', ideviceSyslogPath: '/usr/bin/true');

  final List<(String, String)> pairRequests = [];
  final List<String> connectRequests = [];
  DeviceCommandResult pairResult =
      DeviceCommandResult.success(message: 'Paired successfully');
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
  final StreamController<List<Device>> _watchController =
      StreamController<List<Device>>.broadcast();

  @override
  Future<List<Device>> getDevices() async => List.of(androidDevices);

  @override
  Stream<List<Device>> watchDeviceChanges() => _watchController.stream;

  @override
  Future<WirelessServiceDiscoveryResult> discoverMdnsServices() async {
    return discoveryResult;
  }

  Future<void> dispose() async {
    await _watchController.close();
  }
}

class _FakeWirelessIdeviceIdTool extends IdeviceIdTool {
  _FakeWirelessIdeviceIdTool() : super(executablePath: '/usr/bin/true');

  @override
  Future<List<String>> getDeviceIds() async => const [];
}

class _FakeWirelessIdeviceInfoTool extends IdeviceInfoTool {
  _FakeWirelessIdeviceInfoTool() : super(executablePath: '/usr/bin/true');
}

