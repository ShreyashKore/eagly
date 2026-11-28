import '../../../data/device.dart';
import '../../../utils/log_entry_utils.dart';
import '../data/models/log_entry.dart';
import 'filter_utils.dart';

/// Spots an Android app's process dying and coming back, from what
/// ActivityManager logs, and makes the divider that marks it:
/// "com.example.notes restarted · pid 4121 → 4188".
///
/// The signal is ActivityManager's `Start proc <pid>:<process>/<uid> for …`,
/// logged as system_server forks a process. A marker is made only for a
/// process whose earlier pid logged lines in this capture, so the system's
/// own process churn — services and providers starting all the time — never
/// shows. It goes right before the new pid's first line, so it reads as the
/// seam between the two runs however much other processes log between the
/// `Start proc` line and that one.
///
/// A death (`Process <process> (pid <pid>) has died…`, or
/// `Killing <pid>:<process>/…` for a process ActivityManager killed itself) covers
/// two gaps: it ties a pid that logged before any line of it was resolved to
/// its process, and when no `Start proc` line was understood, a line of the
/// same process from another pid after the old one died still gets its
/// marker, placed at the first line known to be that process's.
///
/// iOS has no counterpart: the syslog relay carries no reliable
/// process-launch line, and lines name the executable, not a pid's
/// lifetime, so iOS lines are never looked at.
class AppRestartDetector({
  /// The process Eagly knows [pid] by, for lines that arrived without one.
  final PackageForPid? packageForPid,
}) {
  /// Pids announced by a `Start proc` line that have not logged yet, and the
  /// process each belongs to.
  final Map<String, String> _awaitingFirstLine = {};

  /// The process each pid was started (or died) as, per ActivityManager.
  final Map<String, String> _processOfPid = {};

  /// The pid that last logged a line for each process.
  final Map<String, String> _lastLoggedPid = {};

  /// Pids that have logged at least one line in this capture.
  final Set<String> _loggedPids = {};

  /// Pids ActivityManager reported dead.
  final Set<String> _deadPids = {};

  /// The most pids each map holds before it is cleared. A pid space wraps
  /// after a few tens of thousands; forgetting costs at most a missed marker.
  static const int _maxTrackedPids = 8192;

  /// Takes in [entry], the next line of the capture, and returns the marker
  /// that goes right before it, if this is the first line of a restarted
  /// process.
  LogEntry? observe(LogEntry entry) {
    if (!_isAndroidLine(entry)) return null;
    final signalMarker = _readSignal(entry, logged: true);
    final pid = entry.pid.trim();
    if (pid.isEmpty) return signalMarker;

    LogEntry? marker;
    final started = _awaitingFirstLine.remove(pid);
    if (started != null) {
      marker = _restarted(started, pid, entry);
    } else {
      final process = _processOf(entry);
      final previous = process == null ? null : _lastLoggedPid[process];
      // No `Start proc` line was understood for this pid, but the process's
      // last pid has died: this is its next run.
      if (previous != null && previous != pid && _deadPids.contains(previous)) {
        marker = _restarted(process!, pid, entry);
      }
    }

    _addPid(_loggedPids, pid);
    // A dead process's last lines can come in after the new one's first;
    // they don't make it the process's latest pid again.
    final process = started ?? _processOf(entry);
    if (process != null && !_deadPids.contains(pid)) {
      _lastLoggedPid[process] = pid;
    }
    return marker ?? signalMarker;
  }

  /// Takes in a line that isn't kept — the capture is paused — for its
  /// ActivityManager signals alone, so a restart while paused is still
  /// marked at the new process's first line after the resume.
  void observeSignalsOnly(LogEntry entry) {
    if (_isAndroidLine(entry)) _readSignal(entry, logged: false);
  }

  /// [entries] with their markers in place, for an imported log.
  List<LogEntry> annotate(Iterable<LogEntry> entries) {
    final result = <LogEntry>[];
    for (final entry in entries) {
      final marker = observe(entry);
      if (marker != null) result.add(marker);
      result.add(entry);
    }
    return result;
  }

  /// Forgets everything, for a fresh capture.
  void reset() {
    _awaitingFirstLine.clear();
    _processOfPid.clear();
    _lastLoggedPid.clear();
    _loggedPids.clear();
    _deadPids.clear();
  }

  // ── Signals ──

  /// Android ≥ 8: `Start proc 4188:com.example.notes/u0a190 for top-activity
  /// {…}`. The process may carry a `:suffix` of its own.
  static final RegExp _startProc = RegExp(r'^Start proc (\d+):([^\s/]+)/\S+');

  /// Older releases: `Start proc com.example.notes for activity …: pid=4188
  /// uid=10190 …`.
  static final RegExp _legacyStartProc = RegExp(
    r'^Start proc ([^\s:]+(?::\S+)?) for .*?\bpid=(\d+)',
  );

  /// `Process com.example.notes (pid 4121) has died: fg  TOP`.
  static final RegExp _died = RegExp(r'^Process (\S+) \(pid (\d+)\) has died');

  /// `Killing 4121:com.example.notes/u0a190 (adj 0): stop com.example.notes`.
  static final RegExp _killed = RegExp(r'^Killing (\d+):([^\s/]+)/\S+');

  /// Reads a `Start proc` or a death from [entry]. Returns a marker only for
  /// a start whose pid has already logged ([logged]: a line of it came in
  /// ahead of the `Start proc` line), which then goes before this line.
  LogEntry? _readSignal(LogEntry entry, {required bool logged}) {
    if (entry.tag.trim() != 'ActivityManager') return null;
    final message = entry.message.trim();
    if (message.startsWith('Start proc ')) {
      final match = _startProc.firstMatch(message);
      final legacy = match == null
          ? _legacyStartProc.firstMatch(message)
          : null;
      final pid = match?.group(1) ?? legacy?.group(2);
      final process = match?.group(2) ?? legacy?.group(1);
      if (pid == null || process == null) return null;
      _putPid(_processOfPid, pid, process);
      _deadPids.remove(pid);
      // A repeated `Start proc` for the same pid changes nothing.
      if (_lastLoggedPid[process] == pid) return null;
      if (logged && _loggedPids.contains(pid)) {
        return _restarted(process, pid, entry);
      }
      _putPid(_awaitingFirstLine, pid, process);
      return null;
    }
    final death = _died.firstMatch(message);
    final killed = death == null ? _killed.firstMatch(message) : null;
    final pid = death?.group(2) ?? killed?.group(1);
    final process = death?.group(1) ?? killed?.group(2);
    if (pid == null || process == null) return null;
    _addPid(_deadPids, pid);
    _awaitingFirstLine.remove(pid);
    // Its lines may have come in before Eagly knew the pid's process.
    if (_loggedPids.contains(pid)) {
      _lastLoggedPid.putIfAbsent(process, () => pid);
    }
    return null;
  }

  // ── Helpers ──

  static bool _isAndroidLine(LogEntry entry) =>
      entry.isActualLog && entry.platform == DevicePlatform.android;

  /// The process [entry]'s pid belongs to: what ActivityManager said it
  /// started, else the package Eagly resolved for the line or the pid.
  String? _processOf(LogEntry entry) {
    final pid = entry.pid.trim();
    final known = _processOfPid[pid];
    if (known != null) return known;
    var process = packageFilterValue(entry);
    if (process.isEmpty || process == pid) {
      process = packageForPid?.call(pid)?.trim() ?? '';
    }
    return process.isEmpty || process == pid ? null : process;
  }

  /// The marker for [process] coming back as [pid], placed before [next];
  /// null when no earlier pid of it logged.
  LogEntry? _restarted(String process, String pid, LogEntry next) {
    final previous = _lastLoggedPid[process];
    _lastLoggedPid[process] = pid;
    if (previous == null || previous == pid) return null;
    return LogEntryUtils.buildSpecial(
      type: LogEntryType.restarted,
      message: restartMessage(process, previous, pid),
      timestamp: next.timestamp,
      tag: 'ActivityManager',
      pid: pid,
      packageName: process,
      processName: process,
    );
  }

  /// "com.example.notes restarted · pid 4121 → 4188".
  static String restartMessage(String process, String from, String to) =>
      '$process restarted · pid $from → $to';

  static void _addPid(Set<String> pids, String pid) {
    if (pids.length >= _maxTrackedPids) pids.clear();
    pids.add(pid);
  }

  static void _putPid(Map<String, String> map, String pid, String process) {
    if (map.length >= _maxTrackedPids && !map.containsKey(pid)) map.clear();
    map[pid] = process;
  }
}
