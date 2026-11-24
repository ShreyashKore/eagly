import 'package:eagly/services/ios/rust_ios_runtime.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> opened;
  final library = ExternalLibrary.process(iKnowHowToUseIt: true);

  ExternalLibrary open(String name) {
    opened.add(name);
    return library;
  }

  setUp(() => opened = []);

  for (final (system, name) in [
    ('macos', 'rust_lib_eagly.framework/rust_lib_eagly'),
    ('linux', 'librust_lib_eagly.so'),
    ('windows', 'rust_lib_eagly.dll'),
  ]) {
    test('opens the bundled library on $system', () {
      final result = openBundledRustLibrary(
        environment: const {},
        operatingSystem: system,
        open: open,
      );
      expect(result, same(library));
      expect(opened, [name]);
    });
  }

  test('leaves the search to the bridge when nothing is bundled', () {
    final result = openBundledRustLibrary(
      environment: const {},
      operatingSystem: 'macos',
      open: (_) => throw ArgumentError('Failed to load dynamic library'),
    );
    expect(result, isNull);
  });

  test('yields to the bridge\'s directory override', () {
    final result = openBundledRustLibrary(
      environment: const {
        'FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR': '/somewhere/',
      },
      operatingSystem: 'macos',
      open: open,
    );
    expect(result, isNull);
    expect(opened, isEmpty);
  });
}
