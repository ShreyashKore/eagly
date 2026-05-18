import 'package:flutter_test/flutter_test.dart';
import 'package:eagly/data/log_level.dart';

void main() {
  group('LogLevel', () {
    test(
      'resolves Android and iOS raw values into shared canonical levels',
      () {
        expect(LogLevel.fromStored('E'), LogLevel.error);
        expect(LogLevel.fromStored('ERROR'), LogLevel.error);
        expect(LogLevel.fromStored('F'), LogLevel.fault);
        expect(LogLevel.fromStored('fatal'), LogLevel.fault);
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
        LogLevel.fault.normalizeSelectionForPlatform(isIos: false),
        LogLevel.fault,
      );
      expect(
        LogLevel.unknown.normalizeSelectionForPlatform(isIos: false),
        LogLevel.verbose,
      );
    });

    test('normalizes stored raw values for export/import compatibility', () {
      expect(LogLevel.normalizeAndroidStoredLevel('fatal'), 'F');
      expect(LogLevel.normalizeAndroidStoredLevel('ERROR'), 'E');
      expect(LogLevel.normalizeAndroidStoredLevel('verbose'), 'V');
      expect(LogLevel.normalizeIosStoredLevel('Notice'), 'default');
      expect(LogLevel.normalizeIosStoredLevel('panic'), 'panic');
    });

    test('uses Fatal as the Android-facing display label for F', () {
      expect(LogLevel.androidValues, contains(LogLevel.fault));
      expect(LogLevel.fault.displayLabel(isIos: false), 'Fatal');
      expect(LogLevel.fault.labelWithDisplayCode(isIos: false), 'Fatal (F)');
      expect(LogLevel.fault.displayLabel(isIos: true), 'Fault');
    });
  });
}
