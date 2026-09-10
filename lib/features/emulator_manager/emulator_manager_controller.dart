import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../data/device.dart';
import '../app_log/app_logger.dart';
import '../../services/devices_repository.dart';
import '../../services/tools/adb_tool.dart';
import '../../services/tools/emulator_tool.dart';
import '../../utils/android_sdk_path.dart';
import 'data/android_emulator.dart';
import 'data/emulator_entry.dart';
import 'data/emulator_launch_options.dart';
import 'services/avd_metadata_reader.dart';

/// Drives the emulator manager: the AVD list read off disk, the runtime state
/// of each one, and the launch/stop actions.
///
/// Two refreshes with very different costs, kept apart on purpose:
///
///  * [refresh] re-reads the SDK — `emulator -list-avds` plus one `config.ini`
///    per AVD. Runs on open and on the Refresh action, never on a timer.
///  * the poll loop re-reads only *runtime* state, from the device list
///    [DevicesRepository] already maintains over `adb track-devices`. No disk,
///    and an adb call only for a serial whose AVD name is not cached yet.
///
/// The wireless dialog's scan is the cautionary tale this follows: keep the
/// loop passive, guard it by generation so a parked one cannot resume after
/// dispose, and never let it notify listeners on a tick where nothing changed —
/// a 2 s unconditional rebuild pulls the ground out from under any text field
/// the dialog has open.
class EmulatorManagerController extends ChangeNotifier {
  EmulatorManagerController({
    DevicesRepository? devicesRepository,
    AdbTool? adbTool,
    AvdMetadataReader? metadataReader,
    AndroidSdkLocation Function()? locateSdk,
    EmulatorTool Function(String executablePath)? createEmulatorTool,
    this.onEmulatorReady,
  }) : _devicesRepository = devicesRepository ?? DevicesRepository.instance,
       _adbTool = adbTool ?? AdbTool(),
       _metadataReader = metadataReader ?? AvdMetadataReader(),
       _locateSdk = locateSdk ?? AndroidSdkPath.locate,
       _createEmulatorTool = createEmulatorTool ?? _defaultEmulatorTool;

  static EmulatorTool _defaultEmulatorTool(String executablePath) =>
      EmulatorTool(executablePath: executablePath);

  final DevicesRepository _devicesRepository;
  final AdbTool _adbTool;
  final AvdMetadataReader _metadataReader;
  final AndroidSdkLocation Function() _locateSdk;
  final EmulatorTool Function(String executablePath) _createEmulatorTool;
  final AppLogger _logger = AppLogger(source: 'EmulatorManagerController');

  /// Called once a launched AVD has booted far enough for adb to call it
  /// `device`. Opening its tab is the caller's job — the controller knows
  /// nothing about tabs.
  final Future<void> Function(Device device)? onEmulatorReady;

  /// How often the runtime state is re-read while the dialog is open.
  @visibleForTesting
  static Duration pollInterval = const Duration(seconds: 2);

  /// How long a launched AVD may sit in [EmulatorRunState.starting] before it
  /// is given up on.
  ///
  /// Generous by design. A detached emulator reports nothing back, so this is
  /// the only way a launch that died on startup ever stops saying "Starting" —
  /// but a cold boot on a slow machine legitimately takes minutes, and calling
  /// a boot failed while it is still booting is the worse error.
  @visibleForTesting
  static Duration launchTimeout = const Duration(minutes: 3);

  AndroidSdkLocation? _sdk;
  List<AndroidEmulator> _emulators = const [];
  List<EmulatorEntry> _entries = const [];
  EmulatorTool? _emulatorTool;
  String? _emulatorToolPath;

  var _loading = false;
  var _busy = false;
  String? _message;
  String? _error;

  /// AVD name → when its launch was fired. An entry lives here from the moment
  /// the emulator process is spawned until its device shows up booted, which
  /// is what makes both the "Starting" label and the auto-opened tab possible.
  final Map<String, DateTime> _pendingLaunches = {};

  /// Serials that were sent `emu kill` and have not disappeared yet.
  final Set<String> _stoppingSerials = {};

