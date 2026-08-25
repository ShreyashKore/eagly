import 'terminal_tools.dart';

/// Commands the terminal answers itself instead of handing to a device tool.
enum TerminalBuiltin {
  help(['help', '?'], 'Show what this terminal understands'),
  clear(['clear', 'cls'], 'Clear the scrollback'),
  devices(['devices'], 'List every device Eagly can see'),
  use(['use'], 'Pin this tab to a device (`use auto` to unpin)'),
  tools(['tools'], 'List the CLIs this terminal dispatches to'),
  history(['history'], 'Show this tab\'s command history');

  const TerminalBuiltin(this.names, this.summary);

  /// The word(s) that invoke this built-in; the first is the canonical one.
  final List<String> names;
  final String summary;

  static TerminalBuiltin? lookup(String name) {
    for (final builtin in TerminalBuiltin.values) {
      if (builtin.names.contains(name)) return builtin;
    }
    return null;
  }
}

/// What one submitted line turned out to be.
///
/// [deviceRef] carries the optional `@device` prefix — the escape hatch for
/// aiming a single line at a device other than the tab's target — and is
/// resolved by the controller, which is the only thing that knows what devices
/// exist.
sealed class TerminalRequest {
  const TerminalRequest({this.deviceRef});

  /// The `@…` prefix the user typed, without the `@`.
  final String? deviceRef;
}

/// A terminal built-in ([TerminalBuiltin]) with its arguments.
final class TerminalBuiltinRequest extends TerminalRequest {
  const TerminalBuiltinRequest(
    this.builtin, {
    this.arguments = const [],
    super.deviceRef,
  });

  final TerminalBuiltin builtin;
  final List<String> arguments;
}

/// A known CLI invoked by name, with the arguments that follow it.
final class TerminalToolRequest extends TerminalRequest {
  const TerminalToolRequest(this.tool, this.arguments, {super.deviceRef});

  final TerminalTool tool;
  final List<String> arguments;
}

/// A line that named no known tool, so it is meant for the device's own shell.
/// [script] is the raw remainder — the device's `sh` evaluates it, so pipes,
/// `;` and `$(…)` all work.
final class TerminalShellRequest extends TerminalRequest {
  const TerminalShellRequest(this.script, {super.deviceRef});

  final String script;
}

/// The line could not be read at all (unbalanced quotes, a bare `@`).
final class TerminalInvalidRequest extends TerminalRequest {
  const TerminalInvalidRequest(this.message, {super.deviceRef});

  final String message;
}

/// Parses one submitted line. Never throws — a malformed line comes back as a
/// [TerminalInvalidRequest] carrying the message to print.
TerminalRequest parseTerminalInput(String input) {
  var rest = input.trim();
  String? deviceRef;

  if (rest.startsWith('@')) {
    final split = rest.indexOf(RegExp(r'\s'));
    if (split < 0) {
      return TerminalInvalidRequest(
        'Missing a command after "$rest". Write `$rest <command>`, or `use '
        '${rest.substring(1)}` to point this whole tab at that device.',
      );
    }
    deviceRef = rest.substring(1, split);
    rest = rest.substring(split).trim();
    if (deviceRef.isEmpty) {
      return const TerminalInvalidRequest(
        'Write the device after the @, e.g. `@pixel adb shell ls`.',
      );
    }
  }

  final List<String> tokens;
  try {
    tokens = tokenizeCommandLine(rest);
  } on FormatException catch (error) {
    return TerminalInvalidRequest(error.message, deviceRef: deviceRef);
  }
  if (tokens.isEmpty) {
    return TerminalInvalidRequest('Nothing to run.', deviceRef: deviceRef);
  }

  final builtin = TerminalBuiltin.lookup(tokens.first.toLowerCase());
  if (builtin != null) {
    return TerminalBuiltinRequest(
      builtin,
      arguments: tokens.sublist(1),
      deviceRef: deviceRef,
    );
  }

  final tool = lookupTerminalTool(tokens.first);
  if (tool != null) {
    return TerminalToolRequest(tool, tokens.sublist(1), deviceRef: deviceRef);
  }

  return TerminalShellRequest(rest, deviceRef: deviceRef);
}

/// Splits a command line into argv the way a POSIX shell would: whitespace
/// separates tokens, single quotes are literal, double quotes and backslashes
/// escape. The result is handed straight to `Process.start`, so no host shell
/// ever sees the line.
///
/// Throws a [FormatException] when a quote is left open.
List<String> tokenizeCommandLine(String input) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  var hasToken = false;
  var quote = '';

  for (var index = 0; index < input.length; index++) {
    final char = input[index];

    if (quote.isEmpty && (char == ' ' || char == '\t' || char == '\n')) {
      if (hasToken) {
        tokens.add(buffer.toString());
        buffer.clear();
        hasToken = false;
      }
      continue;
    }
    if (char == r'\' && quote != "'" && index + 1 < input.length) {
      buffer.write(input[++index]);
      hasToken = true;
      continue;
    }
    if (quote.isEmpty && (char == "'" || char == '"')) {
      quote = char;
      hasToken = true;
      continue;
    }
    if (char == quote) {
      quote = '';
      continue;
    }
    buffer.write(char);
    hasToken = true;
  }

  if (quote.isNotEmpty) {
    throw FormatException('Unbalanced $quote quote in the command.');
  }
  if (hasToken) tokens.add(buffer.toString());
  return tokens;
}
