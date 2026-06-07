// ignore_for_file: avoid_print
// Standalone Phase-1 verification harness for ScrcpyClient.
//
// Runs without Flutter:  dart run bin/scrcpy_probe.dart [deviceSerial]
// It connects to scrcpy-server on the device and prints access-unit stats so
// we can confirm the raw H.264 stream flows before wiring up native decode.
import 'dart:async';

import 'package:eagly/services/tools/scrcpy_client.dart';

Future<void> main(List<String> args) async {
  final deviceId = args.isNotEmpty ? args.first : '10BD2G09X3000JT';

  final client = ScrcpyClient(
    adbExecutablePath: 'adb', // use adb from PATH for the standalone harness
    serverJarPath: 'platform-tools/macos/scrcpy-server',
    onLog: (m) => print('· $m'),
  );

  print('Connecting to $deviceId ...');
  final stream = await client.connect(
    deviceId,
    options: const ScrcpyVideoOptions(
      maxSize: 1024,
      maxFps: 60,
      videoBitRate: 8000000,
      logLevel: 'info',
    ),
  );

  print(
    'Connected: name="${stream.deviceName}" codec="${stream.codecId}" '
    'header=${stream.width}x${stream.height}',
  );

  var count = 0;
  var bytes = 0;
  var configCount = 0;
  var keyCount = 0;
  final start = DateTime.now();
  final completer = Completer<void>();

  final sub = stream.packets.listen(
    (p) {
      count++;
      bytes += p.data.length;
      if (p.isConfig) configCount++;
      if (p.isKeyFrame) keyCount++;
      if (count <= 6 || count % 30 == 0) {
        final secs = DateTime.now().difference(start).inMilliseconds / 1000.0;
        final head = p.data
            .take(8)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        print(
          '#$count  config=${p.isConfig} key=${p.isKeyFrame} '
          'size=${p.data.length}  pts=${p.ptsMicros}  '
          '[${(bytes / 1024).toStringAsFixed(0)}KB cfg=$configCount key=$keyCount '
          '${(count / secs).toStringAsFixed(1)}fps]  head=$head',
        );
      }
    },
    onError: (Object e) {
      print('stream error: $e');
      if (!completer.isCompleted) completer.complete();
    },
    onDone: () {
      if (!completer.isCompleted) completer.complete();
    },
  );

  // Run for a few seconds then tear down.
  await Future.any([
    completer.future,
    Future<void>.delayed(const Duration(seconds: 6)),
  ]);

  await sub.cancel();
  await stream.stop();

  final secs = DateTime.now().difference(start).inMilliseconds / 1000.0;
  print(
    '\nDONE: $count packets in ${secs.toStringAsFixed(1)}s '
    '(${(count / secs).toStringAsFixed(1)} fps), '
    '${(bytes / 1024).toStringAsFixed(0)} KB total, '
    'config=$configCount key=$keyCount',
  );
}
