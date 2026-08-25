import 'terminal_line.dart';

/// A live terminal process: its merged output, its eventual exit code, and the
/// two things a terminal needs to drive it — a way to feed stdin and a way to
/// stop it.
///
/// Unlike a utility run, a terminal command has no timeout: `adb logcat` and
/// `idevicesyslog` legitimately stream until the user stops them, so ending the
/// process is the caller's job ([kill]).
class TerminalProcessSession {
  TerminalProcessSession({
    required this.output,
    required this.exitCode,
    required Future<void> Function() onKill,
    required void Function(String text) onInput,
  }) : _onKill = onKill,
       _onInput = onInput;

  /// stdout and stderr, line by line, tagged by pipe. Closes when both pipes
  /// are done.
  final Stream<TerminalOutputChunk> output;

  final Future<int> exitCode;

  final Future<void> Function() _onKill;
  final void Function(String text) _onInput;

  /// Terminates the process (SIGTERM, escalating to SIGKILL).
  Future<void> kill() => _onKill();

  /// Writes [text] plus a newline to the process' stdin. A no-op once the
  /// process has exited.
  void sendLine(String text) => _onInput(text);
}
