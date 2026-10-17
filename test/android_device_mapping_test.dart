import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:eagly/utils/android_device_mapping.dart';

/// Rows lifted from Google Play's supported_devices.csv, quirks included.
const _csv = '''Retail Branding,Marketing Name,Device,Model
"","","AD681H","Smartfren Andromax AD681H"
"Google","Pixel 8 Pro","husky","Pixel 8 Pro"
"Google","Pixel 9 Pro XL","komodo","Pixel 9 Pro XL"
"SMART Technologies","AM60 series","komodo","AM60 series"
"SMART Technologies","AMG1","komodo","AMG series"
"Samsung","Galaxy S23","dm1q","SM-S911B"
"Samsung","Galaxy S23","dm1q","SM-S911U"
"Samsung","Galaxy A54 5G","a54x","SM-A546E"
"Archos","Alba 7\\'\\'","ac70plv4","Alba 7"""
"AOpen","RK3288 10"" Chromebase","tiger_cheets","AOpen Chromebase Mini"
''';

void main() {
  final catalog = AndroidDeviceCatalog.parse(_csv);

  test('codename and model resolve to the marketing name', () {
    expect(
      catalog.lookup(brand: 'samsung', device: 'dm1q', model: 'SM-S911B'),
      'Galaxy S23',
    );
  });

  test('a listed model resolves without its codename', () {
    expect(catalog.lookup(model: 'sm-a546e'), 'Galaxy A54 5G');
  });

  test('a shared codename resolves only for a matching brand', () {
    expect(catalog.lookup(device: 'komodo', model: 'unknown'), isNull);
    expect(
      catalog.lookup(brand: 'Google', device: 'komodo', model: 'unknown'),
      'Pixel 9 Pro XL',
    );
    expect(
      catalog.lookup(brand: 'SMART Technologies', device: 'komodo'),
      isNull,
    );
  });

  test('rows without a marketing name are ignored', () {
    expect(
      catalog.lookup(device: 'AD681H', model: 'Smartfren Andromax AD681H'),
      isNull,
    );
  });

  test('quoted and backslash escapes are unescaped', () {
    expect(catalog.lookup(model: 'Alba 7"'), "Alba 7''");
    expect(
      catalog.lookup(model: 'AOpen Chromebase Mini'),
      'RK3288 10" Chromebase',
    );
  });

  test('decode reads UTF-16LE with a byte-order mark, and UTF-8', () {
    final units = '﻿$_csv'.codeUnits;
    final utf16le = [
      for (final u in units) ...[u & 0xFF, u >> 8],
    ];
    expect(AndroidDeviceCatalog.decode(utf16le), _csv);
    expect(AndroidDeviceCatalog.decode(utf8.encode(_csv)), _csv);
  });

  group('AndroidMarketingNames', _loaderTests);
}

void _loaderTests() {
  late HttpServer server;
  late Directory cacheDirectory;
  late int requests;
  late int failuresLeft;
  HttpOverrides? overrides;

  setUp(() async {
    // flutter_test stubs out HttpClient; these tests talk to a real (local)
    // server.
    overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    requests = 0;
    failuresLeft = 0;
    cacheDirectory = await Directory.systemTemp.createTemp('eagly_android_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      requests++;
      if (failuresLeft > 0) {
        failuresLeft--;
        request.response.statusCode = 503;
      } else {
        request.response.add(utf8.encode(_csv));
      }
      request.response.close();
    });
    AndroidMarketingNames.retryDelay = const Duration(milliseconds: 50);
  });

  tearDown(() async {
    HttpOverrides.global = overrides;
    AndroidMarketingNames.retryDelay = const Duration(minutes: 10);
    await server.close(force: true);
    await cacheDirectory.delete(recursive: true);
  });

  AndroidMarketingNames names() {
    final names = AndroidMarketingNames.forTesting(
      url: Uri.parse('http://127.0.0.1:${server.port}/devices.csv'),
      cacheDirectory: cacheDirectory,
    );
    addTearDown(names.dispose);
    return names;
  }

  Future<void> changed(AndroidMarketingNames names) {
    final done = Completer<void>();
    names.addListener(() {
      if (!done.isCompleted) done.complete();
    });
    return done.future.timeout(const Duration(seconds: 10));
  }

  test('a failed download retries on its own, then notifies', () async {
    failuresLeft = 2;
    final loader = names();
    final arrived = changed(loader);

    expect(await loader.lookup(model: 'SM-S911B'), isNull);
    await arrived;

    expect(requests, 3);
    expect(await loader.lookup(model: 'SM-S911B'), 'Galaxy S23');
  });

  test('the list is cached whole and read back on the next launch', () async {
    final first = names();
    final arrived = changed(first);
    await first.lookup(model: 'SM-S911B');
    await arrived;

    final files = cacheDirectory.listSync().map((f) => f.uri.pathSegments.last);
    expect(files, ['android_supported_devices.csv']);
    expect(
      File('${cacheDirectory.path}/android_supported_devices.csv')
          .readAsStringSync(),
      _csv,
    );

    // Reading the cached copy is never waited on: the first lookup answers
    // null, and listeners hear once it is in.
    final relaunched = names();
    final loaded = changed(relaunched);
    expect(await relaunched.lookup(model: 'SM-S911B'), isNull);
    await loaded;
    expect(await relaunched.lookup(model: 'SM-S911B'), 'Galaxy S23');
    expect(requests, 1);
  });
}
