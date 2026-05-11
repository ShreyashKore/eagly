import 'package:flutter_test/flutter_test.dart';
import 'package:devspect/data/device.dart';

void main() {
  test('ios labels trim values and avoid duplicate secondary labels', () {
    final device = Device.ios(
      'ios-1',
      'device',
      name: '  QA iPhone  ',
      model: ' QA iPhone ',
    );

    expect(device, isA<IosDevice>());
    expect(device.displayName, 'QA iPhone');
    expect(device.displayLabel.primary, 'QA iPhone');
    expect(device.displayLabel.secondary, isNull);
  });

  test('android display name ignores whitespace-only metadata', () {
    final device = Device.android(
      'emulator-5554',
      'device',
      brand: '   ',
      model: ' Pixel 8 ',
      name: '  ',
    );

    expect(device, isA<AndroidDevice>());
    expect(device.displayName, 'Pixel 8');
    expect(device.displayLabel.secondary, 'Pixel 8');
  });
}
