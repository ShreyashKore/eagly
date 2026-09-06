import '../data/models/log_entry.dart';
import 'filter_utils.dart';

/// Remembers which package/process each PID belonged to, learned from the log
/// entries that *did* get a package resolved.
///
/// The pid→package map on the device side ([DeviceSessionRepository]) is polled
/// every few seconds, so entries emitted before the poll that first saw a
/// process — or after it exited — reach us with no package at all. Keeping the
/// mapping here lets a package filter still recognise those entries by their
/// PID instead of dropping them.
class PidPackageIndex {
  final Map<String, String> _packageByPid = {};

  /// The package/process last seen for [pid], or null when it was never
  /// resolved.
  String? packageForPid(String pid) => _packageByPid[pid];

  /// Learns [log]'s pid→package mapping, if it has one, and returns the package
  /// when that mapping is *new* (so the caller can tell whether anything the
  /// active filter cares about changed). Call before the entry is filtered, so
  /// the filter can already use what this entry taught us.
  String? record(LogEntry log) {
    final pid = log.pid.trim();
    if (pid.isEmpty) return null;

    final package = packageFilterValue(log);
    if (package.isEmpty || package == pid) return null;
    if (_packageByPid[pid] == package) return null;

    _packageByPid[pid] = package;
    return package;
  }

  void clear() => _packageByPid.clear();
}
