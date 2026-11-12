import 'package:eagly/data/device.dart';
import 'package:eagly/features/logs/data/models/log_framework.dart';
import 'package:eagly/features/logs/log_controller.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSessionService service;
  DeviceSessionController? session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  tearDown(() {
    session?.dispose();
    session = null;
  });

  LogController createLog() {
    final device = Device(
      'emulator-5554',
      'device',
      platform: DevicePlatform.android,
    );
    service = FakeSessionService(device);
    session = DeviceSessionController(device: device, service: service);
    return session!.logSessionManager.selectedTab!;
  }

  test('loaded flutter lines are detected and clearLogs resets them', () {
    final log = createLog();
    expect(log.detectedFrameworks, isEmpty);
    expect(log.filter.visibleFrameworks, isEmpty);

    log.logs = [
      testLogEntry(message: 'boot', tag: 'ActivityManager'),
      testLogEntry(message: 'hello', tag: 'flutter'),
    ];
    expect(log.detectedFrameworks, {LogFramework.flutter});
    expect(log.filter.visibleFrameworks, [LogFramework.flutter]);

    log.clearLogs();
    expect(log.detectedFrameworks, isEmpty);
    expect(log.filter.visibleFrameworks, isEmpty);
  });

  test('game engine lines are detected', () {
    final log = createLog();
    log.logs = [
      testLogEntry(message: 'boot', tag: 'ActivityManager'),
      testLogEntry(message: 'Player started', tag: 'Unity'),
      testLogEntry(message: 'Godot Engine v4.4', tag: 'godot'),
    ];
    expect(log.detectedFrameworks, {LogFramework.unity, LogFramework.godot});
    expect(log.filter.visibleFrameworks, [
      LogFramework.unity,
      LogFramework.godot,
    ]);
  });

  test('streamed lines are detected on flush', () async {
    final log = createLog();
    await log.startLogcat();

    service.emit(testLogEntry(message: 'boot', tag: 'ActivityManager'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(log.filter.visibleFrameworks, isEmpty);

    service.emit(testLogEntry(message: 'Running JS', tag: 'ReactNativeJS'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(log.detectedFrameworks, {LogFramework.reactNative});
    expect(log.filter.visibleFrameworks, [LogFramework.reactNative]);

    // A fresh capture hides the chip until the framework logs again.
    await log.startLogcat();
    expect(log.detectedFrameworks, isEmpty);
    expect(log.filter.visibleFrameworks, isEmpty);
    await log.stopLogcat();
  });

  test('an only filter narrows filteredLogs and survives a clear', () {
    final log = createLog();
    log.logs = [
      testLogEntry(message: 'native', tag: 'ActivityManager'),
      testLogEntry(message: 'dart', tag: 'flutter'),
      testLogEntry(message: 'engine', tag: 'FlutterJNI'),
    ];

    log.filter.setFrameworkMode(LogFramework.flutter, FrameworkFilterMode.only);
    expect(log.filteredLogs.map((entry) => entry.message), ['dart', 'engine']);

    log.filter.setFrameworkMode(LogFramework.flutter, FrameworkFilterMode.hide);
    expect(log.filteredLogs.map((entry) => entry.message), ['native']);

    log.clearLogs();
    expect(log.detectedFrameworks, isEmpty);
    // The active filter keeps its chip so it can be removed.
    expect(log.filter.visibleFrameworks, [LogFramework.flutter]);
  });
}
