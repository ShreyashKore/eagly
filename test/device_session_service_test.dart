import 'dart:io';

import 'package:eagly/data/device.dart';
import 'package:eagly/services/device_session_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String adbPath;
  late String ideviceInstallerPath;
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
if [ "$1" = "-s" ] && [ "$3" = "install" ]; then
  echo "Performing Streamed Install"
  echo "Success"
  exit 0
fi
exit 0
''');
    ideviceInstallerPath = await _writeExecutable(
      tempDir,
      'ideviceinstaller',
      r'''#!/bin/sh
if [ "$1" = "-u" ] && [ "$3" = "-i" ]; then
  echo "Complete"
  exit 0
fi
exit 0
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

  DeviceSessionService buildService() {
    return DeviceSessionService(
      adbPath: adbPath,
      ideviceInstallerPath: ideviceInstallerPath,
      ideviceSyslogPath: ideviceSyslogPath,
    );
  }

  test('pairDevice returns success output from adb', () async {
    final service = buildService();

    final result = await service.pairDevice(
      address: '127.0.0.1:1234',
      pairingCode: '654321',
    );

    expect(result.isSuccess, isTrue);
    expect(result.message, contains('Successfully paired'));
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

  test('installApp installs APKs on Android devices via adb', () async {
    final service = buildService();

    final result = await service.installApp(
      device: Device.android('emulator-5554', 'device'),
      filePath: '${tempDir.path}/sample.apk',
    );

    expect(result.isSuccess, isTrue);
    expect(result.message, contains('Success'));
  });

  test(
    'installApp installs IPA or app bundles on iOS devices via ideviceinstaller',
    () async {
      final service = buildService();

      final result = await service.installApp(
        device: Device.ios('00008110-001234567890801E', 'device'),
        filePath: '${tempDir.path}/Sample.ipa',
      );

      expect(result.isSuccess, isTrue);
      expect(result.message, contains('Complete'));
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
