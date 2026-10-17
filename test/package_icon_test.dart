import 'dart:typed_data';

import 'package:eagly/presentation/components/package_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_app_icon_cache.dart';

/// A 1×1 transparent PNG.
final Uint8List _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Holds icons "on disk" only: nothing is in memory until [load] reads it,
/// like the real cache at the start of a session.
class _ColdIconCache extends FakeAppIconCache {
  @override
  Uint8List? peek(String packageName) => null;
}

void main() {
  late FakeAppIconCache cache;

  setUp(() => cache = FakeAppIconCache());

  Future<void> pumpIcon(WidgetTester tester, String packageName) {
    return tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PackageIcon(
            packageName: packageName,
            size: 16,
            fallback: const Icon(Icons.apps_outlined),
            cache: cache,
          ),
        ),
      ),
    );
  }

  test('packageOf keeps package names and drops process suffixes', () {
    expect(PackageIcon.packageOf('com.example.app'), 'com.example.app');
    expect(
      PackageIcon.packageOf(' com.example.app:remote '),
      'com.example.app',
    );
    expect(PackageIcon.packageOf('system_server'), isNull);
    expect(PackageIcon.packageOf('/system/bin/surfaceflinger'), isNull);
    expect(PackageIcon.packageOf('[kworker/0:1]'), isNull);
    expect(PackageIcon.packageOf('1234'), isNull);
    expect(PackageIcon.packageOf(''), isNull);
  });

  testWidgets('paints an icon already in memory in its first frame', (
    tester,
  ) async {
    cache.seed('com.example.app', _png);

    await pumpIcon(tester, 'com.example.app:remote');

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.apps_outlined), findsNothing);
  });

  testWidgets('shows the fallback until a cold icon is read', (tester) async {
    cache = _ColdIconCache()..seed('com.example.app', _png);

    await pumpIcon(tester, 'com.example.app');
    expect(find.byIcon(Icons.apps_outlined), findsOneWidget);

    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(cache.loadedPackages, ['com.example.app']);
  });

  testWidgets('never looks up a value that cannot be a package', (
    tester,
  ) async {
    await pumpIcon(tester, 'system_server');
    await tester.pump();

    expect(find.byIcon(Icons.apps_outlined), findsOneWidget);
    expect(cache.loadedPackages, isEmpty);
  });

  testWidgets('follows a reused row on to another package', (tester) async {
    cache.seed('com.example.a', _png);

    await pumpIcon(tester, 'com.example.a');
    expect(find.byType(Image), findsOneWidget);

    await pumpIcon(tester, 'com.example.b');
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.apps_outlined), findsOneWidget);
  });
}
