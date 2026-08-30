import 'package:flutter/material.dart';

import '../../../data/device.dart';
import 'utility_command.dart';
import 'utility_suggestions.dart';

/// The Utilities catalog: curated `adb` / `adb shell` commands a developer
/// actually reaches for, with a libimobiledevice equivalent wherever one
/// exists (`idevicediagnostics`, `ideviceinfo`, `idevicename`, `idevicedate`,
/// `idevicepair`, `idevicesetlocation` — all already bundled).
///
/// Commands that have no counterpart on the other platform simply return
/// `null` from their builder and are hidden for that device; nothing else in
/// the feature is platform-aware.
final List<UtilityGroup> utilityCatalog = [
  _powerGroup,
  _infoGroup,
  _screenGroup,
  _appsGroup,
  _debugGroup,
];

// ── Builder helpers ───────────────────────────────────────────────────────

UtilityInvocation? _adb(Device device, List<String> arguments) =>
    device is AndroidDevice ? UtilityInvocation.adb(arguments) : null;

UtilityInvocation? _adbShell(Device device, String script) =>
    device is AndroidDevice ? UtilityInvocation.adbShell(script) : null;

UtilityInvocation? _idevice(
  Device device,
  UtilityTool tool,
  List<String> arguments,
) => device is IosDevice ? UtilityInvocation(tool, arguments) : null;

// ── Power & connection ────────────────────────────────────────────────────

final _powerGroup = UtilityGroup(
  id: 'power',
  title: 'Power & Connection',
  icon: Icons.power_settings_new,
  commands: [
    UtilityCommand(
      id: 'reboot',
      label: 'Reboot device',
      description: 'Restarts the device and reconnects it when it comes back.',
      icon: Icons.restart_alt,
      confirmation: 'The device will restart and briefly disconnect.',
      expectsOutput: false,
      successMessage: 'Reboot requested.',
      build: (device, args) =>
          _adb(device, ['reboot']) ??
          _idevice(device, UtilityTool.idevicediagnostics, ['restart']),
    ),
    UtilityCommand(
      id: 'power-off',
      label: 'Power off',
      description:
          'Shuts the device down. You will have to power it on by hand.',
      icon: Icons.power_off,
      confirmation:
          'The device will shut down — you will need to power it back on '
          'manually before it reappears here.',
      expectsOutput: false,
      successMessage: 'Shutdown requested.',
      build: (device, args) =>
          _adbShell(device, 'reboot -p') ??
          _idevice(device, UtilityTool.idevicediagnostics, ['shutdown']),
    ),
    UtilityCommand(
      id: 'sleep-screen',
      label: 'Sleep screen',
      description: 'Turns the display off without locking anything else.',
      icon: Icons.bedtime_outlined,
      expectsOutput: false,
      successMessage: 'Screen put to sleep.',
      build: (device, args) =>
          _adbShell(device, 'input keyevent 223') ??
          _idevice(device, UtilityTool.idevicediagnostics, ['sleep']),
    ),
    UtilityCommand(
      id: 'wake-screen',
      label: 'Wake screen',
      description: 'Turns the display back on.',
      icon: Icons.wb_sunny_outlined,
      expectsOutput: false,
      successMessage: 'Screen woken.',
      build: (device, args) => _adbShell(device, 'input keyevent 224'),
    ),
    UtilityCommand(
      id: 'reboot-recovery',
      label: 'Reboot to recovery',
      description: 'Restarts into the recovery partition.',
      icon: Icons.medical_services_outlined,
      confirmation:
          'The device will restart into recovery mode and leave the device '
          'list until you boot it back to Android.',
      expectsOutput: false,
      successMessage: 'Rebooting to recovery.',
      build: (device, args) => _adb(device, ['reboot', 'recovery']),
    ),
    UtilityCommand(
      id: 'reboot-bootloader',
      label: 'Reboot to bootloader',
      description: 'Restarts into fastboot / bootloader mode.',
      icon: Icons.developer_board,
      confirmation:
          'The device will restart into the bootloader and leave the device '
          'list until you boot it back to Android.',
      expectsOutput: false,
      successMessage: 'Rebooting to bootloader.',
      build: (device, args) => _adb(device, ['reboot', 'bootloader']),
    ),
    UtilityCommand(
      id: 'reconnect',
      label: 'Reconnect transport',
      description:
          'Bounces the adb connection — the usual fix for a wedged device.',
      icon: Icons.usb,
      build: (device, args) => _adb(device, ['reconnect']),
    ),
    UtilityCommand(
      id: 'pair-status',
      label: 'Check pairing',
      description: 'Validates that this Mac is still trusted by the device.',
      icon: Icons.verified_user_outlined,
      build: (device, args) =>
          _idevice(device, UtilityTool.idevicepair, ['validate']),
    ),
    UtilityCommand(
      id: 'unpair',
      label: 'Unpair device',
      description: 'Removes the trust relationship with this computer.',
      icon: Icons.link_off,
      confirmation:
          'The device will stop trusting this computer. You will have to tap '
          '"Trust" on the device again before logs or apps work.',
      build: (device, args) =>
          _idevice(device, UtilityTool.idevicepair, ['unpair']),
    ),
  ],
);

