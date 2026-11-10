import 'dart:io';

import 'package:eagly/services/ios/ios_wireless_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory storage;

  setUp(() async {
    storage = await Directory.systemTemp.createTemp('eagly-ios-wireless-');
  });

  tearDown(() async {
    await storage.delete(recursive: true);
  });

  Directory recordsDir() => Directory(
    '${storage.path}${Platform.pathSeparator}$iosWirelessDeviceRecordsDir',
  );

  test('no records folder means no pairings', () async {
    expect(await hasIosWirelessPairings(storage.path), isFalse);
  });

  test('an empty or plist-less records folder means no pairings', () async {
    final dir = await recordsDir().create();
    expect(await hasIosWirelessPairings(storage.path), isFalse);

    await File('${dir.path}${Platform.pathSeparator}notes.txt').create();
    expect(await hasIosWirelessPairings(storage.path), isFalse);
  });

  test('one device record is a pairing', () async {
    final dir = await recordsDir().create();
    await File('${dir.path}${Platform.pathSeparator}00008110-001A2B3C.plist')
        .create();

    expect(await hasIosWirelessPairings(storage.path), isTrue);
  });
}
