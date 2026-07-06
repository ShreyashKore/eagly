import 'dart:io';

import 'package:eagly/constants/app_constants.dart';
import 'package:eagly/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdateService.getBinaryUrl', () {
    test('points at the versioned GitHub release-download path', () async {
      final url = await AppUpdateService.getBinaryUrl('1.2.3');
      expect(
        url,
        startsWith('${AppConstants.repoUrl}/releases/download/v1.2.3/'),
      );
    });

    test('targets the current platform\'s stable-named artifact', () async {
      final url = await AppUpdateService.getBinaryUrl('1.2.3');
      // Names must match the stable artifacts uploaded by release.yml.
      final expectedAsset = Platform.isMacOS
          ? 'eagly-macos.dmg'
          : Platform.isWindows
          ? 'eagly-windows-setup.exe'
          : 'eagly-linux.deb';
      expect(url, endsWith('/$expectedAsset'));
    });
  });

  test('isSupported is true on the desktop platforms we ship', () {
    expect(
      AppUpdateService.isSupported,
      Platform.isMacOS || Platform.isWindows || Platform.isLinux,
    );
  });
}