  /// Serial → AVD name. Cached because a serial's AVD cannot change while it
  /// is up, and resolving one costs an `adb emu avd name` round trip.
  final Map<String, String> _serialAvdNames = {};

  var _polling = false;
  var _pollGeneration = 0;
  var _disposed = false;

  // ── State ────────────────────────────────────────────────────────────────

  /// Where the SDK is, as of the last [refresh]. `null` before the first one.
  AndroidSdkLocation? get sdk => _sdk;
  bool get isSdkReady => _sdk?.isReady ?? false;
  bool get canManageAvds => _sdk?.canManageAvds ?? false;

  List<EmulatorEntry> get entries => List.unmodifiable(_entries);
  bool get hasEmulators => _entries.isNotEmpty;

  /// True while the AVD list itself is being read. Passive: it never blocks a
  /// launch, and no action should wait on it.
  bool get isLoading => _loading;

  /// True while a launch or stop *command* is in flight.
  ///
  /// Deliberately narrow. It does not cover the poll, and it does not cover an
  /// emulator booting — that can take minutes, and a dialog frozen for the
  /// duration is the starvation bug the wireless pane already paid for. Per-AVD
  /// progress lives in [EmulatorEntry.runState].
  bool get isBusy => _busy;

  String? get message => _message;
  String? get error => _error;

  /// Names of AVDs whose launch has been fired but whose device has not booted
  /// yet.
  @visibleForTesting
  Set<String> get pendingLaunches => Set.unmodifiable(_pendingLaunches.keys);

  bool get isPolling => _polling;

  EmulatorEntry? entryFor(String name) =>
      _entries.firstWhereOrNull((entry) => entry.name == name);

  // ── Lifecycle ────────────────────────────────────────────────────────────

  /// Loads the AVD list and starts watching runtime state. Call from the
  /// dialog's `initState`.
  Future<void> start() async {
    unawaited(_devicesRepository.ensureStarted());
    await refresh();
    _startPolling();
  }

  /// Re-reads the SDK: where it is, which AVDs it has, and what is in each
  /// one's `config.ini`.
  Future<void> refresh() async {
    if (_disposed) return;

    _loading = true;
    _error = null;
    _notify();

    try {
      // Re-located every time rather than cached, so changing the SDK path in
      // Settings takes effect on the next refresh with no plumbing between the
      // two screens.
      final sdk = _locateSdk();
      _sdk = sdk;

      if (!sdk.isReady) {
        _emulators = const [];
        _entries = const [];
        return;
      }

      final names = await _toolFor(sdk).listAvds();
      if (_disposed) return;

      final emulators = await _metadataReader.readAll(names);
      if (_disposed) return;

      _emulators = emulators.sorted(
        (left, right) =>
            left.label.toLowerCase().compareTo(right.label.toLowerCase()),
      );
      _rebuildEntries();
    } finally {
      _loading = false;
      _notify();
    }

    await _refreshRuntimeState();
  }

  /// Starts the runtime poll. Safe to call when already polling.
  ///
  /// [_pollGeneration] is the cancellation token: a loop parked in its interval
  /// delay cannot be interrupted, so it re-checks the generation on waking and
  /// returns when it has been superseded.
  void _startPolling() {
    if (_polling || _disposed) return;
    _polling = true;
    _pollGeneration++;
    unawaited(_runPollLoop(_pollGeneration));
  }

  void stopPolling() {
    if (!_polling) return;
    _polling = false;
    _pollGeneration++;
  }