// ── Device info ───────────────────────────────────────────────────────────

final _infoGroup = UtilityGroup(
  id: 'info',
  title: 'Device Info',
  icon: Icons.info_outline,
  commands: [
    UtilityCommand(
      id: 'system-properties',
      label: 'System properties',
      description: 'Full property / device information dump.',
      icon: Icons.list_alt,
      build: (device, args) =>
          _adbShell(device, 'getprop') ??
          _idevice(device, UtilityTool.ideviceinfo, const []),
    ),
    UtilityCommand(
      id: 'battery',
      label: 'Battery status',
      description: 'Charge level, health, temperature and charging source.',
      icon: Icons.battery_full,
      build: (device, args) =>
          _adbShell(device, 'dumpsys battery') ??
          _idevice(device, UtilityTool.idevicediagnostics, [
            'diagnostics',
            'GasGauge',
          ]),
    ),
    UtilityCommand(
      id: 'storage',
      label: 'Storage usage',
      description: 'Free and used space per filesystem.',
      icon: Icons.storage,
      build: (device, args) =>
          _adbShell(device, 'df -h') ??
          _idevice(device, UtilityTool.ideviceinfo, [
            '-q',
            'com.apple.disk_usage',
          ]),
    ),
    UtilityCommand(
      id: 'device-name',
      label: 'Device name',
      description: 'The name the device shows to other devices.',
      icon: Icons.badge_outlined,
      build: (device, args) =>
          _adbShell(device, 'settings get global device_name') ??
          _idevice(device, UtilityTool.idevicename, const []),
    ),
    UtilityCommand(
      id: 'device-date',
      label: 'Date & time',
      description:
          'Current clock on the device — handy when tokens expire early.',
      icon: Icons.schedule,
      build: (device, args) =>
          _adbShell(device, 'date') ??
          _idevice(device, UtilityTool.idevicedate, const []),
    ),
    UtilityCommand(
      id: 'network',
      label: 'Network addresses',
      description: 'IP / Wi-Fi addresses assigned to the device.',
      icon: Icons.wifi,
      build: (device, args) =>
          _adbShell(device, 'ip -f inet addr') ??
          _idevice(device, UtilityTool.ideviceinfo, ['-k', 'WiFiAddress']),
    ),
    UtilityCommand(
      id: 'screen-metrics',
      label: 'Screen size & density',
      description: 'Physical and overridden resolution plus dpi.',
      icon: Icons.aspect_ratio,
      build: (device, args) => _adbShell(device, 'wm size; wm density'),
    ),
    UtilityCommand(
      id: 'processes',
      label: 'Running processes',
      description: 'Process list with pids, as `ps -A` reports it.',
      icon: Icons.memory,
      build: (device, args) => _adbShell(device, 'ps -A'),
    ),
  ],
);

// ── Screen & input ────────────────────────────────────────────────────────

const _keyEventOptions = [
  UtilityOption('3', 'Home'),
  UtilityOption('4', 'Back'),
  UtilityOption('187', 'Recent apps'),
  UtilityOption('82', 'Menu'),
  UtilityOption('66', 'Enter'),
  UtilityOption('67', 'Backspace'),
  UtilityOption('84', 'Search'),
  UtilityOption('26', 'Power'),
  UtilityOption('24', 'Volume up'),
  UtilityOption('25', 'Volume down'),
  UtilityOption('164', 'Mute'),
  UtilityOption('27', 'Camera'),
  UtilityOption('220', 'Brightness down'),
  UtilityOption('221', 'Brightness up'),
];

