import 'dart:io';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/logs/services/log_file_service.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A minimal valid Android Studio logcat JSON export with a single entry.
const _validExportJson =
    '{"logcatMessages":[{"header":{"entryType":"log","logLevel":"INFO",'
    '"pid":1,"tid":2,"tag":"T","applicationId":"com.example",'
    '"processName":"p","timestamp":{"seconds":1,"nanos":0}},'
    '"message":"hello world"}]}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
    tempDir = Directory.systemTemp.createTempSync('log-file-service-test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('suggestedExportFileName names the device, scope and format', () {
    final time = DateTime(2026, 11, 9, 14, 5, 7);
    final device = Device(
      'emulator-5554',
      'device',
      platform: DevicePlatform.android,
    );
    final deviceName = device.displayName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    expect(
      LogFileService.suggestedExportFileName(
        device: device,
        format: LogExportFormat.androidStudio,
        scope: LogExportScope.all,
        time: time,
      ),
      '$deviceName-logs-20261109-140507.json',
    );
    expect(
      LogFileService.suggestedExportFileName(
        device: null,
        format: LogExportFormat.plainText,
        scope: LogExportScope.filtered,
        time: time,
      ),
      'logs-filtered-20261109-140507.txt',
    );
  });

  test('importLogs(path:) parses the file and records it as recent', () async {
    final file = File('${tempDir.path}/capture.json')
      ..writeAsStringSync(_validExportJson);

    final result = await LogFileService.importLogs(path: file.path);

    expect(result.isSuccess, isTrue);
    expect(result.fileName, 'capture.json');
    expect(result.filePath, file.path);
    expect(result.logs, hasLength(1));
    expect(result.logs!.single.message, 'hello world');
    expect(PreferencesService.recentLogFiles, [file.path]);
  });

  test('importLogs(path:) fails for a non-existent file', () async {
    final missingPath = '${tempDir.path}/does-not-exist.json';

    final result = await LogFileService.importLogs(path: missingPath);

    expect(result.isSuccess, isFalse);
    expect(result.cancelled, isFalse);
    expect(result.error, isNotNull);
    expect(PreferencesService.recentLogFiles, isEmpty);
  });

  test('importLogs(path:) fails for malformed content', () async {
    final file = File('${tempDir.path}/garbage.json')
      ..writeAsStringSync('not json at all');

    final result = await LogFileService.importLogs(path: file.path);

    expect(result.isSuccess, isFalse);
    expect(result.error, contains('garbage.json'));
    expect(PreferencesService.recentLogFiles, isEmpty);
  });
}
