import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../data/device.dart';

/// Developer-only launch mode for recording product videos: `--record-mode`
/// pins the window to a fixed, centred [windowSize] so every take is framed
/// identically, and keeps real devices anonymous and tidy: believable
/// stand-ins for serials and UDIDs, and devices named by brand and model
/// alone — no ids, no owner-given names.
///
/// Everything recording-specific lives here; removing the feature means
/// deleting this file, its call sites in `main.dart`, and the
/// `Device.presentId` / `Device.shortNames` seams.
abstract final class RecordMode {
  /// Command-line flag that turns record mode on.
  static const flag = '--record-mode';

  /// Window size, in logical pixels, used while recording.
  static const windowSize = Size(1920, 1080);

  /// Whether [args] — the arguments the runner forwarded to `main` — ask for
  /// record mode.
  static bool isRequested(List<String> args) => args.contains(flag);

  /// Locks the window to [windowSize] and centres it. Call after
  /// `windowManager.ensureInitialized()` and before the window is shown.
  static Future<void> applyWindowLayout() async {
    await windowManager.setMinimumSize(windowSize);
    await windowManager.setMaximumSize(windowSize);
    await windowManager.setSize(windowSize);
    await windowManager.center();
  }

  // ── Anonymous devices ─────────────────────────────────────────────────

  /// From now on, shows every device identifier as its [standInId] and
  /// names devices by brand and model alone. Display only — tools keep
  /// getting the real id.
  static void anonymizeDevices() {
    Device.presentId = standInId;
    Device.shortNames = true;
  }

  /// A fake that looks like [id]: same length, letters for letters and
  /// digits for digits, and stable — the same device gets the same stand-in
  /// on every launch, so retakes match. Parts that identify no one stay:
  /// emulator serials, LAN addresses, the chip-model half of a UDID, the
  /// first two characters of a serial (a manufacturer's prefix).
  static String standInId(String id) {
    if (_emulatorSerial.hasMatch(id) || _ipAddress.hasMatch(id)) return id;
    final mdns = _mdnsId.firstMatch(id);
    if (mdns != null) {
      return 'adb-${standInId(mdns[1]!)}-${_scramble(mdns[2]!)}${mdns[3]}';
    }
    final udid = _modernUdid.firstMatch(id);
    if (udid != null) return '${udid[1]}-${_scramble(udid[2]!)}';
    return _scramble(id, keep: 2);
  }

  static final _emulatorSerial = RegExp(r'^emulator-\d+$');
  static final _ipAddress = RegExp(r'^\d+\.\d+\.\d+\.\d+(:\d+)?$');
  static final _mdnsId = RegExp(r'^adb-([A-Za-z0-9]+)-([A-Za-z0-9]+)(\..+)$');
  static final _modernUdid = RegExp(r'^([0-9A-Fa-f]{8})-([0-9A-Fa-f]{16})$');
  static final _hex = RegExp(r'^[0-9A-Fa-f]+$');

  /// Swaps each letter or digit after the first [keep] for a random one of
  /// the same kind (hex stays hex), seeded by [value] itself.
  static String _scramble(String value, {int keep = 0}) {
    final random = Random(_fnv1a(value));
    final hex = _hex.hasMatch(value);
    final out = StringBuffer(value.substring(0, min(keep, value.length)));
    for (var i = out.length; i < value.length; i++) {
      final char = value[i];
      final code = char.codeUnitAt(0);
      final letters = hex ? 6 : 26;
      if (code >= 0x30 && code <= 0x39) {
        out.write(random.nextInt(10));
      } else if (code >= 0x41 && code <= 0x5A) {
        out.writeCharCode(0x41 + random.nextInt(letters));
      } else if (code >= 0x61 && code <= 0x7A) {
        out.writeCharCode(0x61 + random.nextInt(letters));
      } else {
        out.write(char);
      }
    }
    return out.toString();
  }

  /// 32-bit FNV-1a — unlike [String.hashCode], stable across launches.
  static int _fnv1a(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}
