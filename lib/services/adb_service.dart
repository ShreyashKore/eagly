import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/device.dart';
import '../data/log_entry.dart';

class AdbService {
  final String adbPath;
  final Map<String, String> _pidToPackageCache = {};
  Timer? _cacheRefreshTimer;

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

  /// Refresh the PID to package name mapping
  Future<void> refreshPidToPackageMap(String deviceId) async {
    try {
      final result = await Process.run(adbPath, [
        '-s',
        deviceId,
        'shell',
        'ps',
        '-A',
      ]);

      final lines = (result.stdout as String).split('\n');
      _pidToPackageCache.clear();

      for (final line in lines.skip(1)) {
        if (line.trim().isEmpty) continue;

        // ps output format varies, but typically: USER PID PPID VSZ RSS WCHAN ADDR S NAME
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 9) {
          final pid = parts[1];
          final packageName = parts[8];
          _pidToPackageCache[pid] = packageName;
        }
      }
    } catch (e) {
      print('Error refreshing PID to package map: $e');
    }
  }

  /// Get package name from PID
  String? getPackageNameFromPid(String pid) {
    return _pidToPackageCache[pid];
  }

  /// Starts logcat for a specific device and returns a stream of log entries
  Stream<LogEntry> startLogcat(String deviceId) async* {
    // Initial refresh of PID to package mapping
    await refreshPidToPackageMap(deviceId);

    // Refresh the cache every 5 seconds
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      refreshPidToPackageMap(deviceId);
    });

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
        parsed.packageName = getPackageNameFromPid(parsed.pid);
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
