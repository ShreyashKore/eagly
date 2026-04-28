import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logview/services/device_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String adbPath;
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

