import 'package:eagly/utils/log_timestamp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogTimestampParts', () {
    String joined(LogTimestampParts p) =>
        '${p.datePrefix}${p.time}${p.fraction}${p.suffix}';

    test('splits an Android logcat timestamp', () {
      final parts = LogTimestampParts.tryParse('10-18 01:49:18.312')!;
      expect(parts.datePrefix, '10-18 ');
      expect(parts.time, '01:49:18');
      expect(parts.fraction, '.312');
      expect(parts.year, isNull);
      expect(parts.dateLabel(currentYear: 2026), 'Oct 18');
    });

    test('splits an iOS / imported timestamp, with its year', () {
      final parts = LogTimestampParts.tryParse('2025-01-02 23:04:05.006')!;
      expect(parts.datePrefix, '2025-01-02 ');
      expect(parts.time, '23:04:05');
      expect(parts.fraction, '.006');
      expect(parts.dateLabel(currentYear: 2025), 'Jan 2');
      expect(parts.dateLabel(currentYear: 2026), 'Jan 2, 2025');
    });

    test('takes ISO separators, zones and a bare time of day', () {
      expect(
        joined(LogTimestampParts.tryParse('2026-03-04T05:06:07,890Z')!),
        '2026-03-04T05:06:07,890Z',
      );
      final bare = LogTimestampParts.tryParse('05:06:07')!;
      expect(bare.datePrefix, '');
      expect(bare.fraction, '');
      expect(bare.hasDate, isFalse);
      expect(bare.dateLabel(), isNull);
    });

    test('the parts always join back into the original', () {
      for (final raw in [
        '10-18 01:49:18.312',
        '2026-10-18 01:49:18.312',
        '2026-10-18 01:49:18',
        '2026-10-18T01:49:18.312+05:30',
      ]) {
        expect(joined(LogTimestampParts.tryParse(raw)!), raw);
      }
    });

    test('leaves anything else alone', () {
      for (final raw in [
        '',
        'yesterday',
        '13-40 01:49:18.312',
        '1700000000.123',
        '10-18 01:49',
        '10-18 01:49:18.312 extra',
      ]) {
        expect(LogTimestampParts.tryParse(raw), isNull, reason: raw);
      }
    });
  });
}
