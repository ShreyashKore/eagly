import 'package:eagly/presentation/theme/platform_look.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlatformLook.windowsBuild', () {
    test('reads the build from a Windows 11 version string', () {
      expect(
        PlatformLook.windowsBuild('"Windows 10 Pro" 10.0 (Build 22631)'),
        22631,
      );
    });

    test('reads the build from a Windows 10 version string', () {
      expect(
        PlatformLook.windowsBuild('"Windows 10 Home" 10.0 (Build 19045)'),
        19045,
      );
    });

    test('is null when the string has no build', () {
      expect(PlatformLook.windowsBuild('Version 15.1 (Build 24B83)'), null);
      expect(PlatformLook.windowsBuild(''), null);
    });
  });

  group('PlatformLook.supportsMica', () {
    test('only from the first Windows 11 build', () {
      expect(PlatformLook.supportsMica(19045), isFalse);
      expect(PlatformLook.supportsMica(21999), isFalse);
      expect(PlatformLook.supportsMica(22000), isTrue);
      expect(PlatformLook.supportsMica(26100), isTrue);
    });

    test('not when the build is unknown', () {
      expect(PlatformLook.supportsMica(null), isFalse);
    });
  });
}
