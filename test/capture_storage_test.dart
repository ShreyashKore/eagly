import 'dart:io';

import 'package:eagly/features/mirror/services/capture_storage.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory temp;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
    temp = await Directory.systemTemp.createTemp('eagly-capture-test');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test('file names carry a sortable timestamp', () {
    final name = CaptureStorage.buildFileName(
      'screenshot',
      'png',
      now: DateTime(2026, 9, 1, 13, 45, 12),
    );
    expect(name, 'screenshot-20260901-134512.png');
  });

  test('directory falls back to the platform default when unset', () {
    expect(
      CaptureStorage.resolveDirectory(),
      CaptureStorage.defaultDirectory(),
    );
    expect(CaptureStorage.defaultDirectory(), endsWith('Eagly'));
  });

  test('a configured directory wins over the default', () async {
    await PreferencesService.setCaptureDirectory(temp.path);
    expect(CaptureStorage.resolveDirectory(), temp.path);

    await PreferencesService.setCaptureDirectory(null);
    expect(
      CaptureStorage.resolveDirectory(),
      CaptureStorage.defaultDirectory(),
    );
  });

  test('the capture directory is created on demand', () async {
    final nested = '${temp.path}${Platform.pathSeparator}nested';
    await PreferencesService.setCaptureDirectory(nested);

    final created = await CaptureStorage.ensureDirectory();

    expect(created.path, nested);
    expect(Directory(nested).existsSync(), isTrue);
  });

  test('target paths land in the configured folder without a dialog', () async {
    await PreferencesService.setCaptureDirectory(temp.path);

    final path = await CaptureStorage.resolveTargetPath(
      dialogTitle: 'Save screenshot',
      prefix: 'screenshot',
      extension: 'png',
    );

    expect(path, isNotNull);
    expect(File(path!).parent.path, temp.path);
    expect(path, endsWith('.png'));
  });

  test('an existing capture is never overwritten', () async {
    await PreferencesService.setCaptureDirectory(temp.path);

    final first = (await CaptureStorage.resolveTargetPath(
      dialogTitle: 'Save screenshot',
      prefix: 'screenshot',
      extension: 'png',
    ))!;
    await File(first).writeAsBytes(const [0]);

    final second = await CaptureStorage.resolveTargetPath(
      dialogTitle: 'Save screenshot',
      prefix: 'screenshot',
      extension: 'png',
    );

    expect(second, isNot(first));
    expect(second, endsWith('-2.png'));
  });
}
