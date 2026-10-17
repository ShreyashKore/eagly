import 'package:flutter/foundation.dart';

import 'android_emulator.dart';

/// Where an AVD is in the stopped → running → stopped cycle.
enum EmulatorRunState {
  /// Not in `adb devices`. The only state a launch is offered from.
  stopped,

  /// Launched from here, and its device has not come online yet.
  ///
  /// Boot state cannot be read back off adb: `DevicesRepository` reports an
  /// `offline` Android device as disconnected, so an emulator that is mid-boot
  /// looks exactly like one that was never started. This state is therefore
  /// our own record of a launch we fired, and an emulator someone started in
  /// Android Studio stays [stopped] here until it finishes booting.
  starting,

  /// Booted and addressable. This is the state a device tab can be opened in.
  running,

  /// `adb emu kill` was sent and the serial has not gone away yet.
  stopping,
}

/// One AVD as the emulator manager shows it: what is on disk, plus whatever it
/// happens to be doing right now.
///
/// [AndroidEmulator] is deliberately kept free of runtime state. It is read
/// from files that do not change while the dialog is open, so keeping the two
/// halves apart lets the poll rebuild the runtime one every couple of seconds
/// without touching the disk again.
@immutable
class EmulatorEntry {
  const EmulatorEntry({
    required this.emulator,
    this.runState = EmulatorRunState.stopped,
    this.serial,
  });

  final AndroidEmulator emulator;
  final EmulatorRunState runState;

  /// The adb serial (`emulator-5554`) while this AVD is up, otherwise `null`.
  /// It is a console port, not an identity: the same AVD gets a different one
  /// on every boot.
  final String? serial;

  String get name => emulator.name;
  String get label => emulator.label;

  bool get isStopped => runState == EmulatorRunState.stopped;
  bool get isRunning => runState == EmulatorRunState.running;

  /// True while the AVD is mid-transition — neither ready to launch nor ready
  /// to stop, so both actions are held back rather than offered and refused.
  bool get isTransitioning =>
      runState == EmulatorRunState.starting ||
      runState == EmulatorRunState.stopping;

  EmulatorEntry copyWith({
    AndroidEmulator? emulator,
    EmulatorRunState? runState,
    String? serial,
    bool clearSerial = false,
  }) {
    return EmulatorEntry(
      emulator: emulator ?? this.emulator,
      runState: runState ?? this.runState,
      serial: clearSerial ? null : (serial ?? this.serial),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EmulatorEntry &&
      other.emulator == emulator &&
      other.runState == runState &&
      other.serial == serial;

  @override
  int get hashCode => Object.hash(emulator, runState, serial);

  @override
  String toString() => 'EmulatorEntry($name, ${runState.name}, $serial)';
}
