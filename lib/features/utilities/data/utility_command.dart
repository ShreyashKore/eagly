import 'package:flutter/material.dart';

import '../../../data/device.dart';

/// A bundled CLI a utility can run through, plus the flag that selects a
/// device on it (`adb -s <serial>` vs. `idevicefoo -u <udid>`). Adding a new
/// backing tool is a one-line change here — the runner is generic.
enum UtilityTool(
  final String executable,

  /// Flag that precedes the device identifier for this tool.
  final String deviceFlag,
) {
  adb('adb', '-s'),
  ideviceinfo('ideviceinfo', '-u'),
  idevicediagnostics('idevicediagnostics', '-u'),
  idevicename('idevicename', '-u'),
  idevicedate('idevicedate', '-u'),
  idevicepair('idevicepair', '-u'),
  idevicesetlocation('idevicesetlocation', '-u'),
}

/// One concrete tool invocation: the arguments that follow the device
/// selector, which the runner prepends.
class const UtilityInvocation(
  final UtilityTool tool,
  final List<String> arguments,
) {
  /// `adb -s <id> <arguments>`.
  const UtilityInvocation.adb(List<String> arguments)
    : this(UtilityTool.adb, arguments);

  /// `adb -s <id> shell <script>` — [script] is evaluated by the device's own
  /// `sh`, so it may contain pipes, `;` and `$(…)`. It never touches a host
  /// shell (arguments are passed to the process directly).
  UtilityInvocation.adbShell(String script)
    : this(UtilityTool.adb, ['shell', script]);

  /// The command line as shown in the UI (without the device selector, which
  /// is noise for the reader).
  String get displayCommand => [tool.executable, ...arguments].join(' ');
}

/// How a parameter is edited. [choice] is a closed dropdown; [suggestion] is
/// a free-text field with a dropdown of common values attached, for inputs
/// whose useful values are well known but not exhaustive (permissions,
/// `dumpsys` services, screen sizes).
enum UtilityParamKind { text, choice, suggestion }

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
    this.helperText,
  });

  const UtilityParam.choice({
    required this.key,
    required this.label,
    required this.options,
    required this.defaultValue,
    this.helperText,
  }) : kind = UtilityParamKind.choice,
       hint = null,
       isRequired = true;

  /// A text field backed by a list of [options] the user can pick from or
  /// ignore — anything typed is passed through unchanged.
  const UtilityParam.suggestion({
    required this.key,
    required this.label,
    required this.options,
    this.hint,
    this.defaultValue = '',
    this.helperText,
  }) : kind = UtilityParamKind.suggestion,
       isRequired = true;

  final String key;
  final String label;
  final String? hint;
  final UtilityParamKind kind;
  final List<UtilityOption> options;
  final String defaultValue;
  final bool isRequired;

  /// Optional one-liner shown under the field in the parameters dialog.
  final String? helperText;
}

class const UtilityOption(
  final String value,
  final String label, {

  /// Optional second line shown under [label] in a suggestion dropdown.
  final String? description,
});

/// The collected parameter values, read positionally by a command's builder.
/// Missing keys read as an empty string so a builder can be called with no
/// values at all to probe platform support (see [UtilityCommand.supports]).
class const UtilityArgs([final Map<String, String> _values = const {}]) {
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
class const UtilityCommand({
  required final String id,
  required final String label,

  /// One-line explanation shown under [label].
  required final String description,
  required final IconData icon,

  /// Builds the invocation for [device], or `null` when unsupported there.
  required final UtilityInvocation? Function(Device device, UtilityArgs args)
  build,

  /// Values collected from the user before [build] is called.
  final List<UtilityParam> params = const [],

  /// Non-null for utilities that must be confirmed first — the string is the
  /// dialog body.
  final String? confirmation,

  /// False for utilities whose point is the side effect, not the output; the
  /// pane then reports [successMessage] instead of an empty output panel.
  final bool expectsOutput = true,
  final String? successMessage,

  /// The [UtilityParam.key] that takes a package name / bundle id, for
  /// commands aimed at one app. Non-null is what makes a command reachable
  /// from the Apps pane's right-click menu (pre-filled with that app), so
  /// the user never has to type a package name by hand.
  final String? packageParamKey,

  /// Whether this command may be aimed at a *system* app. Defaults to false:
  /// mutating a preinstalled package's permissions or state can leave the
  /// device unusable, so a command has to opt in — read-only ones do.
  /// Only meaningful together with [packageParamKey].
  final bool systemAppSafe = false,
}) {
  /// True for commands that target a single app, i.e. that the Apps pane can
  /// offer on an app's context menu.
  bool get targetsApp => packageParamKey != null;

  /// Whether this command may be run against [isSystemApp].
  bool allowsApp({required bool isSystemApp}) => !isSystemApp || systemAppSafe;

  /// True when clicking asks the user to confirm before anything runs.
  bool get isDestructive => confirmation != null;

  bool get needsInput => params.isNotEmpty;

  bool supports(Device device) => build(device, const UtilityArgs()) != null;

  /// The command line with empty placeholders, for tooltips. Null when
  /// unsupported on [device].
  String? previewFor(Device device) =>
      build(device, const UtilityArgs())?.displayCommand;

  /// The command line as it would run with [values] filled in — used by the
  /// parameters dialog to show exactly what the Run button will execute.
  String? previewWith(Device device, Map<String, String> values) =>
      build(device, UtilityArgs(values))?.displayCommand;

  Map<String, String> get defaultValues => {
    for (final param in params) param.key: param.defaultValue,
  };
}

/// A titled section of the catalog.
class const UtilityGroup({
  required final String id,
  required final String title,
  required final IconData icon,
  required final List<UtilityCommand> commands,
}) {
  UtilityGroup withCommands(List<UtilityCommand> commands) =>
      UtilityGroup(id: id, title: title, icon: icon, commands: commands);
}

/// The outcome of one run, rendered by the output panel.
class const UtilityRunResult({
  required final String commandId,
  required final String label,
  required final String commandLine,
  required final int exitCode,
  required final String output,
  required final DateTime finishedAt,

  /// Set when the run never produced a process result (tool missing, spawn
  /// failure, …) rather than exiting non-zero.
  final String? failure,
}) {
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
