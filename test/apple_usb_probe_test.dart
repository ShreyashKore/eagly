import 'package:eagly/services/ios/apple_usb_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads an iPhone, iPad and iPod off their device instance ids', () {
    expect(
      parseAppleUsbInstanceId(
        r'USB\VID_05AC&PID_12A8\00008030001A2C3E0E38802E',
      ),
      const AppleUsbDevice(
        serial: '00008030001A2C3E0E38802E',
        kind: AppleUsbDeviceKind.iPhone,
      ),
    );
    expect(
      parseAppleUsbInstanceId(r'USB\VID_05AC&PID_12AB\00008103000A1B2C3D4E5F60')
          ?.kind,
      AppleUsbDeviceKind.iPad,
    );
    expect(
      parseAppleUsbInstanceId(r'USB\VID_05AC&PID_12AA\0123456789abcdef')?.kind,
      AppleUsbDeviceKind.iPod,
    );
  });

  test('ignores case, and upper-cases the serial', () {
    expect(
      parseAppleUsbInstanceId(r'usb\vid_05ac&pid_12a8\abcdef0123'),
      const AppleUsbDevice(
        serial: 'ABCDEF0123',
        kind: AppleUsbDeviceKind.iPhone,
      ),
    );
  });

  test('skips interfaces, other Apple hardware and other vendors', () {
    for (final id in [
      // The iPhone's own interfaces: one device, not three.
      r'USB\VID_05AC&PID_12A8&MI_00\7&2B5D3A1&0&0000',
      r'USB\VID_05AC&PID_12A8&MI_01\7&2B5D3A1&0&0001',
      // A Magic Keyboard, and an iPhone in recovery mode.
      r'USB\VID_05AC&PID_029C\5&1A2B3C4D&0&2',
      r'USB\VID_05AC&PID_1281\CPID:8030',
      // Somebody else's phone, and a hub.
      r'USB\VID_18D1&PID_4EE7\1A2B3C4D',
      r'USB\ROOT_HUB30\4&36E5B0B3&0&0',
      '',
    ]) {
      expect(parseAppleUsbInstanceId(id), isNull, reason: id);
    }
  });
}
