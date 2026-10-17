import '../../../data/device.dart';

/// A bundled CLI the terminal is allowed to dispatch to, plus everything the
/// dispatcher needs to aim it at a device without the user saying so:
///
/// * [deviceFlag] — the flag that selects a device (`adb -s`, `idevice* -u`).
///   `null` for tools that address no single device (`idevice_id`, `plistutil`).
/// * [selectorFlags] — every flag that already picks a device, so a line the
///   user *did* target explicitly is passed through untouched.
/// * [deviceLessSubcommands] — subcommands that talk to the host rather than a
///   device, where a selector would be noise (`adb devices`, `adb pair`, …).
///
/// Growing the table is the only thing needed to make another bundled binary
/// reachable from the terminal.
class TerminalTool {
  const TerminalTool(
    this.executable, {
    this.deviceFlag,
    this.selectorFlags = const {},
    this.deviceLessSubcommands = const {},
    this.platform,
    required this.summary,
  });

  /// An `adb`-style tool: global options (device selector included) precede a
  /// subcommand.
  const TerminalTool.adb()
    : this(
        'adb',
        deviceFlag: '-s',
        selectorFlags: const {'-s', '--serial', '-d', '-e', '-t'},
        deviceLessSubcommands: const {
          'devices',
          'connect',
          'disconnect',
          'pair',
          'start-server',
          'kill-server',
          'version',
          'keygen',
          'help',
        },
        platform: DevicePlatform.android,
        summary: 'Android Debug Bridge',
      );

  /// A libimobiledevice tool: `-u <udid>` selects the device.
  const TerminalTool.idevice(String executable, String summary)
    : this(
        executable,
        deviceFlag: '-u',
        selectorFlags: const {'-u', '--udid'},
        platform: DevicePlatform.ios,
        summary: summary,
      );

  final String executable;

  /// Flag that precedes the device identifier, or `null` when this tool takes
  /// no device selector.
  final String? deviceFlag;

  /// Flags that already pick a device; seeing one suppresses injection.
  final Set<String> selectorFlags;

  /// Subcommands that never take a device selector.
  final Set<String> deviceLessSubcommands;

  /// The platform this tool can drive, or `null` when it is platform-agnostic.
  final DevicePlatform? platform;

  /// One-line description, shown by the `tools` built-in.
  final String summary;

  bool supports(Device device) =>
      platform == null || platform == device.platform;

  /// Builds the argv for [arguments] aimed at [device]: the caller's arguments
  /// with the device selector prepended, unless the line already selects a
  /// device, the subcommand is host-side, or this tool takes no selector.
  List<String> argumentsFor(Device device, List<String> arguments) {
    final flag = deviceFlag;
    if (flag == null) return arguments;
    if (_alreadySelectsDevice(arguments)) return arguments;
    if (_isDeviceLessSubcommand(arguments)) return arguments;
    return [flag, device.id, ...arguments];
  }

  bool _alreadySelectsDevice(List<String> arguments) {
    // Only the leading option run can carry a selector; scanning stops at the
    // subcommand so a serial or a path that happens to look like a flag later
    // on is never mistaken for one.
    var index = 0;
    while (index < arguments.length) {
      final argument = arguments[index];
      if (!argument.startsWith('-')) return false;
      if (selectorFlags.contains(argument)) return true;
      // `adb -H/-P/-L` take a value; every other global flag stands alone.
      index += const {'-H', '-P', '-L'}.contains(argument) ? 2 : 1;
    }
    return false;
  }

  bool _isDeviceLessSubcommand(List<String> arguments) {
    if (deviceLessSubcommands.isEmpty) return false;
    final subcommand = arguments.firstWhere(
      (argument) => !argument.startsWith('-'),
      orElse: () => '',
    );
    return deviceLessSubcommands.contains(subcommand);
  }
}

/// Every CLI the terminal will dispatch to, in the order the `tools` built-in
/// lists them. Anything not in here is treated as a device shell command.
const List<TerminalTool> terminalTools = [
  TerminalTool.adb(),

  // ── libimobiledevice ──────────────────────────────────────────────────────
  TerminalTool(
    'idevice_id',
    platform: DevicePlatform.ios,
    summary: 'List paired device UDIDs',
  ),
  TerminalTool.idevice('ideviceinfo', 'Read device properties'),
  TerminalTool.idevice('idevicename', 'Read or set the device name'),
  TerminalTool.idevice('idevicedate', 'Read or set the device clock'),
  TerminalTool.idevice('idevicediagnostics', 'Diagnostics, restart, shutdown'),
  TerminalTool.idevice('idevicesyslog', 'Stream the system log'),
  TerminalTool.idevice('ideviceinstaller', 'Install, list and remove apps'),
  TerminalTool.idevice('idevicescreenshot', 'Capture a screenshot'),
  TerminalTool.idevice('idevicecrashreport', 'Pull crash reports'),
  TerminalTool.idevice('idevicepair', 'Pair, validate and unpair'),
  TerminalTool.idevice('idevicesetlocation', 'Simulate a GPS location'),
  TerminalTool.idevice('idevicebackup2', 'Back up and restore'),
  TerminalTool.idevice('ideviceimagemounter', 'Mount developer disk images'),
  TerminalTool.idevice('idevicedebug', 'Launch an app under the debugger'),
  TerminalTool.idevice('idevicedebugserverproxy', 'Proxy the debug server'),
  TerminalTool.idevice(
    'idevicenotificationproxy',
    'Post/observe notifications',
  ),
  TerminalTool.idevice('ideviceprovision', 'Manage provisioning profiles'),
  TerminalTool.idevice('ideviceenterrecovery', 'Put the device in recovery'),
  TerminalTool('plistutil', summary: 'Convert between plist formats'),
];

final Map<String, TerminalTool> _toolsByName = {
  for (final tool in terminalTools) tool.executable: tool,
};

/// The tool [name] refers to, or `null` when the terminal doesn't know it.
TerminalTool? lookupTerminalTool(String name) => _toolsByName[name];

/// One process the terminal is about to start: the resolved executable and the
/// complete argv, device selector included.
class TerminalInvocation {
  const TerminalInvocation({required this.executable, required this.arguments});

  final String executable;
  final List<String> arguments;

  /// The command line as actually run, for the prompt line's tooltip.
  String get displayCommand => [executable, ...arguments].join(' ');
}
