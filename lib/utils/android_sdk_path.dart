import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/preferences_service.dart';

/// How usable the Android SDK we found turned out to be.
enum AndroidSdkStatus {
  /// SDK found and its `emulator` package is installed.
  ready,

  /// An SDK is there, but the `emulator` package is not installed in it.
  emulatorMissing,

  /// Nothing that looks like an SDK at any candidate location.
  sdkMissing,
}

/// Where the Android SDK is and which of its tools can actually be run.
@immutable
class const AndroidSdkLocation({
  required this.status,
  this.sdkPath,
  this.emulatorExecutable,
  this.avdManagerExecutable,
}) {
  const AndroidSdkLocation.missing()
    : this(status: AndroidSdkStatus.sdkMissing);

  final AndroidSdkStatus status;

  /// SDK root, set for every status except [AndroidSdkStatus.sdkMissing].
  final String? sdkPath;

  /// Absolute path to the emulator binary; non-null exactly when [isReady].
  final String? emulatorExecutable;

  /// `null` when `cmdline-tools` is not installed. Creating and deleting AVDs
  /// is unavailable then — listing and launching are not, so this must never
  /// gate the feature as a whole.
  final String? avdManagerExecutable;

  bool get isReady => status == AndroidSdkStatus.ready;

  /// True when AVDs can also be created and deleted, not just launched.
  bool get canManageAvds => isReady && avdManagerExecutable != null;
}

/// Locates the user's own Android SDK.
///
/// `adb` and the libimobiledevice suite are *bundled* under
/// `platform-tools/<os>/` and resolved by `utils/tools_path.dart`. The emulator
/// is not, and never will be: it only runs against system images that are
/// gigabytes each, so it ships with the user's Android SDK and the emulator
/// manager has to go find that SDK instead of assuming one.
///
/// Order: the Settings override, then `ANDROID_HOME`, then `ANDROID_SDK_ROOT`,
/// then the platform's default install path. The env vars sit *below* the
/// explicit override and *above* the default, but they cannot be relied on at
/// all — an app launched from Finder or the Start menu inherits the login
/// environment rather than a shell's, so `ANDROID_HOME` is usually unset even
/// on a machine where the SDK is installed and Android Studio works fine.
/// That is why the default path matters and why the override exists.
class const AndroidSdkPath._() {
  /// The process environment. Swappable because Dart cannot mutate the real
  /// one, and the precedence rules above are worth testing.
  @visibleForTesting
  static Map<String, String> environment = Platform.environment;

  /// Restores [environment]; call from `tearDown`.
  @visibleForTesting
  static void resetEnvironment() {
    environment = Platform.environment;
  }

  /// Directories that only ever appear inside an SDK root.
  static const _sdkMarkers = [
    'emulator',
    'platform-tools',
    'cmdline-tools',
    'licenses',
  ];

  /// Everything the emulator manager needs, resolved in one pass.
  static AndroidSdkLocation locate() {
    final sdkRoot = resolveSdkRoot();
    if (sdkRoot == null) return const AndroidSdkLocation.missing();

    final emulator = emulatorExecutable(sdkRoot);
    return AndroidSdkLocation(
      status: emulator == null
          ? AndroidSdkStatus.emulatorMissing
          : AndroidSdkStatus.ready,
      sdkPath: sdkRoot,
      emulatorExecutable: emulator,
      avdManagerExecutable: avdManagerExecutable(sdkRoot),
    );
  }

  /// The first candidate that looks like an SDK, or `null` when none does.
  static String? resolveSdkRoot() {
    for (final candidate in candidateSdkRoots()) {
      if (looksLikeSdk(candidate)) return candidate;
    }
    return null;
  }

  /// Every location [resolveSdkRoot] considers, in order and de-duplicated.
  ///
  /// Exposed so the "SDK not found" notice can list exactly what was tried
  /// rather than leaving the user to guess where Eagly looked.
  static List<String> candidateSdkRoots() {
    final candidates = <String>[];
    final seen = <String>{};

    for (final raw in <String?>[
      PreferencesService.androidSdkPath,
      environment['ANDROID_HOME'],
      environment['ANDROID_SDK_ROOT'],
      ...defaultSdkRoots(),
    ]) {
      final candidate = _normalize(raw);
      if (candidate == null) continue;
      if (seen.add(candidate)) candidates.add(candidate);
    }

    return candidates;
  }

  /// Where each platform's Android Studio installs the SDK by default.
  static List<String> defaultSdkRoots() {
    final home = homeDirectory();

    if (Platform.isMacOS) {
      return [
        if (home != null) _join(home, ['Library', 'Android', 'sdk']),
      ];
    }

    if (Platform.isWindows) {
      final localAppData = _normalize(environment['LOCALAPPDATA']);
      return [
        if (localAppData != null) _join(localAppData, ['Android', 'Sdk']),
        if (home != null) _join(home, ['AppData', 'Local', 'Android', 'Sdk']),
      ];
    }

    return [
      if (home != null) ...[
        _join(home, ['Android', 'Sdk']),
        _join(home, ['.local', 'share', 'Android', 'sdk']),
      ],
    ];
  }