const _rotationOptions = [
  UtilityOption('0', 'Portrait'),
  UtilityOption('1', 'Landscape'),
  UtilityOption('2', 'Portrait (upside down)'),
  UtilityOption('3', 'Landscape (reversed)'),
  UtilityOption('auto', 'Auto-rotate'),
];

const _animationScaleOptions = [
  UtilityOption('0', 'Off (fastest)'),
  UtilityOption('0.5', '0.5×'),
  UtilityOption('1', '1× (default)'),
  UtilityOption('2', '2× (slow motion)'),
];

const _toggleOptions = [UtilityOption('1', 'On'), UtilityOption('0', 'Off')];

final _screenGroup = UtilityGroup(
  id: 'screen',
  title: 'Screen & Input',
  icon: Icons.touch_app_outlined,
  commands: [
    UtilityCommand(
      id: 'input-text',
      label: 'Type text',
      description: 'Types into whatever field currently has focus.',
      icon: Icons.keyboard_alt_outlined,
      expectsOutput: false,
      successMessage: 'Text sent to the device.',
      params: const [
        UtilityParam(key: 'text', label: 'Text', hint: 'test@example.com'),
      ],
      // `input text` treats spaces as argument separators, so they go over the
      // wire as %s.
      build: (device, args) => _adbShell(
        device,
        'input text ${shellQuote(args['text'].replaceAll(' ', '%s'))}',
      ),
    ),
    UtilityCommand(
      id: 'key-event',
      label: 'Send key',
      description: 'Presses a hardware or navigation key.',
      icon: Icons.smart_button,
      expectsOutput: false,
      successMessage: 'Key sent.',
      params: const [
        UtilityParam.choice(
          key: 'code',
          label: 'Key',
          options: _keyEventOptions,
          defaultValue: '3',
        ),
      ],
      build: (device, args) =>
          _adbShell(device, 'input keyevent ${args['code']}'),
    ),
    UtilityCommand(
      id: 'open-url',
      label: 'Open URL or deep link',
      description: 'Fires a VIEW intent — the fastest way to test deep links.',
      icon: Icons.link,
      params: const [
        UtilityParam(
          key: 'url',
          label: 'URL',
          hint: 'https://example.com or myapp://path',
        ),
      ],
      build: (device, args) => _adbShell(
        device,
        'am start -a android.intent.action.VIEW -d ${shellQuote(args['url'])}',
      ),
    ),
    UtilityCommand(
      id: 'rotation',
      label: 'Set rotation',
      description:
          'Forces an orientation, or hands control back to the sensor.',
      icon: Icons.screen_rotation,
      expectsOutput: false,
      successMessage: 'Rotation applied.',
      params: const [
        UtilityParam.choice(
          key: 'rotation',
          label: 'Orientation',
          options: _rotationOptions,
          defaultValue: '0',
        ),
      ],
      build: (device, args) {
        final rotation = args['rotation'];
        if (rotation == 'auto') {
          return _adbShell(
            device,
            'settings put system accelerometer_rotation 1',
          );
        }
        return _adbShell(
          device,
          'settings put system accelerometer_rotation 0; '
          'settings put system user_rotation $rotation',
        );
      },
    ),
    UtilityCommand(
      id: 'resolution',
      label: 'Override resolution',
      description: 'Emulates another screen size. Use "reset" to restore.',
      icon: Icons.fit_screen,
      params: const [
        UtilityParam.suggestion(
          key: 'size',
          label: 'Size',
          hint: '1080x1920 or reset',
          defaultValue: 'reset',
          options: screenResolutions,
        ),
      ],
      build: (device, args) =>
          _adbShell(device, 'wm size ${shellQuote(args['size'])}'),
    ),
    UtilityCommand(
      id: 'density',
      label: 'Override density',
      description: 'Emulates another dpi. Use "reset" to restore.',
      icon: Icons.grid_4x4,
      params: const [
        UtilityParam.suggestion(
          key: 'density',
          label: 'Density',
          hint: '420 or reset',
          defaultValue: 'reset',
          options: screenDensities,
        ),
      ],
      build: (device, args) =>
          _adbShell(device, 'wm density ${shellQuote(args['density'])}'),
    ),
    UtilityCommand(
      id: 'show-touches',
      label: 'Show taps',
      description: 'Draws a marker wherever the screen is touched.',
      icon: Icons.adjust,
      expectsOutput: false,
      successMessage: 'Tap indicator updated.',
      params: const [
        UtilityParam.choice(
          key: 'value',
          label: 'Show taps',
          options: _toggleOptions,
          defaultValue: '1',
        ),
      ],
      build: (device, args) => _adbShell(
        device,
        'settings put system show_touches ${args['value']}',
      ),
    ),
    UtilityCommand(
      id: 'animation-scale',
      label: 'Animation scale',
      description: 'Speeds up or slows down all system animations at once.',
      icon: Icons.speed,
      expectsOutput: false,
      successMessage: 'Animation scale updated.',
      params: const [
        UtilityParam.choice(
          key: 'scale',
          label: 'Scale',
          options: _animationScaleOptions,
          defaultValue: '0',
        ),
      ],
      build: (device, args) {
        final scale = args['scale'];
        return _adbShell(
          device,
          'settings put global window_animation_scale $scale; '
          'settings put global transition_animation_scale $scale; '
          'settings put global animator_duration_scale $scale',
        );
      },
    ),
  ],
);

