import 'package:flutter_test/flutter_test.dart';
import 'package:devspect/utils/log_buffer.dart';

void main() {
  test(
    'retains overflow until threshold and evicts matching entries in batches',
    () {
      final buffer = LogBuffer<String>(baseCapacity: 3);
      buffer.setFilter((log) => log.startsWith('keep'));

      for (final value in [
        'keep-1',
        'drop-1',
        'drop-2',
        'keep-2',
        'drop-3',
        'drop-4',
        'drop-5',
      ]) {
        expect(buffer.append(value), isEmpty);
      }

      expect(buffer.getLogs(), [
        'keep-1',
        'drop-1',
        'drop-2',
        'keep-2',
        'drop-3',
        'drop-4',
        'drop-5',
      ]);

      expect(buffer.append('drop-6'), ['drop-1', 'drop-2']);

      expect(buffer.getLogs(), [
        'keep-1',
        'keep-2',
        'drop-3',
        'drop-4',
        'drop-5',
        'drop-6',
      ]);
    },
  );

  test('reclassifies existing entries when the active filter changes', () {
    final buffer = LogBuffer<String>(baseCapacity: 2);
    buffer.setFilter((log) => log.startsWith('a'));

    for (final value in ['a1', 'b1', 'b2', 'a2']) {
      buffer.append(value);
    }

    buffer.setFilter((log) => log.startsWith('b'));
    expect(buffer.append('b3'), isEmpty);
    expect(buffer.getLogs(), ['a1', 'b1', 'b2', 'a2', 'b3']);

    expect(buffer.append('b4'), ['a1', 'a2']);
    expect(buffer.getLogs(), ['b1', 'b2', 'b3', 'b4']);
  });

  test(
    'shrinks buffered overflow in batches after removing an active filter',
    () {
      final buffer = LogBuffer<String>(baseCapacity: 2);
      buffer.setFilter((_) => true);

      for (final value in ['a', 'b', 'c', 'd']) {
        buffer.append(value);
      }

      buffer.setFilter(null);
      expect(buffer.getLogs(), ['c', 'd']);

      buffer.append('e');
      expect(buffer.getLogs(), ['c', 'd', 'e']);

      buffer.append('f');
      expect(buffer.getLogs(), ['e', 'f']);
    },
  );
}
