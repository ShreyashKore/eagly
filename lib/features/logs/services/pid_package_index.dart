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
class PidPackageIndex({
  /// Consulted for a PID no entry ever resolved — in practice the session
  /// repository's own polled `ps -A` map. It covers the process that logged
  /// only in the window before the first poll saw it and then went quiet: the
  /// device knows the PID, but no entry in this buffer ever carried its
  /// package. An in-memory lookup, not a fresh adb call.
  final PackageForPid? _fallback,
}) {
  final Map<String, String> _packageByPid = {};

  /// The package/process last seen for [pid], or null when neither the entries
  /// nor the fallback ever resolved it.
  String? packageForPid(String pid) =>
      _packageByPid[pid] ?? _fallback?.call(pid);

  /// Learns [log]'s pid→package mapping, if it has one, and returns the package
  /// when that mapping is *new* (so the caller can tell whether anything the
  /// active filter cares about changed). Call before the entry is filtered, so
  /// the filter can already use what this entry taught us.
  String? record(LogEntry log) => learn(log.pid, packageFilterValue(log));

  /// Learns that [pid] belongs to [package] — from a log entry, or straight
  /// from the device's refreshed map — returning [package] when that's new.
  String? learn(String pid, String package) {
    pid = pid.trim();
    package = package.trim();
    if (pid.isEmpty || package.isEmpty || package == pid) return null;
    if (_packageByPid[pid] == package) return null;

    _packageByPid[pid] = package;
    return package;
  }

  void clear() => _packageByPid.clear();
}