// ── Apps & permissions ────────────────────────────────────────────────────

final _appsGroup = UtilityGroup(
  id: 'apps',
  title: 'Apps & Permissions',
  icon: Icons.security_outlined,
  commands: [
    UtilityCommand(
      id: 'foreground-activity',
      label: 'Foreground activity',
      description: 'Which package and activity is on screen right now.',
      icon: Icons.center_focus_strong_outlined,
      build: (device, args) => _adbShell(
        device,
        "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp'",
      ),
    ),
    UtilityCommand(
      id: 'grant-permission',
      label: 'Grant permission',
      description: 'Grants a runtime permission without touching Settings.',
      icon: Icons.lock_open,
      expectsOutput: false,
      successMessage: 'Permission granted.',
      packageParamKey: 'package',
      params: const [
        UtilityParam(
          key: 'package',
          label: 'Package',
          hint: 'com.example.app',
          helperText: 'Right-click an app in the Apps pane to fill this in.',
        ),
        UtilityParam.suggestion(
          key: 'permission',
          label: 'Permission',
          hint: 'android.permission.CAMERA',
          options: androidRuntimePermissions,
          helperText: 'Pick a common one, or type any permission name.',
        ),
      ],
      build: (device, args) => _adbShell(
        device,
        'pm grant ${shellQuote(args['package'])} '
        '${shellQuote(args['permission'])}',
      ),
    ),
    UtilityCommand(
      id: 'revoke-permission',
      label: 'Revoke permission',
      description:
          'Takes a runtime permission back — the app is not restarted.',
      icon: Icons.lock_outline,
      expectsOutput: false,
      successMessage: 'Permission revoked.',
      packageParamKey: 'package',
      params: const [
        UtilityParam(
          key: 'package',
          label: 'Package',
          hint: 'com.example.app',
          helperText: 'Right-click an app in the Apps pane to fill this in.',
        ),
        UtilityParam.suggestion(
          key: 'permission',
          label: 'Permission',
          hint: 'android.permission.CAMERA',
          options: androidRuntimePermissions,
          helperText: 'Pick a common one, or type any permission name.',
        ),
      ],
      build: (device, args) => _adbShell(
        device,
        'pm revoke ${shellQuote(args['package'])} '
        '${shellQuote(args['permission'])}',
      ),
    ),
    UtilityCommand(
      id: 'reset-permissions',
      label: 'Reset permissions',
      description:
          'Puts every runtime permission back to "ask", like a fresh install.',
      icon: Icons.restore,
      confirmation:
          'Every runtime permission for this package goes back to "ask". The '
          'app is force-stopped in the process.',
      packageParamKey: 'package',
      params: const [
        UtilityParam(
          key: 'package',
          label: 'Package',
          hint: 'com.example.app',
          helperText: 'Right-click an app in the Apps pane to fill this in.',
        ),
      ],
      build: (device, args) => _adbShell(
        device,
        'pm reset-permissions -p ${shellQuote(args['package'])}',
      ),
    ),
    UtilityCommand(
      id: 'package-info',
      label: 'Package details',
      description: 'Version, install source, permissions and components.',
      icon: Icons.inventory_2_outlined,
      packageParamKey: 'package',
      // Read-only, so it is the one app command safe to aim at a system app.
      systemAppSafe: true,
      params: const [
        UtilityParam(
          key: 'package',
          label: 'Package',
          hint: 'com.example.app',
          helperText: 'Right-click an app in the Apps pane to fill this in.',
        ),
      ],
      build: (device, args) =>
          _adbShell(device, 'dumpsys package ${shellQuote(args['package'])}'),
    ),
    UtilityCommand(
      id: 'monkey',
      label: 'Monkey stress test',
      description:
          'Fires pseudo-random UI events at an app to shake out crashes.',
      icon: Icons.bolt,
      confirmation:
          'The app will receive thousands of random taps and gestures. Do not '
          'run this against a signed-in production account.',
      packageParamKey: 'package',
      params: const [
        UtilityParam(
          key: 'package',
          label: 'Package',
          hint: 'com.example.app',
          helperText: 'Right-click an app in the Apps pane to fill this in.',
        ),
        UtilityParam(
          key: 'events',
          label: 'Event count',
          hint: '500',
          defaultValue: '500',
        ),
      ],
      build: (device, args) => _adbShell(
        device,
        'monkey -p ${shellQuote(args['package'])} -v ${args['events']} -s 100',
      ),
    ),
  ],
);

