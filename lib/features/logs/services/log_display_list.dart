import '../../../utils/log_entry_utils.dart';
import '../data/models/log_entry.dart';

/// A folded (or unfolded) run of identical consecutive lines, as the row that
/// heads it shows it.
class const LogRepeat({
  /// How many lines the run holds.
  required final int count,
  required final LogEntry first,
  required final LogEntry last,

  /// Whether the run is unfolded, one row per line, this row being its first.
  required final bool expanded,
}) {
  /// How long the run lasted, first line to last; null when either
  /// timestamp doesn't parse.
  Duration? get span {
    final start = first.parsedTimestamp;
    final end = last.parsedTimestamp;
    if (start == null || end == null) return null;
    final span = end.difference(start);
    return span.isNegative ? null : span;
  }
}

/// The log list as it is drawn: [LogController.filteredLogs] with runs of
/// identical consecutive lines folded into one row, like a browser console.
///
/// Everything the list does by index — selection, the current search match,
/// the overview ruler, scrolling to a row — works in *row* indices, while
/// copy, export, search and filters work on the entries. This is the one
/// place the two meet: a row covers the range [startOf]`..+`[lengthOf] of the
/// filtered entries, and [rowOf] maps an entry back to its row.
///
/// Runs are built incrementally. Lines only ever append to the filtered list
/// between rebuilds, and an appended line can only grow the last run or start
/// a new one, so [sync] costs the new lines alone. A filter, a search-hidden
/// column, an eviction or a clear replaces or reshapes the list; [sync] spots
/// that and rebuilds once.
class LogDisplayList({
  /// The fewest identical lines that fold.
  final int threshold = defaultThreshold,
}) {
  static const int defaultThreshold = 3;

  bool _collapse = true;

  /// The filtered entries the rows were built from, and how many of them.
  List<LogEntry> _source = const [];
  int _covered = 0;
  int? _lastCoveredId;
  bool _dirty = true;

  // Parallel per-row lists: where each row starts in [_source], the entry it
  // shows, and the run it heads (an index into the run lists) or -1.
  final List<int> _rowStarts = [];
  final List<LogEntry> _rowEntries = [];
  final List<int> _rowRun = [];

  // Runs of [threshold] or more, in order.
  final List<int> _runStarts = [];
  final List<int> _runLengths = [];

  /// Where the trailing streak of identical lines starts in [_source] — the
  /// only place an appended line can join.
  int _tailStart = 0;

  /// Unfolded runs, by the id of their first line, which outlives the index
  /// shifts of an eviction or a filter change.
  final Set<int> _expanded = {};

  /// Bumped whenever the rows change.
  int get revision => _revision;
  int _revision = 0;

  /// Whether runs fold at all. Off, there is one row per entry.
  bool get collapse => _collapse;
  set collapse(bool value) {
    if (_collapse == value) return;
    _collapse = value;
    _dirty = true;
    _revision++;
  }

  /// Brings the rows up to date with [filtered]: appends the lines added
  /// since the last call, or rebuilds when the list was replaced or changed
  /// other than at its end.
  void sync(List<LogEntry> filtered) {
    if (!_collapse) {
      if (!identical(filtered, _source) || filtered.length != _covered) {
        _source = filtered;
        _covered = filtered.length;
        _revision++;
      }
      return;
    }
    final appendedOnly =
        !_dirty &&
        identical(filtered, _source) &&
        filtered.length >= _covered &&
        (_covered == 0 || filtered[_covered - 1].id == _lastCoveredId);
    if (!appendedOnly) {
      _source = filtered;
      _rebuild();
      return;
    }
    if (filtered.length == _covered) return;
    for (var i = _covered; i < filtered.length; i++) {
      _add(i);
    }
    _cover(filtered.length);
  }

  /// Forces the next [sync] to rebuild.
  void invalidate() => _dirty = true;

  /// Forgets which runs were unfolded, for a cleared or restarted capture.
  void forgetExpanded() => _expanded.clear();

  int get length => _collapse ? _rowStarts.length : _covered;

  /// The entry each row shows: the first line of a run. With folding off,
  /// the filtered list itself.
  List<LogEntry> get entries => _collapse ? _rowEntries : _source;

  /// Index into the filtered entries of the first line [row] covers.
  int startOf(int row) => _collapse ? _rowStarts[row] : row;

  /// How many filtered entries [row] covers: a folded run's count, else 1.
  int lengthOf(int row) {
    if (!_collapse) return 1;
    final end = row + 1 < _rowStarts.length ? _rowStarts[row + 1] : _covered;
    return end - _rowStarts[row];
  }

  /// The row showing the filtered entry at [entryIndex] — for a line inside
  /// a folded run, the run's row.
  int rowOf(int entryIndex) {
    if (!_collapse) return entryIndex;
    var low = 0;
    var high = _rowStarts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_rowStarts[mid] <= entryIndex) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// The run [row] heads, folded or not; null for a single line or a line
  /// inside an unfolded run.
  LogRepeat? repeatAt(int row) {
    if (!_collapse || row < 0 || row >= _rowRun.length) return null;
    final run = _rowRun[row];
    if (run < 0) return null;
    final start = _runStarts[run];
    final count = _runLengths[run];
    final first = _source[start];
    return LogRepeat(
      count: count,
      first: first,
      last: _source[start + count - 1],
      expanded: _expanded.contains(first.id),
    );
  }

  /// Unfolds the run [row] heads, or folds it back. Returns false when [row]
  /// heads none.
  bool toggleRepeat(int row) {
    if (!_collapse || row < 0 || row >= _rowRun.length) return false;
    final run = _rowRun[row];
    if (run < 0) return false;
    final start = _runStarts[run];
    final count = _runLengths[run];
    final id = _source[start].id;
    if (_expanded.remove(id)) {
      _rowStarts.removeRange(row + 1, row + count);
      _rowEntries.removeRange(row + 1, row + count);
      _rowRun.removeRange(row + 1, row + count);
    } else {
      _expanded.add(id);
      _rowStarts.insertAll(row + 1, [
        for (var i = start + 1; i < start + count; i++) i,
      ]);
      _rowEntries.insertAll(row + 1, _source.sublist(start + 1, start + count));
      _rowRun.insertAll(row + 1, List.filled(count - 1, -1));
    }
    _revision++;
    return true;
  }

  // ── Building ──

  void _rebuild() {
    _rowStarts.clear();
    _rowEntries.clear();
    _rowRun.clear();
    _runStarts.clear();
    _runLengths.clear();
    _tailStart = 0;
    for (var i = 0; i < _source.length; i++) {
      _add(i);
    }
    _dirty = false;
    _cover(_source.length);
  }

  void _cover(int count) {
    _covered = count;
    _lastCoveredId = count == 0 ? null : _source[count - 1].id;
    _revision++;
  }

  /// Takes in the entry at [index], the next after the ones already built.
  void _add(int index) {
    final entry = _source[index];
    if (index == 0 || !isRepeatOf(_source[index - 1], entry)) {
      _tailStart = index;
      _pushRow(index, -1);
      return;
    }
    final length = index - _tailStart + 1;
    if (length < threshold) {
      _pushRow(index, -1);
      return;
    }
    final expanded = _expanded.contains(_source[_tailStart].id);
    if (length > threshold) {
      _runLengths[_runLengths.length - 1] = length;
      if (expanded) _pushRow(index, -1);
      return;
    }
    // The streak just reached the threshold: it becomes a run, and the rows
    // its first lines had as single lines fold into one.
    final run = _runStarts.length;
    _runStarts.add(_tailStart);
    _runLengths.add(length);
    final headRow = _rowStarts.length - (threshold - 1);
    if (expanded) {
      _rowRun[headRow] = run;
      _pushRow(index, -1);
      return;
    }
    _rowStarts.removeRange(headRow + 1, _rowStarts.length);
    _rowEntries.removeRange(headRow + 1, _rowEntries.length);
    _rowRun.removeRange(headRow + 1, _rowRun.length);
    _rowRun[headRow] = run;
  }

  void _pushRow(int start, int run) {
    _rowStarts.add(start);
    _rowEntries.add(_source[start]);
    _rowRun.add(run);
  }

  /// Whether [next] repeats [previous]: both device lines, from the same
  /// process, at the same level, under the same tag, saying the same thing.
  /// Timestamps and threads may differ. Session markers never join a run.
  static bool isRepeatOf(LogEntry previous, LogEntry next) =>
      previous.isActualLog &&
      next.isActualLog &&
      previous.message == next.message &&
      previous.tag == next.tag &&
      previous.pid == next.pid &&
      previous.level == next.level;
}
