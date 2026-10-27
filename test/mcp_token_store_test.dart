import 'dart:io';

import 'package:eagly/features/mcp/mcp_token_store.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  late McpTokenStore store;

  File tokenFile() =>
      File('${dir.path}${Platform.pathSeparator}${McpTokenStore.fileName}');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
    dir = Directory.systemTemp.createTempSync('mcp-token');
    store = McpTokenStore(directory: () async => dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('makes a 256-bit hex token on first use and keeps it', () async {
    final token = await store.load();

    expect(token, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(tokenFile().readAsStringSync(), token);
    expect(await McpTokenStore(directory: () async => dir).load(), token);
  });

  test('regenerate replaces it', () async {
    final first = await store.load();
    final second = await store.regenerate();

    expect(second, isNot(first));
    expect(await McpTokenStore(directory: () async => dir).load(), second);
  });

  test('the file is readable by its owner only', () async {
    await store.load();
    expect(tokenFile().statSync().modeString(), 'rw-------');

    await store.regenerate();
    expect(tokenFile().statSync().modeString(), 'rw-------');
    // No temp file left behind.
    expect(dir.listSync(), hasLength(1));
  }, skip: Platform.isWindows);

  test('a file with wider permissions is tightened', () async {
    final token = await store.load();
    await Process.run('chmod', ['644', tokenFile().path]);

    expect(await store.load(), token);
    expect(tokenFile().statSync().modeString(), 'rw-------');
  }, skip: Platform.isWindows);

  test('a token kept in preferences moves into the file', () async {
    const legacy =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    SharedPreferences.setMockInitialValues({'mcpToken': legacy});
    await PreferencesService.init();

    expect(await store.load(), legacy);
    expect(tokenFile().readAsStringSync(), legacy);
    expect(PreferencesService.legacyMcpToken, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('mcpToken'), isFalse);
  });

  test('a damaged file is replaced with a new token', () async {
    tokenFile().writeAsStringSync('not a token');

    final token = await store.load();
    expect(token, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(tokenFile().readAsStringSync(), token);
  });
}
