/// What a scrollback line is, which is all the view needs to style it.
enum TerminalLineKind {
  /// The echoed prompt line for a command the user submitted.
  command,

  /// A line the user sent to a running process' stdin.
  input,

  /// Process stdout.
  stdout,

  /// Process stderr.
  stderr,

  /// Output produced by the terminal itself — built-ins, exit codes,
  /// connectivity notices.
  notice,

  /// A terminal-level failure: unknown tool, unresolved device, bad quoting.
  error,
}

/// One line of terminal scrollback.
class TerminalLine {
  const TerminalLine(this.kind, this.text, {this.prompt, this.resolved});

  const TerminalLine.command(
    String text, {
    required String prompt,
    String? resolved,
  }) : this(TerminalLineKind.command, text, prompt: prompt, resolved: resolved);

  const TerminalLine.input(String text) : this(TerminalLineKind.input, text);

  const TerminalLine.notice(String text) : this(TerminalLineKind.notice, text);

  const TerminalLine.error(String text) : this(TerminalLineKind.error, text);

  final TerminalLineKind kind;
  final String text;

  /// Device label rendered before the `$` on a [TerminalLineKind.command] line.
  final String? prompt;

  /// The command line as actually executed (device selector included), shown
  /// as the prompt line's tooltip so the injected selector stays visible.
  final String? resolved;

  /// Text put on the clipboard when the whole scrollback is copied.
  String get copyText => switch (kind) {
    TerminalLineKind.command => '${prompt ?? ''} \$ $text'.trimLeft(),
    TerminalLineKind.input => '> $text',
    _ => text,
  };
}

/// One chunk of live process output, tagged by the pipe it arrived on.
class TerminalOutputChunk {
  const TerminalOutputChunk(this.text, {required this.isError});

  final String text;
  final bool isError;
}
