import 'package:flutter/foundation.dart';

/// An Android Virtual Device as it exists *on disk*, before it boots.
///
/// Every field here is read from the AVD's own `.ini` / `config.ini`, which
/// means the list is available with no emulator running, no adb call, and —
/// crucially — no `avdmanager`, whose JVM startup costs well over a second per
/// invocation. Only [name] is guaranteed: an AVD that `emulator -list-avds`
/// reports but whose config cannot be read is still perfectly launchable, so
/// it appears with everything else null rather than being dropped.
@immutable
class const AndroidEmulator({
  /// The AVD id — what `emulator -avd` and `avdmanager` take. Never localised
  /// and never contains spaces, which is why it is a poor label.
  required final String name,

  /// `avd.ini.displayname`, the name Android Studio shows. Often absent on
  /// AVDs created by tooling rather than by the AVD Manager UI.
  final String? displayName,

  /// Absolute path to the `.avd` directory.
  final String? avdPath,

  /// Hardware profile id, e.g. `pixel_7a`.
  final String? deviceProfile,

  /// Profile vendor, e.g. `Google`.
  final String? manufacturer,

  /// API level as written in the AVD's `target`, e.g. `36.1` — a string, not
  /// an int, because minor-versioned platforms (`android-36.1`) are real.
  final String? apiLevel,

  /// System image tag as shown to humans, e.g. `Google Play`, `Google APIs`.
  final String? tagDisplay,

  /// System image ABI, e.g. `arm64-v8a`.
  final String? abi,
  final int? ramMb,
  final int? screenWidthPx,
  final int? screenHeightPx,
  final int? densityDpi,

  /// Whether the image bundles the Play Store (`PlayStore.enabled`).
  final bool hasPlayStore = false,
}) {
  /// What to show the user: the AVD's own display name when it set one,
  /// otherwise the id with its underscores read back as spaces.
  String get label {
    final display = displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    return name.replaceAll('_', ' ');
  }

  /// `1080 × 2400` when both dimensions are known.
  String? get resolution {
    if (screenWidthPx == null || screenHeightPx == null) return null;
    return '$screenWidthPx × $screenHeightPx';
  }

  /// One-line tile subtitle: `API 36.1 · Google Play · arm64-v8a`.
  ///
  /// Empty when the config could not be read, which is the caller's cue to
  /// show nothing rather than a row of placeholders.
  String get summary => [
    if (apiLevel != null) 'API $apiLevel',
    if (tagDisplay != null) tagDisplay!,
    if (abi != null) abi!,
  ].join(' · ');

  /// True when nothing beyond the id could be read off disk.
  bool get isMetadataMissing =>
      displayName == null &&
      apiLevel == null &&
      abi == null &&
      deviceProfile == null;

  @override
  bool operator ==(Object other) =>
      other is AndroidEmulator &&
      other.name == name &&
      other.displayName == displayName &&
      other.avdPath == avdPath &&
      other.deviceProfile == deviceProfile &&
      other.manufacturer == manufacturer &&
      other.apiLevel == apiLevel &&
      other.tagDisplay == tagDisplay &&
      other.abi == abi &&
      other.ramMb == ramMb &&
      other.screenWidthPx == screenWidthPx &&
      other.screenHeightPx == screenHeightPx &&
      other.densityDpi == densityDpi &&
      other.hasPlayStore == hasPlayStore;

  @override
  int get hashCode => Object.hash(
    name,
    displayName,
    avdPath,
    deviceProfile,
    manufacturer,
    apiLevel,
    tagDisplay,
    abi,
    ramMb,
    screenWidthPx,
    screenHeightPx,
    densityDpi,
    hasPlayStore,
  );

  @override
  String toString() => 'AndroidEmulator($name)';
}
