import 'package:flutter_test/flutter_test.dart';
import 'package:logview/data/log_entry.dart';

void main() {
  group('LogEntry', () {
    test('parseFromLogcat assigns a unique incrementing internal ID', () {
      final first = LogEntry.parseFromLogcat(
        '04-26 20:54:02.025 1234 5678 I AuthTag: first message',
      );
      final second = LogEntry.parseFromLogcat(
        '04-26 20:54:02.026 1234 5678 I AuthTag: second message',
      );

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.id, isNonNegative);
      expect(second!.id, first.id + 1);
      expect(first.id, isNot(second.id));
    });

    test('does not export internal IDs and regenerates them on import', () {
      final entry = LogEntry(
        timestamp: '2026-04-26 20:54:02.025',
        pid: '1234',
        tid: '5678',
        level: 'I',
        tag: 'AuthTag',
        message: 'message body',
      );

      final exported = entry.toExportMap();
      final restored = LogEntry.fromExportedMap(exported);

      expect(exported.containsKey('id'), isFalse);
      expect(restored, isNotNull);
      expect(restored!.id, isNot(entry.id));
      expect(restored.message, entry.message);
      expect(restored.tag, entry.tag);
    });

    test('uses a provided ID unchanged', () {
      const customId = 42;
      final entry = LogEntry(
        id: customId,
        timestamp: '2026-04-26 20:54:02.025',
        pid: '1234',
        tid: '5678',
        level: 'I',
        tag: 'AuthTag',
        message: 'message body',
      );

      expect(entry.id, customId);
    });
  });
}
