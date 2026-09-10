import 'package:flutter/foundation.dart';

/// How an AVD should be started.
@immutable
class EmulatorLaunchOptions {
  const EmulatorLaunchOptions({this.coldBoot = false, this.wipeData = false});

  /// The plain "just start it" launch: resume the saved snapshot if there is
  /// one, keep user data.
  static const normal = EmulatorLaunchOptions();

  /// Boot from scratch rather than resuming the saved snapshot. The usual fix
  /// for an AVD that resumes into a broken state.
  final bool coldBoot;

  /// Erase the AVD's user data first — a factory reset. Destructive, and it
  /// forces a cold boot regardless of [coldBoot].
  final bool wipeData;

  /// True when launching this way throws away state the user cannot get back,
  /// which is what puts a confirmation in front of it.
  bool get isDestructive => wipeData;

  /// Emulator flags for these options, appended after `-avd <name>`.
  List<String> toArguments() => [
    if (coldBoot) '-no-snapshot-load',
    if (wipeData) '-wipe-data',
  ];

  @override
  bool operator ==(Object other) =>
      other is EmulatorLaunchOptions &&
      other.coldBoot == coldBoot &&
      other.wipeData == wipeData;

  @override
  int get hashCode => Object.hash(coldBoot, wipeData);

  @override
  String toString() =>
      'EmulatorLaunchOptions(coldBoot: $coldBoot, wipeData: $wipeData)';
}

/// What came of asking the emulator binary to start.
///
/// "Started" means the process was spawned, not that the device booted — the
/// emulator is launched detached and reports nothing back, so a booted device
/// is confirmed by watching for it to appear in `adb devices`.
@immutable
class EmulatorLaunchOutcome {
  const EmulatorLaunchOutcome({required this.started, this.pid, this.error});

  const EmulatorLaunchOutcome.success(int pid) : this(started: true, pid: pid);

  const EmulatorLaunchOutcome.failure(String error)
    : this(started: false, error: error);

  final bool started;
  final int? pid;
  final String? error;

  bool get isSuccess => started;
}
