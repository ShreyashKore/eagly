import 'dart:typed_data';

import 'package:eagly/services/tools/android_apk_icon_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApkIconExtractor', () {
    test('returns null for empty bytes rather than throwing', () {
      expect(ApkIconExtractor.extractIconBytes(Uint8List(0)), isNull);
    });

    test('returns null for bytes that are not a zip archive', () {
      final garbage = Uint8List.fromList(
        List<int>.generate(256, (i) => i % 256),
      );
      expect(ApkIconExtractor.extractIconBytes(garbage), isNull);
    });

    test('returns null for a well-formed but empty zip archive', () {
      // A minimal valid (empty) ZIP: just the End Of Central Directory record.
      final emptyZip = Uint8List.fromList([
        0x50, 0x4B, 0x05, 0x06, // EOCD signature
        0x00, 0x00, 0x00, 0x00, // disk numbers
        0x00, 0x00, 0x00, 0x00, // entry counts
        0x00, 0x00, 0x00, 0x00, // central directory size
        0x00, 0x00, 0x00, 0x00, // central directory offset
        0x00, 0x00, // comment length
      ]);
      expect(ApkIconExtractor.extractIconBytes(emptyZip), isNull);
    });
  });
}
