import 'dart:async';
import 'dart:io';

import '../../data/device.dart';
import '../../data/log_entry.dart';
import '../../data/wireless_debug_models.dart';
import 'tool_process_runner.dart';

class AdbTool extends ToolProcessRunner {
  AdbTool({super.executablePath})
    : super(executableName: 'adb');

  Future<List<Device>> getDevices() async {
    try {
      final result = await runText(['devices', '-l']);
      if (!result.isSuccess) {
        logError(
          'adb devices -l returned non-zero exit code',
          result.combinedOutput,
        );
        return const [];
      }

      final deviceList = <Device>[];
      for (final line in result.stdout.split('\n').skip(1)) {
        final parsed = _parseDeviceLine(line);
        if (parsed != null) {
          deviceList.add(parsed);
        }
      }

      return deviceList;
    } on ProcessException catch (error) {
      logError('ProcessException while listing Android devices', error);
      return const [];
    } catch (error) {
      logError('Unexpected error while listing Android devices', error);
      return const [];
    }
  }

  Stream<List<Device>> watchDeviceChanges() async* {
    Process? process;

    try {
      process = await startProcess(['track-devices', '-l']);
      await for (final line in stdoutLines(process)) {
        if (line.trim().isEmpty) continue;
        yield await getDevices();
      }
    } finally {
      await stopProcess(process);
    }
  }

  Future<Device> describeDevice(String deviceId) async {
    try {
      final result = await runText(['-s', deviceId, 'shell', 'getprop']);
      if (!result.isSuccess) {
        logError(
          'adb shell getprop returned non-zero exit for $deviceId',
          result.combinedOutput,
        );
        return Device.android(deviceId, 'unavailable');
      }

      final properties = _parseAndroidGetPropOutput(result.stdout);
      final brand = _normalizeAndroidBrand(
        _firstNonEmpty(
          properties['ro.product.brand'],
          properties['ro.product.manufacturer'],
        ),
      );
      final model = _firstNonEmpty(
        properties['ro.product.marketname'],
        properties['ro.product.model'],
      );
      final name = _firstNonEmpty(
        properties['ro.product.device'],
        properties['ro.product.name'],
      );

      return Device.android(
        deviceId,
        'device',
        brand: brand,
        model: model,
        name: name,
      );
    } on ProcessException catch (error) {
      logError('ProcessException describing Android device $deviceId', error);
      return Device.android(deviceId, 'unavailable');
    } catch (error) {
      logError('Unexpected error describing Android device $deviceId', error);
      return Device.android(deviceId, 'unavailable');
    }
  }

  Future<WirelessServiceDiscoveryResult> discoverMdnsServices() async {
    try {
      final result = await runText(['mdns', 'services']);
      if (!result.isSuccess) {
        final details = describeCommandFailure(
          'Failed to discover wireless ADB services.',
          result,
        );
        logError('Failed to discover wireless ADB services', details);
        return WirelessServiceDiscoveryResult.failure(error: details);
      }

      final services = <WirelessDebugService>[];
      for (final rawLine in result.stdout.split('\n')) {
        final line = rawLine.trim();
        if (line.isEmpty ||
            line.startsWith('List of discovered mdns services')) {
          continue;
        }

        final match = RegExp(
          r'^(.+?)\s+(_adb-tls-(?:connect|pairing)\._tcp)\.?\s+([^\s:]+):(\d+)$',
        ).firstMatch(line);
        if (match == null) {
          continue;
        }

        final port = int.tryParse(match.group(4)!);
        if (port == null) {
          continue;
        }

        services.add(
          WirelessDebugService(
            name: match.group(1)!.trim(),
            type: _parseMdnsServiceType(match.group(2)!),
            host: match.group(3)!.trim(),
            port: port,
          ),
        );
      }

      services.sort((left, right) {
        final typeOrder = left.type.index.compareTo(right.type.index);
        if (typeOrder != 0) return typeOrder;
        final hostOrder = left.host.compareTo(right.host);
        if (hostOrder != 0) return hostOrder;
        return left.port.compareTo(right.port);
      });

      return WirelessServiceDiscoveryResult.success(services: services);
    } catch (error) {
      logError('Exception while discovering mdns services', error);
      return WirelessServiceDiscoveryResult.failure(
        error:
            'Failed to discover wireless ADB services: ${describeError(error)}',
      );
    }
  }

  Future<DeviceCommandResult> pairDevice({
    required String address,
    required String pairingCode,
  }) async {
    try {
      final result = await runText(['pair', address, pairingCode]);
      if (!result.isSuccess) {
        final details = describeCommandFailure(
          'Failed to pair with $address.',
          result,
        );
        logError('Pair command failed for $address', details);
        return DeviceCommandResult.failure(error: details);
      }

      final message = result.combinedOutput;
      return DeviceCommandResult.success(
        message: message.isEmpty
            ? 'Successfully paired with $address.'
            : message,
      );
    } catch (error) {
      logError('Exception while pairing with $address', error);
      return DeviceCommandResult.failure(
        error: 'Failed to pair with $address: ${describeError(error)}',
      );
    }
  }