  Future<void> _runPollLoop(int generation) async {
    bool isStale() => _disposed || !_polling || generation != _pollGeneration;

    while (!isStale()) {
      await Future<void>.delayed(pollInterval);
      if (isStale()) return;
      try {
        await _refreshRuntimeState();
      } catch (error, stackTrace) {
        // A throw here would leave [_polling] true with no loop behind it, so
        // the dialog would silently stop tracking anything and refuse to start
        // a new loop. One bad tick is not worth that.
        _logger.error('Emulator poll failed', detail: '$error\n$stackTrace');
      }
    }
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  /// Starts [name], if this SDK has it and it is not already up.
  ///
  /// Returns whether the emulator *process* was spawned — not whether it
  /// booted. A detached emulator cannot report that, so booting is watched for
  /// by the poll and surfaces through [EmulatorEntry.runState] and, on success,
  /// [onEmulatorReady].
  Future<bool> launch(
    String name, {
    EmulatorLaunchOptions options = EmulatorLaunchOptions.normal,
  }) async {
    final sdk = _sdk;
    if (sdk == null || !sdk.isReady) {
      return _fail('The Android SDK emulator was not found.');
    }
    if (_busy) {
      return _fail('Finish the current emulator action before starting one.');
    }

    final entry = entryFor(name);
    if (entry == null) {
      // The list is stale — the AVD was deleted elsewhere, most likely in
      // Android Studio. Re-read rather than leave a tile that cannot work.
      unawaited(refresh());
      return _fail('$name is no longer in this SDK.');
    }
    if (!entry.isStopped) {
      return _fail('${entry.label} is already running.');
    }

    _busy = true;
    _message = null;
    _error = null;
    _notify();

    try {
      final outcome = await _toolFor(sdk).launch(name, options: options);
      if (_disposed) return outcome.isSuccess;

      if (!outcome.isSuccess) {
        _error = outcome.error ?? 'Could not start ${entry.label}.';
        return false;
      }

      _pendingLaunches[name] = DateTime.now();
      _message = options.wipeData
          ? 'Wiping ${entry.label} and starting it…'
          : 'Starting ${entry.label}…';
      _applyRuntimeStates(_currentRuntimeStates());
      return true;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Asks a running AVD to shut down.
  ///
  /// The emulator exits on its own schedule, so the serial lingers for a few
  /// seconds afterwards; the poll is what eventually clears the tile.
  Future<bool> stopEmulator(String name) async {
    if (_busy) {
      return _fail('Finish the current emulator action before stopping one.');
    }

    final entry = entryFor(name);
    final serial = entry?.serial;
    if (entry == null || serial == null) {
      return _fail('$name is not running.');
    }

    _busy = true;
    _message = null;
    _error = null;
    _stoppingSerials.add(serial);
    _applyRuntimeStates(_currentRuntimeStates());
    _notify();

    try {
      final result = await _adbTool.killEmulator(serial);
      if (_disposed) return result.isSuccess;

      if (!result.isSuccess) {
        _stoppingSerials.remove(serial);
        _applyRuntimeStates(_currentRuntimeStates());
        _error = result.error ?? 'Failed to stop ${entry.label}.';
        return false;
      }

      _message = 'Stopping ${entry.label}…';
      return true;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void clearFeedback() {
    if (_message == null && _error == null) return;
    _message = null;
    _error = null;
    _notify();
  }

  // ── Runtime state ────────────────────────────────────────────────────────

  /// Reconciles the AVD list with what is actually running.
  ///
  /// Cheap on purpose: the device list is a synchronous read of what
  /// [DevicesRepository] already tracks, and the only I/O is one
  /// `adb emu avd name` per serial that has not been resolved before.
  Future<void> _refreshRuntimeState() async {
    if (_disposed) return;

    final serials = _liveEmulatorSerials();

    // A serial is a console port that gets recycled, so stale entries here
    // would eventually name the wrong AVD.
    _serialAvdNames.removeWhere((serial, _) => !serials.contains(serial));
    _stoppingSerials.removeWhere((serial) => !serials.contains(serial));

    for (final serial in serials) {
      if (_serialAvdNames.containsKey(serial)) continue;
      final name = await _adbTool.emulatorAvdName(serial);
      if (_disposed) return;
      // A `null` here is usually an emulator whose console is not up yet, not
      // a failure: leave it unresolved and try again on the next tick.
      if (name != null) _serialAvdNames[serial] = name;
    }

    final states = _currentRuntimeStates();
    final changed = _applyRuntimeStates(states);
    final resolved = _resolvePendingLaunches(states);

    if (changed || resolved.isNotEmpty) _notify();

    for (final device in resolved) {
      if (_disposed) return;
      try {
        await onEmulatorReady?.call(device);
      } catch (error) {
        // Opening the tab is the caller's business, and its failure is not a
        // reason to stop tracking the emulator that did boot.
        _logger.error(
          'Failed to open the tab for ${device.id}',
          detail: '$error',
        );
      }
    }
  }

  Set<String> _liveEmulatorSerials() {
    return {
      for (final device in _devicesRepository.devices)
        if (device.isConnected && AdbTool.isEmulatorSerial(device.id))
          device.id,
    };
  }

  /// The run state of every AVD that has one right now, keyed by AVD name.
  Map<String, EmulatorEntry> _currentRuntimeStates() {
    final states = <String, EmulatorEntry>{};

    // `isConnected` already means `status == 'device'` for an Android device —
    // the repository downgrades `offline` and `unauthorized` to disconnected —
    // so a serial that is here at all is one adb will talk to.
    for (final serial in _liveEmulatorSerials()) {
      final name = _serialAvdNames[serial];
      if (name == null) continue;

      states[name] = EmulatorEntry(
        emulator: AndroidEmulator(name: name),
        runState: _stoppingSerials.contains(serial)
            ? EmulatorRunState.stopping
            : EmulatorRunState.running,
        serial: serial,
      );
    }

    // Which leaves booting emulators with nothing to be found by: they are
    // `offline` for the whole boot and therefore absent above. A launch we
    // fired ourselves is the one case we can still account for.
    for (final name in _pendingLaunches.keys) {
      states.putIfAbsent(
        name,
        () => EmulatorEntry(
          emulator: AndroidEmulator(name: name),
          runState: EmulatorRunState.starting,
        ),
      );
    }

    return states;
  }

  /// Merges [states] into [entries]. Returns whether anything actually moved —
  /// the poll ticks every couple of seconds and most ticks change nothing.
  bool _applyRuntimeStates(Map<String, EmulatorEntry> states) {
    final previous = _entries;
    _rebuildEntries(states);
    return !listEquals(previous, _entries);
  }

  void _rebuildEntries([Map<String, EmulatorEntry>? states]) {
    final runtime = states ?? _currentRuntimeStates();
    _entries = [
      for (final emulator in _emulators)
        EmulatorEntry(
          emulator: emulator,
          runState:
              runtime[emulator.name]?.runState ?? EmulatorRunState.stopped,
          serial: runtime[emulator.name]?.serial,
        ),
    ];
  }

  /// Closes out launches that either booted or ran out of time. Returns the
  /// devices whose tabs should be opened.
  List<Device> _resolvePendingLaunches(Map<String, EmulatorEntry> states) {
    if (_pendingLaunches.isEmpty) return const [];

    final ready = <Device>[];
    final now = DateTime.now();

    for (final name in _pendingLaunches.keys.toList(growable: false)) {
      final state = states[name];

      if (state != null && state.runState == EmulatorRunState.running) {
        _pendingLaunches.remove(name);
        final device = _devicesRepository.devices.firstWhereOrNull(
          (candidate) => candidate.id == state.serial,
        );
        _message = '${entryFor(name)?.label ?? name} is ready.';
        _error = null;
        if (device != null) ready.add(device);
        continue;
      }

      final startedAt = _pendingLaunches[name];
      if (startedAt != null && now.difference(startedAt) > launchTimeout) {
        _pendingLaunches.remove(name);
        _message = null;
        _error =
            '${entryFor(name)?.label ?? name} did not finish booting within '
            '${launchTimeout.inMinutes} minutes. It may still be starting — '
            'check the emulator window.';
      }
    }

    return ready;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  EmulatorTool _toolFor(AndroidSdkLocation sdk) {
    final path = sdk.emulatorExecutable!;
    final tool = _emulatorTool;
    if (tool != null && _emulatorToolPath == path) return tool;

    final created = _createEmulatorTool(path);
    _emulatorTool = created;
    _emulatorToolPath = path;
    return created;
  }

  bool _fail(String error) {
    _message = null;
    _error = error;
    _notify();
    return false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _polling = false;
    _pollGeneration++;
    super.dispose();
  }
}
