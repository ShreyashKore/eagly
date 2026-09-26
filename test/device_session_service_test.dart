import 'dart:io';

import 'package:eagly/data/device.dart';
import 'package:eagly/services/device_session_repository.dart';
import 'package:eagly/features/wireless_connection/services/wireless_connection_service.dart';
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
if [ "$1" = "-s" ] && [ "$3" = "shell" ] && [ "$4" = "ps" ]; then
  echo start >> "$(dirname "$0")/ps_log"
  sleep 0.2
  echo end >> "$(dirname "$0")/ps_log"
  echo "USER PID PPID VSZ RSS WCHAN ADDR S NAME"
  echo "u0_a1 4242 1 0 0 0 0 S com.foo"
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
      // Mirrors the 1.1.1+ CLI the macOS bundle ships: `install PATH`, with
      // the pre-1.1.1 `-i` flag rejected at option parsing.
      r'''#!/bin/sh
if [ "$1" = "-u" ] && [ "$3" = "install" ]; then
  echo "Complete"
  exit 0
fi
if [ "$1" = "-u" ] && [ "$3" = "-i" ]; then
  echo "ideviceinstaller: invalid option -- i" >&2
  echo "Usage: ideviceinstaller OPTIONS" >&2
  exit 1
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

  DeviceSessionRepository buildService(Device device) {
    return DeviceSessionRepository(
      device: device,
      adbPath: adbPath,
      ideviceInstallerPath: ideviceInstallerPath,
      ideviceSyslogPath: ideviceSyslogPath,
    );
  }

  WirelessConnectionService buildWirelessService() {
    return WirelessConnectionService(adbPath: adbPath);
  }

  test('pairDevice returns success output from adb', () async {
    final service = buildWirelessService();

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
      final service = buildWirelessService();

      final result = await service.connectDevice('127.0.0.1:5555');

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('failed to connect to 127.0.0.1:5555'));
    },
  );

  test(
    'requested pid→package refreshes coalesce and keep their spacing',
    () async {
      final previousInterval = DeviceSessionRepository.pidRefreshMinInterval;
      DeviceSessionRepository.pidRefreshMinInterval = const Duration(
        seconds: 1,
      );
      addTearDown(
        () => DeviceSessionRepository.pidRefreshMinInterval = previousInterval,
      );
      final service = buildService(Device.android('emulator-5554', 'device'));
      final log = File('${tempDir.path}/ps_log');
      int psCalls() => log.existsSync()
          ? log.readAsLinesSync().where((line) => line == 'end').length
          : 0;
      Future<void> waitForPsCalls(int count) async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (psCalls() < count && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      // A burst of requests is one refresh.
      for (var index = 0; index < 5; index++) {
        service.requestPidToPackageRefresh();
      }
      await waitForPsCalls(1);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(psCalls(), 1);
      expect(service.getProcessNameFromPid('4242'), 'com.foo');

      // Inside the interval, the next requests wait for it to pass.
      final requestedAt = DateTime.now();
      service.requestPidToPackageRefresh();
      service.requestPidToPackageRefresh();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(psCalls(), 1);
      await waitForPsCalls(2);
      expect(psCalls(), 2);
      expect(
        DateTime.now().difference(requestedAt),
        greaterThan(const Duration(milliseconds: 500)),
      );
      await service.dispose();
    },
  );

  test(
    'a refresh requested mid-flight runs after it, never alongside',
    () async {
      final previousInterval = DeviceSessionRepository.pidRefreshMinInterval;
      DeviceSessionRepository.pidRefreshMinInterval = const Duration(
        milliseconds: 100,
      );
      addTearDown(
        () => DeviceSessionRepository.pidRefreshMinInterval = previousInterval,
      );
      final service = buildService(Device.android('emulator-5554', 'device'));
      final log = File('${tempDir.path}/ps_log');

      final polled = service.refreshPidToPackageMap();
      final joined = service.refreshPidToPackageMap();
      service.requestPidToPackageRefresh();
      await Future.wait([polled, joined]);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (log.readAsLinesSync().length < 4 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(log.readAsLinesSync(), ['start', 'end', 'start', 'end']);
      await service.dispose();
    },
  );

  test('a pid→package refresh reports only the mappings it changed', () async {
    final service = buildService(Device.android('emulator-5554', 'device'));
    final updates = <Map<String, String>>[];
    final sub = service.pidToPackageUpdates.listen(updates.add);

    await service.refreshPidToPackageMap();
    await service.refreshPidToPackageMap();
    await Future<void>.delayed(Duration.zero);

    expect(updates, [
      {'4242': 'com.foo'},
    ]);
    await sub.cancel();
    await service.dispose();
  });

  test('requested pid→package refreshes are a no-op on iOS', () async {
    final service = buildService(
      Device.ios('00008110-001234567890801E', 'device'),
    );
    service.requestPidToPackageRefresh();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(File('${tempDir.path}/ps_log').existsSync(), isFalse);
    await service.dispose();
  });

  test('installApp installs APKs on Android devices via adb', () async {
    final service = buildService(Device.android('emulator-5554', 'device'));

    final result = await service.installApp(
      filePath: '${tempDir.path}/sample.apk',
    );

    expect(result.isSuccess, isTrue);
    expect(result.message, contains('Success'));
  });

  test(
    'installApp installs IPA or app bundles on iOS devices via ideviceinstaller',
    () async {
      final service = buildService(
        Device.ios('00008110-001234567890801E', 'device'),
      );

      final result = await service.installApp(
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
