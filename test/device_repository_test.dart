import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logview/data/device.dart';
import 'package:logview/services/device_bridge_service.dart';
import 'package:logview/services/device_repository.dart';

void main() {
  late _FakeDeviceBridgeService bridgeService;
  late DeviceRepository repository;

  setUp(() {
    bridgeService = _FakeDeviceBridgeService();
    repository = DeviceRepository.forTesting(
      deviceBridgeService: bridgeService,
    );
  });

  tearDown(() {
    repository.dispose();
    bridgeService.dispose();
  });

  test(
    'refreshDevices preserves metadata for devices that become disconnected',
    () async {
      bridgeService.androidDevices = [
        Device(
          'emulator-5554',
          'device',
          model: 'Pixel_8',
          name: 'sdk_gphone64_arm64',
          platform: DevicePlatform.android,
        ),
      ];

      await repository.refreshDevices(force: true);

      bridgeService.androidDevices = const [];
      await repository.refreshDevices(force: true);

      expect(repository.devices, hasLength(1));
      expect(repository.devices.single.id, 'emulator-5554');
      expect(repository.devices.single.model, 'Pixel_8');
      expect(repository.devices.single.name, 'sdk_gphone64_arm64');
      expect(repository.devices.single.isDisconnected, isTrue);
    },
  );

  test(
    'refreshDevices reuses cached iOS descriptions when the device remains connected',
    () async {
      bridgeService.iosDeviceIds = ['ios-1'];
      bridgeService.iosDescriptions['ios-1'] = Device(
        'ios-1',
        'device',
        name: 'QA iPhone',
        model: 'iPhone 15',
        platform: DevicePlatform.ios,
      );

      await repository.refreshDevices(force: true);

      bridgeService.iosDescriptions['ios-1'] = Device(
        'ios-1',
        'device',
        platform: DevicePlatform.ios,
      );
      await repository.refreshDevices(force: true);

      expect(bridgeService.describeIosDeviceCalls['ios-1'], 1);
      expect(repository.devices.single.name, 'QA iPhone');
      expect(repository.devices.single.model, 'iPhone 15');
    },
  );
}

class _FakeDeviceBridgeService extends DeviceBridgeService {
  _FakeDeviceBridgeService()
    : super(
        adbPath: '/usr/bin/true',
        ideviceIdPath: '/usr/bin/true',
        ideviceInfoPath: '/usr/bin/true',
        ideviceSyslogPath: '/usr/bin/true',
      );

  List<Device> androidDevices = const [];
  List<String> iosDeviceIds = const [];
  final Map<String, Device> iosDescriptions = {};
  final Map<String, int> describeIosDeviceCalls = {};
  final StreamController<String> _watchController =
      StreamController<String>.broadcast();

  @override
  Future<List<Device>> getAndroidDevices() async => List.of(androidDevices);

  @override
  Future<List<String>> getIosDeviceIds() async => List.of(iosDeviceIds);

  @override
  Future<Device> describeIosDevice(String deviceId) async {
    describeIosDeviceCalls.update(
      deviceId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return iosDescriptions[deviceId] ??
        Device(deviceId, 'device', platform: DevicePlatform.ios);
  }

  @override
  Stream<String> watchAndroidDeviceChanges() => _watchController.stream;

  @override
  Future<void> dispose() async {
    await _watchController.close();
  }
}
