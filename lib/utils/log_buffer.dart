import 'dart:collection';

typedef LogFilter<T> = bool Function(T log);

const int _batchOverflowPercent = 20;

class LogBuffer<T> {
  LogBuffer({required this.baseCapacity})
    : assert(baseCapacity > 0, 'baseCapacity must be positive'),
      expandedCapacity = baseCapacity * 2,
      _targetCapacity = baseCapacity;

  final int baseCapacity;
  final int expandedCapacity;
  final ListQueue<_BufferEntry<T>> _entries = ListQueue<_BufferEntry<T>>();

  LogFilter<T>? _activeFilter;

  /// Current target capacity:
  /// baseCapacity normally
  /// expandedCapacity when filter active
  int _targetCapacity;

  void setFilter(LogFilter<T>? filter) {
    _activeFilter = filter;

    for (final entry in _entries) {
      entry.matchesFilter = filter?.call(entry.value) ?? false;
    }

    if (filter == null) {
      _targetCapacity = baseCapacity;
    } else {
      _targetCapacity = expandedCapacity;
    }

    _evictOverflowBatch();
  }

  List<T> append(T log) {
    final matches = _activeFilter?.call(log) ?? false;

    _entries.addLast(_BufferEntry<T>(value: log, matchesFilter: matches));

    return _evictOverflowBatch();
  }

  List<T> getLogs() {
    return [for (final entry in _entries) entry.value];
  }

  List<T> search(bool Function(T log) predicate) {
    return [
      for (final entry in _entries)
        if (predicate(entry.value)) entry.value,
    ];
  }

  int get size => _entries.length;

  bool get isFilterActive => _activeFilter != null;

  int get capacity => _targetCapacity;

  int get maxBufferedSize => _targetCapacity + _overflowAllowance;

  List<T> trimToCapacity() {
    return _evictUntilSize(_targetCapacity);
  }

  void clear() {
    _entries.clear();
  }

  Map<String, dynamic> stats() {
    final matchingCount = _entries.where((entry) => entry.matchesFilter).length;
    return {
      'size': size,
      'baseCapacity': baseCapacity,
      'expandedCapacity': expandedCapacity,
      'targetCapacity': _targetCapacity,
      'maxBufferedSize': maxBufferedSize,
      'overflowPercent': _batchOverflowPercent,
      'filterActive': isFilterActive,
      'matchingCount': matchingCount,
      'nonMatchingCount': size - matchingCount,
      'shrinkDebt': 0,
    };
  }

  int get _overflowAllowance {
    final allowance = (_targetCapacity * _batchOverflowPercent) ~/ 100;
    return allowance > 0 ? allowance : 1;
  }

  List<T> _evictOverflowBatch() {
    if (size <= maxBufferedSize) {
      return const [];
    }

    return _evictUntilSize(_targetCapacity);
  }

  List<T> _evictUntilSize(int targetSize) {
    final evicted = <T>[];
    final removeCount = size - targetSize;
    for (var index = 0; index < removeCount; index++) {
      final removed = _evictOne(preferNonMatching: _activeFilter != null);
      if (removed == null) {
        break;
      }
      evicted.add(removed);
    }
    return evicted;
  }

  T? _evictOne({required bool preferNonMatching}) {
    if (_entries.isEmpty) return null;

    if (preferNonMatching) {
      for (final entry in _entries) {
        if (!entry.matchesFilter) {
          _entries.remove(entry);
          return entry.value;
        }
      }
    }

    return _entries.removeFirst().value;
  }
}

class _BufferEntry<T> {
  final T value;
  bool matchesFilter;

  _BufferEntry({required this.value, required this.matchesFilter});
}
