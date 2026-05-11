import 'package:flutter_test/flutter_test.dart';
import 'package:devspect/data/log_level.dart';

void main() {
  group('LogLevel', () {
    test(
      'resolves Android and iOS raw values into shared canonical levels',
      () {
        expect(LogLevel.fromStored('E'), LogLevel.error);
        expect(LogLevel.fromStored('ERROR'), LogLevel.error);
        expect(LogLevel.fromStored('W'), LogLevel.warning);
        expect(LogLevel.fromStored('notice'), LogLevel.defaultLevel);
        expect(LogLevel.fromStored('debug'), LogLevel.debug);
        expect(LogLevel.fromStored('critical'), LogLevel.fault);
      },
    );

    test('preserves unknown raw values as unknown shared levels', () {
      final level = LogLevel.fromStored('panic');

      expect(level.isUnknown, isTrue);
      expect(level.code, 'panic');
      expect(level.label, 'Unknown');
      expect(level.hierarchy, LogLevel.unknown.hierarchy);
    });

    test('normalizes unsupported selections to the closest platform level', () {
      expect(
        LogLevel.verbose.normalizeSelectionForPlatform(isIos: true),
        LogLevel.debug,
      );
      expect(
        LogLevel.defaultLevel.normalizeSelectionForPlatform(isIos: false),
        LogLevel.info,
      );
      expect(
        LogLevel.unknown.normalizeSelectionForPlatform(isIos: false),
        LogLevel.verbose,
      );
    });

    test('normalizes stored raw values for export/import compatibility', () {
      expect(LogLevel.normalizeAndroidStoredLevel('ERROR'), 'E');
      expect(LogLevel.normalizeAndroidStoredLevel('verbose'), 'V');
      expect(LogLevel.normalizeIosStoredLevel('Notice'), 'default');
      expect(LogLevel.normalizeIosStoredLevel('panic'), 'panic');
    });
  });
}
