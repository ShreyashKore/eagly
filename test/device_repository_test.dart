import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eagly/data/device.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/services/tools/adb_tool.dart';
import 'package:eagly/data/ios_device_info.dart';
import 'package:eagly/services/ios/ios_device_domains.dart';
import 'package:eagly/services/ios/ios_device_service.dart';

void main() {
  late _FakeAdbTool adbTool;
  late _FakeIosDeviceService iosDevicesService;
  late DevicesRepository repository;

  setUp(() {
    adbTool = _FakeAdbTool();
    iosDevicesService = _FakeIosDeviceService();
    repository = DevicesRepository.forTesting(
      adbTool: adbTool,
      iosDeviceService: iosDevicesService,
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

  test('Android models are shown by their marketing name', () async {
    final lookups = <String>[];
    final namesChanged = ChangeNotifier();
    String? listed;
    final repository = DevicesRepository.forTesting(
      adbTool: adbTool,
      iosDeviceService: iosDevicesService,
      androidMarketingName: ({brand, device, model}) async {
        lookups.add('$brand/$device/$model');
        return listed;
      },
      androidMarketingNamesChanged: namesChanged,
    );
    addTearDown(repository.dispose);
    adbTool.androidDevices = [
      Device('R5CW1234', 'device', platform: DevicePlatform.android),
    ];
    adbTool.androidDescriptions['R5CW1234'] = Device(
      'R5CW1234',
      'device',
      brand: 'Samsung',
      model: 'SM-S911B',
      name: 'dm1q',
      platform: DevicePlatform.android,
    );

    // The list hasn't arrived yet: the raw model stands in.
    await repository.refreshDevices(force: true);
    expect(lookups, ['Samsung/dm1q/SM-S911B']);
    expect(repository.devices.single.model, 'SM-S911B');

    // Once it does, the device is described again and renamed.
    listed = 'Galaxy S23';
    namesChanged.notifyListeners();
    await pumpEventQueue();
    expect(repository.devices.single.model, 'Galaxy S23');
    expect(repository.devices.single.name, 'dm1q');
    expect(adbTool.describeAndroidDeviceCalls['R5CW1234'], 2);
  });

  test(
    'a device that names itself keeps its own name over the Play list',
    () async {
      final lookups = <String>[];
      final repository = DevicesRepository.forTesting(
        adbTool: adbTool,
        iosDeviceService: iosDevicesService,
        androidMarketingName: ({brand, device, model}) async {
          lookups.add('$brand/$device/$model');
          return 'Redmi Note 12';
        },
      );
      addTearDown(repository.dispose);
      adbTool.androidDevices = [
        Device('8a7f3c', 'device', platform: DevicePlatform.android),
      ];
      adbTool.androidDescriptions['8a7f3c'] = const AndroidDevice(
        '8a7f3c',
        'device',
        brand: 'Redmi',
        model: '23021RAAEG',
        name: 'sapphire',
        marketName: 'Redmi Note 12 4G',
      );

      await repository.refreshDevices(force: true);

      expect(repository.devices.single.model, 'Redmi Note 12 4G');
      expect(lookups, isEmpty);
    },
  );

  test(
    'Android device not in the online state is treated as disconnected',
    () async {
      adbTool.androidDevices = [
        Device('emulator-5554', 'offline', platform: DevicePlatform.android),
      ];

      await repository.refreshDevices(force: true);

      expect(repository.devices, hasLength(1));
      expect(repository.devices.single.isDisconnected, isTrue);

      adbTool.androidDevices = [
        Device('emulator-5554', 'device', platform: DevicePlatform.android),
      ];
      await repository.refreshDevices(force: true);

      expect(repository.devices.single.isConnected, isTrue);
    },
  );

  test(
    'refreshDevices reuses cached iOS descriptions when the device remains connected',
    () async {
      iosDevicesService.deviceIds = const ['ios-1'];
      iosDevicesService.infos['ios-1'] = const IosDeviceInfo(
        deviceId: 'ios-1',
        status: 'device',
        deviceName: 'QA iPhone',
        hardwareModel: 'iPhone 15',
      );

      await repository.refreshDevices(force: true);

      iosDevicesService.infos['ios-1'] = const IosDeviceInfo(
        deviceId: 'ios-1',
        status: 'device',
      );
      await repository.refreshDevices(force: true);

      // The second refresh must not reopen a lockdown session: a connected
      // device's name cannot change under us, and a TLS handshake per poll is
      // exactly what the description cache exists to avoid.
      expect(iosDevicesService.describeCalls['ios-1'], 1);
      expect(repository.devices.single.name, 'QA iPhone');
      expect(repository.devices.single.model, 'iPhone 15');
    },
  );

  test(
    'iosSupportUnavailable mirrors usbmuxd state and toggles back',
    () async {
      iosDevicesService.usbmuxdUnavailableValue = true;
      await repository.refreshDevices(force: true);
      expect(repository.iosSupportUnavailable, isTrue);

      // Recovers even though the (empty) device list is unchanged.
      iosDevicesService.usbmuxdUnavailableValue = false;
      await repository.refreshDevices(force: true);
      expect(repository.iosSupportUnavailable, isFalse);
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

class _FakeIosDeviceService implements IosDeviceService {
  List<String> deviceIds = const [];
  bool usbmuxdUnavailableValue = false;
  final Map<String, IosDeviceInfo> infos = {};
  final Map<String, int> describeCalls = {};
  final Map<String, IosDeviceDomains> domains = {};

  @override
  Future<List<String>> listDeviceIds() async => List.of(deviceIds);

  @override
  Future<IosDeviceInfo> describeDevice(String deviceId) async {
    describeCalls.update(deviceId, (count) => count + 1, ifAbsent: () => 1);
    return infos[deviceId] ??
        IosDeviceInfo(deviceId: deviceId, status: 'device');
  }

  @override
  Future<IosDeviceDomains> readDeviceDomains(String deviceId) async =>
      domains[deviceId] ?? const IosDeviceDomains();

  @override
  bool get usbmuxdUnavailable => usbmuxdUnavailableValue;
}