  Future<DeviceCommandResult> connectDevice(String address) async {
    try {
      final result = await runText(['connect', address]);
      final output = result.combinedOutput;
      final failed =
          !result.isSuccess || output.toLowerCase().contains('failed');

      if (failed) {
        final details = describeCommandFailure(
          'Failed to connect to $address.',
          result,
        );
        logError('Connect command failed for $address', details);
        return DeviceCommandResult.failure(error: details);
      }

      return DeviceCommandResult.success(
        message: output.isEmpty ? 'Connected to $address.' : output,
      );
    } catch (error) {
      logError('Exception while connecting to $address', error);
      return DeviceCommandResult.failure(
        error: 'Failed to connect to $address: ${describeError(error)}',
      );
    }
  }

  Future<Map<String, String>> getPidToPackageMap(String deviceId) async {
    try {
      final result = await runText(['-s', deviceId, 'shell', 'ps', '-A']);
      final pidToPackage = <String, String>{};

      for (final line in result.stdout.split('\n').skip(1)) {
        if (line.trim().isEmpty) continue;

        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 9) {
          pidToPackage[parts[1]] = parts[8];
        }
      }

      return pidToPackage;
    } catch (error) {
      logError('Failed to read PID->package map for $deviceId', error);
      return const {};
    }
  }

  ToolStreamSession<LogEntry> startLogcat(String deviceId) {
    Process? process;
    var stopRequested = false;
    var stopFuture = Future<void>.value();
    late final StreamController<LogEntry> controller;

    Future<void> stop() {
      if (stopRequested) {
        return stopFuture;
      }
      stopRequested = true;
      stopFuture = stopProcess(process);
      return stopFuture;
    }

    controller = StreamController<LogEntry>(
      onListen: () async {
        try {
          process = await startProcess([
            '-s',
            deviceId,
            'logcat',
            '-v',
            'threadtime',
          ]);
          final stderrFuture = stderrText(process!);
          var emittedLogs = false;

          await for (final line in stdoutLines(process!)) {
            final parsed = LogEntry.parseFromLogcat(line);
            if (parsed != null) {
              emittedLogs = true;
              controller.add(parsed);
            }
          }

          final stderrOutput = (await stderrFuture).trim();
          if (!emittedLogs && stderrOutput.isNotEmpty) {
            controller.add(
              buildToolErrorEntry(
                stderrOutput,
                tag: 'adb logcat',
                processName: deviceId,
              ),
            );
          }
        } on ProcessException catch (error) {
          logError('Failed to start adb logcat for $deviceId', error);
          controller.add(
            buildToolErrorEntry(
              'Failed to start adb logcat: ${describeError(error)}',
              tag: 'adb logcat',
              processName: deviceId,
            ),
          );
        } catch (error) {
          logError(
            'Unexpected error while streaming adb logcat for $deviceId',
            error,
          );
          controller.add(
            buildToolErrorEntry(
              'adb logcat error: ${describeError(error)}',
              tag: 'adb logcat',
              processName: deviceId,
            ),
          );
        } finally {
          await stop();
          await controller.close();
        }
      },
      onCancel: stop,
    );

    return ToolStreamSession(stream: controller.stream, onStop: stop);
  }

  Future<void> stopLogcat(String deviceId) async {
    await runText(['-s', deviceId, 'shell', 'pkill', 'logcat']);
  }

  Future<void> clearLogs(String deviceId) async {
    await runText(['-s', deviceId, 'logcat', '-c']);
  }

  Device? _parseDeviceLine(String line) {
    if (line.trim().isEmpty) return null;

    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;

    final deviceId = parts[0];
    final status = parts[1];

    String? model;
    String? product;

    for (var index = 2; index < parts.length; index++) {
      if (parts[index].startsWith('model:')) {
        model = parts[index].substring('model:'.length);
      } else if (parts[index].startsWith('product:')) {
        product = parts[index].substring('product:'.length);
      }
    }

    return Device.android(deviceId, status, model: model, name: product);
  }

  WirelessDebugServiceType _parseMdnsServiceType(String rawValue) {
    return switch (rawValue.trim()) {
      '_adb-tls-connect._tcp' => WirelessDebugServiceType.connect,
      '_adb-tls-pairing._tcp' => WirelessDebugServiceType.pairing,
      _ => WirelessDebugServiceType.unknown,
    };
  }

  String? _firstNonEmpty(String? first, String? second) {
    if (first != null && first.trim().isNotEmpty) {
      return first.trim();
    }
    if (second != null && second.trim().isNotEmpty) {
      return second.trim();
    }
    return null;
  }

  String? _normalizeAndroidBrand(String? brand) {
    if (brand == null) {
      return null;
    }

    final trimmed = brand.trim();
    if (trimmed.isEmpty || trimmed != trimmed.toLowerCase()) {
      return trimmed.isEmpty ? null : trimmed;
    }

    final words = trimmed.split(RegExp(r'\s+'));
    return words
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  Map<String, String> _parseAndroidGetPropOutput(String stdout) {
    final properties = <String, String>{};
    final propertyPattern = RegExp(r'^\[([^\]]+)\]:\s*\[(.*)\]$');

    for (final rawLine in stdout.split('\n')) {
      final line = rawLine.trim();
      final match = propertyPattern.firstMatch(line);
      if (match == null) {
        continue;
      }

      final key = match.group(1)?.trim();
      final value = match.group(2)?.trim();
      if (key == null || key.isEmpty || value == null || value.isEmpty) {
        continue;
      }

      properties[key] = value;
    }

    return properties;
  }
}
