import 'dart:async';

import '../../../logs/data/models/log_entry.dart';

/// The line an Inspektor server listening on a loopback port writes to the
/// device log, with the token a client must present (§4.3). The server writes
/// it when it starts and again for every connection it accepts.
final RegExp _tokenLine = RegExp(
  r'Inspektor: remote inspection listening on 127\.0\.0\.1:(\d+), '
  r'token ([0-9a-f]{32})',
);

/// The port and token in an Inspektor log line, or null when [message] isn't
/// one.
({int port, String token})? parseInspektorTokenLine(String message) {
  final match = _tokenLine.firstMatch(message);
  if (match == null) return null;
  return (port: int.parse(match.group(1)!), token: match.group(2)!);
}

/// Follows a device's log for the token of the Inspektor server on [port].
///
/// iOS relays only live log lines, so this must start before the client
/// connects: the server repeats its token line when it accepts the
/// connection, and that is the line this catches. [started] completes on the
/// first log entry, once lines are known to be flowing.
///
/// [close] cancels [log], which stops the device-side relay.
class InspektorTokenListener(Stream<LogEntry> log, {required final int port}) {
  this {
    _subscription = log.listen(
      _handle,
      onError: (_) {},
      onDone: () => _logEnded = true,
    );
  }

  late final StreamSubscription<LogEntry> _subscription;
  final Completer<void> _started = Completer<void>();

  /// The latest token seen per pid, the latest from a line without one, and
  /// the latest of all.
  final Map<String, String> _byPid = {};
  String? _unattributed;
  String? _latest;
  final List<_Waiter> _waiters = [];
  bool _logEnded = false;

  /// Completes once the first log entry arrives.
  Future<void> get started => _started.future;

  /// The token of the process with [pid] (the app's `hello` names it), or of
  /// whichever process logged one for [port] when [pid] is unknown. Waits for
  /// the line when it hasn't arrived yet.
  Future<String> tokenFor(int? pid) {
    final known = _known(pid?.toString());
    if (known != null) return Future.value(known);
    if (_logEnded) {
      return Future.error(StateError('The device log ended.'));
    }
    final waiter = _Waiter(pid?.toString());
    _waiters.add(waiter);
    return waiter.completer.future;
  }

  Future<void> close() async {
    _logEnded = true;
    await _subscription.cancel();
    for (final waiter in _waiters) {
      waiter.completer.completeError(
        StateError('Stopped reading the device log.'),
      );
    }
    _waiters.clear();
  }

  String? _known(String? pid) =>
      pid == null ? _latest : _byPid[pid] ?? _unattributed;

  void _handle(LogEntry entry) {
    if (!_started.isCompleted) _started.complete();
    final line = parseInspektorTokenLine(entry.message);
    if (line == null || line.port != port) return;
    // Some log backends leave the pid out; such a line counts for any pid.
    final pid = int.tryParse(entry.pid)?.toString();
    if (pid != null) {
      _byPid[pid] = line.token;
    } else {
      _unattributed = line.token;
    }
    _latest = line.token;
    _waiters.removeWhere((waiter) {
      final token = pid == null || waiter.pid == null || waiter.pid == pid
          ? line.token
          : null;
      if (token == null) return false;
      waiter.completer.complete(token);
      return true;
    });
  }
}

class _Waiter(final String? pid) {
  final Completer<String> completer = Completer<String>();
}