// ── Debug & diagnostics ───────────────────────────────────────────────────

final _debugGroup = UtilityGroup(
  id: 'debug',
  title: 'Debug & Diagnostics',
  icon: Icons.terminal,
  commands: [
    UtilityCommand(
      id: 'clear-logcat',
      label: 'Clear log buffer',
      description: 'Empties the on-device logcat ring buffer.',
      icon: Icons.cleaning_services_outlined,
      expectsOutput: false,
      successMessage: 'Log buffer cleared.',
      build: (device, args) => _adb(device, ['logcat', '-c']),
    ),
    UtilityCommand(
      id: 'dumpsys',
      label: 'Dump a system service',
      description:
          'Raw `dumpsys` output for one service (battery, power, wifi…).',
      icon: Icons.data_object,
      params: const [
        UtilityParam.suggestion(
          key: 'service',
          label: 'Service',
          hint: 'battery, power, wifi, activity …',
          defaultValue: 'battery',
          options: dumpsysServices,
          helperText: 'Run `dumpsys -l` on the device for the full list.',
        ),
      ],
      build: (device, args) =>
          _adbShell(device, 'dumpsys ${shellQuote(args['service'])}'),
    ),
    UtilityCommand(
      id: 'shell-command',
      label: 'Run shell command',
      description: 'Escape hatch — anything the device shell understands.',
      icon: Icons.code,
      params: const [
        UtilityParam(
          key: 'command',
          label: 'Command',
          hint: 'pm list packages -3',
        ),
      ],
      // Deliberately unquoted: the whole point is to pass the line through.
      build: (device, args) => _adbShell(device, args['command']),
    ),
    UtilityCommand(
      id: 'ios-diagnostics',
      label: 'Hardware diagnostics',
      description: 'Full diagnostics relay dump (battery, NAND, Wi-Fi…).',
      icon: Icons.monitor_heart_outlined,
      build: (device, args) => _idevice(
        device,
        UtilityTool.idevicediagnostics,
        ['diagnostics', 'All'],
      ),
    ),
    UtilityCommand(
      id: 'set-location',
      label: 'Simulate location',
      description: 'Overrides the reported GPS position.',
      icon: Icons.my_location,
      expectsOutput: false,
      successMessage: 'Simulated location set.',
      params: const [
        UtilityParam(key: 'lat', label: 'Latitude', hint: '48.8584'),
        UtilityParam(key: 'lon', label: 'Longitude', hint: '2.2945'),
      ],
      // `--` so a negative latitude isn't parsed as a flag.
      build: (device, args) => _idevice(
        device,
        UtilityTool.idevicesetlocation,
        ['--', args['lat'], args['lon']],
      ),
    ),
    UtilityCommand(
      id: 'reset-location',
      label: 'Reset simulated location',
      description: 'Hands location back to the real GPS.',
      icon: Icons.location_searching,
      expectsOutput: false,
      successMessage: 'Simulated location cleared.',
      build: (device, args) =>
          _idevice(device, UtilityTool.idevicesetlocation, ['reset']),
    ),
  ],
);
