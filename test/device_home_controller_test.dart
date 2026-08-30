import 'package:eagly/data/device.dart';
import 'package:eagly/features/device_home/data/device_info.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSessionService service;
  late Device device;
  late DeviceSessionController session;

  setUp(() {
    device = Device(
      'emulator-5554',
      'device',
      platform: DevicePlatform.android,
      brand: 'Google',
      model: 'Pixel 8',
    );
    service = FakeSessionService(device);
    session = DeviceSessionController(device: device, service: service);
  });

  tearDown(() {
    session.dispose();
  });

  test(
    'fetches device info once the controller is created on a connected device',
    () async {
      service.deviceInfoToReturn = const DeviceInfo(
        identity: DeviceIdentityInfo(deviceName: 'Test Pixel'),
      );

      final controller = session.homeController;
      await Future<void>.delayed(Duration.zero);

      expect(controller.deviceInfo.identity.deviceName, 'Test Pixel');
      expect(service.fetchDeviceInfoCount, greaterThanOrEqualTo(1));
    },
  );

  test('keeps the last device info when the device disconnects', () async {
    service.deviceInfoToReturn = const DeviceInfo(
      identity: DeviceIdentityInfo(deviceName: 'Test Pixel'),
    );
    final controller = session.homeController;
    await Future<void>.delayed(Duration.zero);
    expect(controller.deviceInfo.identity.deviceName, 'Test Pixel');

    session.updateDevice(
      device.copyWith(connectionState: DeviceConnectionState.disconnected),
    );

    // The home view renders this snapshot as stale rather than going blank.
    expect(controller.deviceInfo.identity.deviceName, 'Test Pixel');
    expect(controller.hasSnapshot, isTrue);
    expect(controller.lastUpdatedAt, isNotNull);
  });

  test('re-fetches device info on reconnect', () async {
    final controller = session.homeController;
    await Future<void>.delayed(Duration.zero);
    final firstCount = service.fetchDeviceInfoCount;

    session.updateDevice(
      device.copyWith(connectionState: DeviceConnectionState.disconnected),
    );
    session.updateDevice(
      device.copyWith(connectionState: DeviceConnectionState.connected),
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.fetchDeviceInfoCount, greaterThan(firstCount));
    expect(controller.deviceInfo, isNotNull);
  });
}
