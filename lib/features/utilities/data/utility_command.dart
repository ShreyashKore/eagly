import 'package:flutter/material.dart';

import '../../../data/device.dart';

/// A bundled CLI a utility can run through, plus the flag that selects a
/// device on it (`adb -s <serial>` vs. `idevicefoo -u <udid>`). Adding a new
/// backing tool is a one-line change here — the runner is generic.
enum UtilityTool {
  adb('adb', '-s'),
  ideviceinfo('ideviceinfo', '-u'),
  idevicediagnostics('idevicediagnostics', '-u'),
  idevicename('idevicename', '-u'),
  idevicedate('idevicedate', '-u'),
  idevicepair('idevicepair', '-u'),
  idevicesetlocation('idevicesetlocation', '-u');

  const UtilityTool(this.executable, this.deviceFlag);

  final String executable;

  /// Flag that precedes the device identifier for this tool.
  final String deviceFlag;
}

/// One concrete tool invocation: the arguments that follow the device
/// selector, which the runner prepends.
class UtilityInvocation {
  const UtilityInvocation(this.tool, this.arguments);

  /// `adb -s <id> <arguments>`.
  const UtilityInvocation.adb(List<String> arguments)
    : this(UtilityTool.adb, arguments);

  /// `adb -s <id> shell <script>` — [script] is evaluated by the device's own
  /// `sh`, so it may contain pipes, `;` and `$(…)`. It never touches a host
  /// shell (arguments are passed to the process directly).
  UtilityInvocation.adbShell(String script)
    : this(UtilityTool.adb, ['shell', script]);

  final UtilityTool tool;
  final List<String> arguments;

  /// The command line as shown in the UI (without the device selector, which
  /// is noise for the reader).
  String get displayCommand => [tool.executable, ...arguments].join(' ');
}

enum UtilityParamKind { text, choice }

/// One user-supplied value a utility needs before it can run.
class UtilityParam {
  const UtilityParam({
    required this.key,
    required this.label,
    this.hint,
    this.kind = UtilityParamKind.text,
    this.options = const [],
    this.defaultValue = '',
    this.isRequired = true,
  });

  const UtilityParam.choice({
    required this.key,
    required this.label,
    required this.options,
    required this.defaultValue,
  }) : kind = UtilityParamKind.choice,
       hint = null,
       isRequired = true;

  final String key;
  final String label;
  final String? hint;
  final UtilityParamKind kind;
  final List<UtilityOption> options;
  final String defaultValue;
  final bool isRequired;
}

class UtilityOption {
  const UtilityOption(this.value, this.label);

  final String value;
  final String label;
}

/// The collected parameter values, read positionally by a command's builder.
/// Missing keys read as an empty string so a builder can be called with no
/// values at all to probe platform support (see [UtilityCommand.supports]).
class UtilityArgs {
  const UtilityArgs([this._values = const {}]);

  final Map<String, String> _values;

  String operator [](String key) => (_values[key] ?? '').trim();
}

/// A single runnable utility: a labelled, optionally parameterised wrapper
/// around one CLI invocation *per platform*.
///
/// [build] is the only platform-aware part — it returns `null` for a device
/// whose platform has no equivalent, which is how the UI decides what to show.
/// Everything else (grouping, search, params, confirmation, output) is
/// platform-agnostic, so adding an iOS counterpart to an Android command means
/// extending its builder, not touching the controller or the view.
class UtilityCommand {
  const UtilityCommand({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.build,
    this.params = const [],
    this.confirmation,
    this.expectsOutput = true,
    this.successMessage,
  });

  final String id;
  final String label;

  /// One-line explanation shown under [label].
  final String description;
  final IconData icon;

  /// Values collected from the user before [build] is called.
  final List<UtilityParam> params;

  /// Builds the invocation for [device], or `null` when unsupported there.
  final UtilityInvocation? Function(Device device, UtilityArgs args) build;

  /// Non-null for utilities that must be confirmed first — the string is the
  /// dialog body.
  final String? confirmation;

  /// False for utilities whose point is the side effect, not the output; the
  /// pane then reports [successMessage] instead of an empty output panel.
  final bool expectsOutput;
  final String? successMessage;

  bool get needsInput => params.isNotEmpty;

  bool supports(Device device) => build(device, const UtilityArgs()) != null;

  /// The command line with empty placeholders, for tooltips. Null when
  /// unsupported on [device].
  String? previewFor(Device device) =>
      build(device, const UtilityArgs())?.displayCommand;

  Map<String, String> get defaultValues => {
    for (final param in params) param.key: param.defaultValue,
  };
}

/// A titled section of the catalog.
class UtilityGroup {
  const UtilityGroup({
    required this.id,
    required this.title,
    required this.icon,
    required this.commands,
  });

  final String id;
  final String title;
  final IconData icon;
  final List<UtilityCommand> commands;

  UtilityGroup withCommands(List<UtilityCommand> commands) =>
      UtilityGroup(id: id, title: title, icon: icon, commands: commands);
}

/// The outcome of one run, rendered by the output panel.
class UtilityRunResult {
  const UtilityRunResult({
    required this.commandId,
    required this.label,
    required this.commandLine,
    required this.exitCode,
    required this.output,
    required this.finishedAt,
    this.failure,
  });

  final String commandId;
  final String label;
  final String commandLine;
  final int exitCode;
  final String output;
  final DateTime finishedAt;

  /// Set when the run never produced a process result (tool missing, spawn
  /// failure, …) rather than exiting non-zero.
  final String? failure;

  bool get isSuccess => failure == null && exitCode == 0;

  /// Text put on the clipboard by the panel's copy button.
  String get copyText {
    final body = output.trim().isEmpty ? '(no output)' : output.trim();
    return '\$ $commandLine\n$body';
  }
}

/// Single-quotes [value] for the *device* shell so spaces and metacharacters
/// in user input can't break out of the command being built.
String shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";
