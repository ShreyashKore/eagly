import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:devspect/data/device.dart';
import 'package:devspect/data/ios_device_info.dart';
import 'package:devspect/services/device_repository.dart';
import 'package:devspect/services/tools/adb_tool.dart';
import 'package:devspect/services/tools/idevice_id_tool.dart';
import 'package:devspect/services/tools/idevice_info_tool.dart';

void main() {
  late _FakeAdbTool adbTool;
  late _FakeIdeviceIdTool ideviceIdTool;
  late _FakeIdeviceInfoTool ideviceInfoTool;
  late DeviceRepository repository;

  setUp(() {
    adbTool = _FakeAdbTool();
    ideviceIdTool = _FakeIdeviceIdTool();
    ideviceInfoTool = _FakeIdeviceInfoTool();
    repository = DeviceRepository.forTesting(
      adbTool: adbTool,
      ideviceIdTool: ideviceIdTool,
      ideviceInfoTool: ideviceInfoTool,
    );
  });

  tearDown(() {
    repository.dispose();
    adbTool.dispose();
  });

  test(
    'refreshDevices preserves metadata for devices that become disconnected',
    () async {
      adbTool.androidDevices = [
        Device('emulator-5554', 'device', platform: DevicePlatform.android),
      ];
      adbTool.androidDescriptions['emulator-5554'] = Device(
        'emulator-5554',
        'device',
        brand: 'Google',
        model: 'Pixel 8',
        name: 'husky',
        platform: DevicePlatform.android,
      );

      await repository.refreshDevices(force: true);

      adbTool.androidDevices = const [];
      await repository.refreshDevices(force: true);

      expect(repository.devices, hasLength(1));
      expect(repository.devices.single.id, 'emulator-5554');
      expect(repository.devices.single.brand, 'Google');
      expect(repository.devices.single.model, 'Pixel 8');
      expect(repository.devices.single.name, 'husky');
      expect(repository.devices.single.isDisconnected, isTrue);
    },
  );

  test(
    'refreshDevices reuses cached Android descriptions when the device remains connected',
    () async {
      adbTool.androidDevices = [
        Device('emulator-5554', 'device', platform: DevicePlatform.android),
      ];
      adbTool.androidDescriptions['emulator-5554'] = Device(
        'emulator-5554',
        'device',
        brand: 'Google',
        model: 'Pixel 8',
        name: 'husky',
        platform: DevicePlatform.android,
      );

      await repository.refreshDevices(force: true);

      adbTool.androidDescriptions['emulator-5554'] = Device(
        'emulator-5554',
        'device',
        platform: DevicePlatform.android,
      );
      await repository.refreshDevices(force: true);

      expect(adbTool.describeAndroidDeviceCalls['emulator-5554'], 1);
      expect(repository.devices.single.brand, 'Google');
      expect(repository.devices.single.model, 'Pixel 8');
      expect(repository.devices.single.name, 'husky');
    },
  );

  test(
    'refreshDevices reuses cached iOS descriptions when the device remains connected',
    () async {
      ideviceIdTool.iosDeviceIds = ['ios-1'];
      ideviceInfoTool.iosInfos['ios-1'] = const IosDeviceInfo(
        deviceId: 'ios-1',
        status: 'device',
        deviceName: 'QA iPhone',
        hardwareModel: 'iPhone 15',
      );

      await repository.refreshDevices(force: true);

      ideviceInfoTool.iosInfos['ios-1'] = const IosDeviceInfo(
        deviceId: 'ios-1',
        status: 'device',
      );
      await repository.refreshDevices(force: true);

      expect(ideviceInfoTool.readDeviceInfoCalls['ios-1'], 1);
      expect(repository.devices.single.name, 'QA iPhone');
      expect(repository.devices.single.model, 'iPhone 15');
    },
  );
}

class _FakeAdbTool extends AdbTool {
  _FakeAdbTool() : super(executablePath: '/usr/bin/true');

  List<Device> androidDevices = const [];
  final Map<String, Device> androidDescriptions = {};
  final Map<String, int> describeAndroidDeviceCalls = {};
  final StreamController<List<Device>> _watchController =
      StreamController<List<Device>>.broadcast();

  @override
  Future<List<Device>> getDevices() async => List.of(androidDevices);

  @override
  Future<Device> describeDevice(String deviceId) async {
    describeAndroidDeviceCalls.update(
      deviceId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return androidDescriptions[deviceId] ??
        Device(deviceId, 'device', platform: DevicePlatform.android);
  }

  @override
  Stream<List<Device>> watchDeviceChanges() => _watchController.stream;

  Future<void> dispose() async {
    await _watchController.close();
  }
}

class _FakeIdeviceIdTool extends IdeviceIdTool {
  _FakeIdeviceIdTool() : super(executablePath: '/usr/bin/true');

  List<String> iosDeviceIds = const [];

  @override
  Future<List<String>> getDeviceIds() async => List.of(iosDeviceIds);
}

class _FakeIdeviceInfoTool extends IdeviceInfoTool {
  _FakeIdeviceInfoTool() : super(executablePath: '/usr/bin/true');

  final Map<String, IosDeviceInfo> iosInfos = {};
  final Map<String, int> readDeviceInfoCalls = {};

  @override
  Future<IosDeviceInfo> readDeviceInfo(String deviceId) async {
    readDeviceInfoCalls.update(
      deviceId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return iosInfos[deviceId] ??
        IosDeviceInfo(deviceId: deviceId, status: 'device');
  }
}
