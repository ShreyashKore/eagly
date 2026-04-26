import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logview/data/device.dart';
import 'package:logview/services/device_bridge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String adbPath;
  late String ideviceIdPath;
  late String ideviceInfoPath;
  late String ideviceSyslogPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('device-bridge-test');
    adbPath = await _writeExecutable(tempDir, 'adb', r'''#!/bin/sh
if [ "$1" = "-s" ] && [ "$3" = "shell" ] && [ "$4" = "getprop" ]; then
  cat <<'EOF'
[ro.product.brand]: [google]
[ro.product.model]: [Pixel 8]
[ro.product.device]: [husky]
EOF
  exit 0
fi
if [ "$1" = "connect" ]; then
  echo "failed to connect to $2"
  exit 0
fi
if [ "$1" = "pair" ]; then
  echo "Successfully paired"
  exit 0
fi
exit 0
''');
    ideviceIdPath = await _writeExecutable(tempDir, 'idevice_id', r'''#!/bin/sh
if [ "$1" = "-l" ]; then
  printf 'abc123\n\n  def456  \n'
fi
''');
    ideviceInfoPath = await _writeExecutable(
      tempDir,
      'ideviceinfo',
      r'''#!/bin/sh
if [ "$1" = "-u" ]; then
  cat <<'EOF'
DeviceName: QA iPhone
ProductName: iPhone OS
HardwareModel: N71AP
EOF
fi
''',
    );
    ideviceSyslogPath = await _writeExecutable(
      tempDir,
      'idevicesyslog',
      '#!/bin/sh\nexit 0\n',
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  DeviceBridgeService buildService() {
    return DeviceBridgeService(
      adbPath: adbPath,
      ideviceIdPath: ideviceIdPath,
      ideviceInfoPath: ideviceInfoPath,
      ideviceSyslogPath: ideviceSyslogPath,
    );
  }

  test('getIosDeviceIds trims blank lines and whitespace', () async {
    final service = buildService();

    final deviceIds = await service.getIosDeviceIds();

    expect(deviceIds, ['abc123', 'def456']);
  });

  test('describeIosDevice uses fallback fields without ProductType', () async {
    final service = buildService();

    final device = await service.describeIosDevice('abc123');

    expect(device, isA<Device>());
    expect(device.id, 'abc123');
    expect(device.platform, DevicePlatform.ios);
    expect(device.status, 'device');
    expect(device.name, 'QA iPhone');
    expect(device.model, 'N71AP');
  });

  test('describeAndroidDevice parses brand, model and device name', () async {
    final service = buildService();

    final device = await service.describeAndroidDevice('emulator-5554');

    expect(device, isA<Device>());
    expect(device.id, 'emulator-5554');
    expect(device.platform, DevicePlatform.android);
    expect(device.status, 'device');
    expect(device.brand, 'Google');
    expect(device.model, 'Pixel 8');
    expect(device.name, 'husky');
    expect(device.displayLabel.primary, 'emulator-5554');
    expect(device.displayLabel.secondary, 'Google Pixel 8');
  });

  test(
    'connectDevice treats failed output as a failure even with exit code 0',
    () async {
      final service = buildService();

      final result = await service.connectDevice('127.0.0.1:5555');

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('failed to connect to 127.0.0.1:5555'));
    },
  );
}

Future<String> _writeExecutable(
  Directory directory,
  String name,
  String content,
) async {
  final file = File('${directory.path}/$name');
  await file.writeAsString(content);
  final chmodResult = await Process.run('chmod', ['+x', file.path]);
  if (chmodResult.exitCode != 0) {
    throw StateError('Failed to mark ${file.path} executable');
  }
  return file.path;
}
