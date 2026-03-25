import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/device.dart';
import '../data/log_entry.dart';

class AdbService {
  final String adbPath;

  AdbService({this.adbPath = 'adb'});

  /// Fetches the list of connected devices
  Future<List<Device>> getDevices() async {
    final result = await Process.run(adbPath, ['devices']);
    final lines = (result.stdout as String).split('\n');

    return lines.skip(1).where((l) => l.trim().isNotEmpty).map((l) {
      final parts = l.split('\t');
      return Device(parts[0], parts.length > 1 ? parts[1] : 'unknown');
    }).toList();
  }

  /// Starts logcat for a specific device and returns a stream of log entries
  Stream<LogEntry> startLogcat(String deviceId) async* {
    final process = await Process.start(adbPath, [
      '-s',
      deviceId,
      'logcat',
      '-v',
      'threadtime',
    ]);

    await for (final line in process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final parsed = LogEntry.parse(line);
      if (parsed != null) {
        yield parsed;
      }
    }
  }

  /// Stops logcat for a device (by killing the process)
  Future<void> stopLogcat(String deviceId) async {
    // This is a simple implementation - in production you might want to track processes
    // and kill them explicitly
    await Process.run(adbPath, ['-s', deviceId, 'shell', 'pkill', 'logcat']);
  }

  /// Clears the logcat buffer on the device
  Future<void> clearLogcat(String deviceId) async {
    await Process.run(adbPath, ['-s', deviceId, 'logcat', '-c']);
  }
}
