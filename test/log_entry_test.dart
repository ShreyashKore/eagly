import 'package:flutter_test/flutter_test.dart';
import 'package:eagly/data/log_entry.dart';

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
      expect(restored.type, LogEntryType.log);
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

    test('special state factories create non-selectable entries', () {
      final paused = LogEntry.loggingState(
        type: LogEntryType.paused,
        message: 'Paused live logging for Pixel 8.',
        processName: 'Pixel 8',
      );

      expect(paused.isSpecialEntry, isTrue);
      expect(paused.isUserSelectable, isFalse);
      expect(paused.isCopyable, isFalse);
      expect(paused.typeLabel, 'Paused');
      expect(paused.level, 'I');
      expect(paused.message, 'Paused live logging for Pixel 8.');
      expect(paused.specialSearchableText, contains('Paused'));
    });

    test('parses fatal Android threadtime lines and trims padded tags', () {
      final entry = LogEntry.parseFromLogcat(
        '05-14 17:12:59.035  2002 12397 F DEBUG   : Softversion: PD2201IF_EX_A_14.2.14.2.W30.V000L1',
      );

      expect(entry, isNotNull);
      expect(entry!.type, LogEntryType.log);
      expect(entry.level, 'F');
      expect(entry.tag, 'DEBUG');
      expect(entry.message, 'Softversion: PD2201IF_EX_A_14.2.14.2.W30.V000L1');
    });

    test('parses logcat section separators into special notice entries', () {
      final entry = LogEntry.parseFromLogcat('--------- beginning of crash');

      expect(entry, isNotNull);
      expect(entry!.type, LogEntryType.notice);
      expect(entry.isSpecialEntry, isTrue);
      expect(entry.isUserSelectable, isFalse);
      expect(entry.tag, 'adb logcat');
      expect(entry.level, 'I');
      expect(entry.processName, 'crash');
      expect(entry.message, 'Beginning of crash');
    });

    test('exports and restores special entry types', () {
      final error = LogEntry.toolError(
        message: 'Failed to start adb logcat.',
        tag: 'adb logcat',
        processName: 'emulator-5554',
      );

      final restored = LogEntry.fromExportedMap(error.toExportMap());

      expect(restored, isNotNull);
      expect(restored!.type, LogEntryType.error);
      expect(restored.isSpecialEntry, isTrue);
      expect(restored.message, error.message);
      expect(restored.processName, error.processName);
    });
  });
}
