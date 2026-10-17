import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../utils/android_sdk_path.dart';
import '../data/android_emulator.dart';

/// Reads AVD metadata straight off disk.
///
/// The alternative is `avdmanager list avd`, which reports the same facts but
/// costs a JVM start (well over a second) and needs a working `cmdline-tools`
/// install. Since the files are plain `key=value` INI, reading them is both
/// faster and available on SDKs that never installed `cmdline-tools`.
///
/// Nothing here throws: an AVD whose files are missing, truncated or
/// unreadable still yields an [AndroidEmulator] carrying just its name,
/// because `emulator -avd <name>` will launch it regardless and dropping it
/// from the list would be a lie.
class AvdMetadataReader {
  AvdMetadataReader({String? avdHome})
    : _avdHome = avdHome ?? AndroidSdkPath.avdHome();

  final String? _avdHome;

  /// Metadata for every name in [names], in the order given.
  Future<List<AndroidEmulator>> readAll(Iterable<String> names) {
    return Future.wait(names.map(read));
  }

  /// Metadata for the AVD called [name].
  Future<AndroidEmulator> read(String name) async {
    final avdHome = _avdHome;
    if (avdHome == null) return AndroidEmulator(name: name);

    // `<name>.ini` is a two-line pointer file; `path=` is what makes an AVD
    // stored outside the AVD home (a different disk, a shared checkout)
    // findable at all, so it wins over the conventional location.
    final pointer = await _readIni(_join(avdHome, ['$name.ini']));
    final avdPath =
        _normalizeDirectory(pointer['path']) ?? _join(avdHome, ['$name.avd']);

    final config = await _readIni(_join(avdPath, ['config.ini']));
    if (config.isEmpty && pointer.isEmpty) {
      return AndroidEmulator(name: name);
    }

    return buildEmulator(
      name: name,
      // `target` lives in both files; the pointer's copy is the fallback.
      config: {...pointer, ...config},
      avdPath: Directory(avdPath).existsSync() ? avdPath : null,
    );
  }

  /// Builds the model from already-parsed INI keys.
  @visibleForTesting
  static AndroidEmulator buildEmulator({
    required String name,
    required Map<String, String> config,
    String? avdPath,
  }) {
    return AndroidEmulator(
      name: name,
      displayName: _text(config['avd.ini.displayname']),
      avdPath: avdPath,
      deviceProfile: _text(config['hw.device.name']),
      manufacturer: _text(config['hw.device.manufacturer']),
      apiLevel: _apiLevel(config['target']),
      tagDisplay: _text(config['tag.display']),
      abi: _text(config['abi.type']),
      ramMb: _leadingInt(config['hw.ramSize']),
      screenWidthPx: _leadingInt(config['hw.lcd.width']),
      screenHeightPx: _leadingInt(config['hw.lcd.height']),
      densityDpi: _leadingInt(config['hw.lcd.density']),
      hasPlayStore: config['PlayStore.enabled']?.toLowerCase() == 'true',
    );
  }

  /// Parses an AVD INI: `key=value` per line, `#` comments, blank lines
  /// ignored. Values are split on the *first* `=` only, since paths and skin
  /// names routinely contain more.
  @visibleForTesting
  static Map<String, String> parseIni(String contents) {
    final entries = <String, String>{};

    for (final rawLine in const LineSplitter().convert(contents)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final separator = line.indexOf('=');
      if (separator <= 0) continue;

      final key = line.substring(0, separator).trim();
      if (key.isEmpty) continue;
      entries[key] = line.substring(separator + 1).trim();
    }

    return entries;
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  Future<Map<String, String>> _readIni(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return const {};
      return parseIni(await file.readAsString());
    } on FileSystemException {
      return const {};
    }
  }

  /// `android-36.1` → `36.1`. Returns null for a target we don't recognise
  /// (add-on targets such as `Google Inc.:Google APIs:24` exist on old SDKs).
  static String? _apiLevel(String? target) {
    final value = _text(target);
    if (value == null) return null;

    const prefix = 'android-';
    if (!value.toLowerCase().startsWith(prefix)) return null;

    final level = value.substring(prefix.length).trim();
    return level.isEmpty ? null : level;
  }

  /// `2048`, `2048MB` and `1536M` all mean megabytes.
  static int? _leadingInt(String? value) {
    final text = _text(value);
    if (text == null) return null;

    final match = RegExp(r'^\d+').firstMatch(text);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static String? _text(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? _normalizeDirectory(String? value) {
    final path = _text(value);
    if (path == null) return null;
    return Directory(path).existsSync() ? path : null;
  }

  static String _join(String parent, List<String> segments) =>
      [parent, ...segments].join(Platform.pathSeparator);
}
