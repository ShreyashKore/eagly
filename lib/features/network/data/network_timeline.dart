import 'network_transaction.dart';
import 'network_transaction_store.dart';

/// When an exchange started and, if it has, finished.
({DateTime start, DateTime? end})? spanOf(NetworkTransaction transaction) {
  final start = transaction.startedAt;
  if (start == null) return null;
  final elapsed = transaction.elapsed;
  return (
    start: start,
    end:
        transaction.finishedAt ?? (elapsed == null ? null : start.add(elapsed)),
  );
}

/// The stretch of time a set of exchanges covers: the first start to the last
/// finish (or start, for one still running). What the overview and the
/// waterfall column scale against.
class const NetworkTimeRange(final DateTime start, final DateTime end) {
  /// The range of [entries], or null when none of them has a start time.
  static NetworkTimeRange? of(Iterable<NetworkEntry> entries) {
    DateTime? first;
    DateTime? last;
    for (final entry in entries) {
      final span = spanOf(entry.transaction);
      if (span == null) continue;
      final end = span.end ?? span.start;
      if (first == null || span.start.isBefore(first)) first = span.start;
      if (last == null || end.isAfter(last)) last = end;
    }
    if (first == null || last == null) return null;
    return NetworkTimeRange(first, last);
  }

  Duration get duration => end.difference(start);

  /// This range with a little air at the end, and at least 100 ms long, so
  /// a single request draws as a bar rather than a sliver at the edge.
  NetworkTimeRange padded() {
    final micros = duration.inMicroseconds;
    final padded = (micros * 1.03).round();
    const minimum = 100 * 1000;
    return NetworkTimeRange(
      start,
      start.add(Duration(microseconds: padded < minimum ? minimum : padded)),
    );
  }

  /// Where [time] sits in the range, 0 at [start] and 1 at [end]. Not clamped.
  double fractionOf(DateTime time) {
    final total = duration.inMicroseconds;
    if (total <= 0) return 0;
    return time.difference(start).inMicroseconds / total;
  }

  /// The time [fraction] of the way through the range.
  DateTime timeAt(double fraction) => start.add(
    Duration(microseconds: (duration.inMicroseconds * fraction).round()),
  );

  @override
  bool operator ==(Object other) =>
      other is NetworkTimeRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
