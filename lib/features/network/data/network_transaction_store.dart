import 'dart:collection';

import 'network_transaction.dart';

/// Identifies a transaction across sources: transaction ids are only unique
/// within the source that sent them.
typedef NetworkTransactionKey = ({String source, String id});

/// A transaction in the Network pane, with the source it came from.
class const NetworkEntry(
  final NetworkTransactionKey key,
  final NetworkTransaction transaction,
);

/// The Network pane's transactions, oldest first, capped at [capacity].
///
/// An update keeps a transaction where it first appeared, so a request that
/// completes does not jump to the bottom of the list. Past [capacity] the
/// oldest entries are dropped, like `LogBuffer` drops old lines.
class NetworkTransactionStore({final int capacity = 5000}) {
  this : assert(capacity > 0, 'capacity must be positive');

  final LinkedHashMap<NetworkTransactionKey, NetworkTransaction> _entries =
      LinkedHashMap();
  List<NetworkEntry>? _snapshot;

  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  /// Every entry, oldest first. The list is cached until the next change.
  List<NetworkEntry> get entries => _snapshot ??= List.unmodifiable([
    for (final MapEntry(:key, :value) in _entries.entries)
      NetworkEntry(key, value),
  ]);

  NetworkTransaction? operator [](NetworkTransactionKey key) => _entries[key];

  /// Adds [transaction] under [source], or replaces the one it updates.
  /// Returns the keys evicted to stay within [capacity].
  List<NetworkTransactionKey> upsert(
    String source,
    NetworkTransaction transaction,
  ) {
    _entries[(source: source, id: transaction.id)] = transaction;
    _snapshot = null;
    final evicted = <NetworkTransactionKey>[];
    while (_entries.length > capacity) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest);
      evicted.add(oldest);
    }
    return evicted;
  }

  /// Drops everything [source] sent. Returns the keys removed.
  List<NetworkTransactionKey> removeSource(String source) {
    final removed = [
      for (final key in _entries.keys)
        if (key.source == source) key,
    ];
    for (final key in removed) {
      _entries.remove(key);
    }
    if (removed.isNotEmpty) _snapshot = null;
    return removed;
  }

  void clear() {
    _entries.clear();
    _snapshot = null;
  }
}

/// Fetched bodies, kept under a byte budget. The least recently used body is
/// dropped first; a dropped body is simply fetched again when it is next shown.
class NetworkBodyCache({final int maxBytes = 64 * 1024 * 1024}) {
  final LinkedHashMap<(NetworkTransactionKey, NetworkBodyPart), NetworkBody>
  _bodies = LinkedHashMap();
  int _bytes = 0;

  /// The bytes currently held.
  int get bytes => _bytes;

  NetworkBody? get(NetworkTransactionKey key, NetworkBodyPart part) {
    final body = _bodies.remove((key, part));
    if (body != null) _bodies[(key, part)] = body;
    return body;
  }

  void put(NetworkTransactionKey key, NetworkBodyPart part, NetworkBody body) {
    final previous = _bodies.remove((key, part));
    if (previous != null) _bytes -= previous.bytes.length;
    // A body larger than the whole budget is shown but not kept.
    if (body.bytes.length > maxBytes) return;
    _bodies[(key, part)] = body;
    _bytes += body.bytes.length;
    while (_bytes > maxBytes) {
      final oldest = _bodies.keys.first;
      _bytes -= _bodies.remove(oldest)!.bytes.length;
    }
  }

  /// Drops every body of the transactions in [keys].
  void removeAll(Iterable<NetworkTransactionKey> keys) {
    final doomed = keys.toSet();
    if (doomed.isEmpty) return;
    _bodies.removeWhere((entry, body) {
      if (!doomed.contains(entry.$1)) return false;
      _bytes -= body.bytes.length;
      return true;
    });
  }

  void clear() {
    _bodies.clear();
    _bytes = 0;
  }
}