  /// True when [path] holds at least one directory unique to an SDK root.
  ///
  /// Deliberately loose. A partial SDK — one whose `emulator` package was
  /// never installed — should be reported as "install the emulator package",
  /// not as "no SDK here", which would send the user hunting for a path they
  /// already have.
  static bool looksLikeSdk(String path) {
    if (path.isEmpty) return false;
    return _sdkMarkers.any(
      (marker) => Directory(_join(path, [marker])).existsSync(),
    );
  }

  /// The emulator binary inside [sdkRoot], or `null` when not installed.
  static String? emulatorExecutable(String sdkRoot) {
    return _existingFile(
      _join(sdkRoot, ['emulator', _executableName('emulator')]),
    );
  }

  /// `avdmanager` inside [sdkRoot], or `null` when `cmdline-tools` is absent.
  static String? avdManagerExecutable(String sdkRoot) {
    final fileName = Platform.isWindows ? 'avdmanager.bat' : 'avdmanager';

    final latest = _existingFile(
      _join(sdkRoot, ['cmdline-tools', 'latest', 'bin', fileName]),
    );
    if (latest != null) return latest;

    // A versioned install (`cmdline-tools/13.0/bin`) works just as well as
    // `latest`. Sorting by directory name is a lexicographic tiebreak, not a
    // version comparison — `latest` is the normal case and this is the rare
    // fallback, so picking "16.0" over "9.0" is not worth a version parser.
    final cmdlineTools = Directory(_join(sdkRoot, ['cmdline-tools']));
    if (cmdlineTools.existsSync()) {
      final versioned =
          cmdlineTools
              .listSync()
              .whereType<Directory>()
              .map((directory) => directory.path)
              .toList()
            ..sort();
      for (final directory in versioned.reversed) {
        final executable = _existingFile(_join(directory, ['bin', fileName]));
        if (executable != null) return executable;
      }
    }

    // SDKs from before the 2021 cmdline-tools split kept it in `tools/bin`.
    return _existingFile(_join(sdkRoot, ['tools', 'bin', fileName]));
  }

  /// Every directory the emulator searches for AVDs, in order.
  ///
  /// Taken from the emulator's own error output rather than from the docs,
  /// which disagree with it:
  ///
  ///     (Note: Directories are searched in the order $ANDROID_AVD_HOME,
  ///      $ANDROID_SDK_HOME/avd and $HOME/.android/avd)
  ///
  /// `ANDROID_USER_HOME` is newer than that message and is what current SDK
  /// tooling sets, so it goes in too, and `$ANDROID_SDK_HOME/.android/avd` is
  /// the pre-2019 layout still found in the wild beside the `/avd` spelling.
  /// Getting this wrong costs metadata, not function: the emulator resolves
  /// the AVD itself at launch, so a missed directory shows up as a tile with
  /// no details rather than an AVD that will not start.
  static List<String> avdHomeCandidates() {
    final candidates = <String>[];

    void add(String? path) {
      if (path != null && !candidates.contains(path)) candidates.add(path);
    }

    add(_normalize(environment['ANDROID_AVD_HOME']));

    final userHome = _normalize(environment['ANDROID_USER_HOME']);
    if (userHome != null) add(_join(userHome, ['avd']));

    final sdkHome = _normalize(environment['ANDROID_SDK_HOME']);
    if (sdkHome != null) {
      add(_join(sdkHome, ['avd']));
      add(_join(sdkHome, ['.android', 'avd']));
    }

    final home = homeDirectory();
    if (home != null) add(_join(home, ['.android', 'avd']));

    return candidates;
  }

  /// The first candidate that exists on disk.
  ///
  /// Falls back to the last candidate — the conventional `~/.android/avd` —
  /// when none do, so an error message always has a path to name. `null` only
  /// when the environment reveals no home directory at all.
  static String? avdHome() {
    final candidates = avdHomeCandidates();
    for (final candidate in candidates) {
      if (Directory(candidate).existsSync()) return candidate;
    }
    return candidates.isEmpty ? null : candidates.last;
  }

  /// The user's home directory, or `null` when the environment has no idea.
  static String? homeDirectory() =>
      _normalize(environment['HOME']) ?? _normalize(environment['USERPROFILE']);

  // ── helpers ──────────────────────────────────────────────────────────────

  static String _join(String parent, List<String> segments) =>
      [parent, ...segments].join(Platform.pathSeparator);

  static String _executableName(String name) =>
      Platform.isWindows ? '$name.exe' : name;

  static String? _existingFile(String path) =>
      File(path).existsSync() ? path : null;

  /// Trims whitespace and any trailing separator so two spellings of the same
  /// directory de-duplicate. Returns `null` for null/blank input.
  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    final separator = Platform.pathSeparator;
    if (trimmed.length > 1 && trimmed.endsWith(separator)) {
      return trimmed.substring(0, trimmed.length - separator.length);
    }
    return trimmed;
  }
}
