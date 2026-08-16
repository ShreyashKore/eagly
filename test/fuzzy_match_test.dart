import 'package:eagly/command_palette/fuzzy_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fuzzyScore', () {
    test('empty query matches everything with a zero score', () {
      expect(fuzzyScore('', 'Reload Devices'), 0);
    });

    test('matches characters out of contiguity but in order', () {
      expect(fuzzyScore('rlddv', 'Reload Devices'), isNotNull);
    });

    test('is case-insensitive', () {
      expect(fuzzyScore('RELOAD', 'reload devices'), isNotNull);
    });

    test('fails when a character is out of order', () {
      // "d" then "e" then "R" is not a subsequence of "Reload".
      expect(fuzzyScore('der', 'Reload'), isNull);
    });

    test('fails when the query has a character the target lacks', () {
      expect(fuzzyScore('xyz', 'Reload Devices'), isNull);
    });

    test('scores a tighter/prefix match higher than a scattered one', () {
      final tight = fuzzyScore('reload', 'Reload Devices')!;
      final scattered = fuzzyScore('res', 'Reload Devices')!;
      expect(tight, greaterThan(scattered));
    });

    test('scores an exact prefix match higher than a mid-string match', () {
      final prefix = fuzzyScore('com', 'Command Palette')!;
      final middle = fuzzyScore('pal', 'Command Palette')!;
      expect(prefix, greaterThan(middle));
    });
  });
}
