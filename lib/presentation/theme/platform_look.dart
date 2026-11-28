import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;

/// What makes Eagly look at home on each desktop, without a second widget
/// set: the window's own backdrop material behind the chrome (macOS sidebar
/// vibrancy, Windows 11 Mica), the platform's UI font, and its corner radii.
/// The widgets stay Material; only the theme and the window change.
///
/// Linux has no system backdrop worth borrowing (GNOME draws none), so it
/// keeps the bundled Inter and opaque chrome.
///
/// Font and shape follow [defaultTargetPlatform], not `dart:io`'s
/// `Platform`, so widget tests (which run as Android) keep today's look and
/// `debugDefaultTargetPlatformOverride` can preview another platform's.
abstract final class PlatformLook {
  // ── Window material ───────────────────────────────────────────────────

  /// Whether the window shows a system material behind the app's chrome.
  /// Set by [applyWindowMaterial]; chrome reads it through [chromeColor].
  static bool get hasWindowMaterial => _hasWindowMaterial;
  static bool _hasWindowMaterial = false;

  /// How much of the chrome's own colour is laid over the window material:
  /// enough to keep text on the header and rail legible, little enough for
  /// the material (and the wallpaper behind it) to show.
  static const chromeOpacity = 0.25;

  /// Gives the window its platform material. Call once, before the first
  /// frame, after `windowManager.ensureInitialized()`. Failures leave the
  /// window opaque — the look is a nicety, never a reason not to start.
  static Future<void> applyWindowMaterial({required bool dark}) async {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    // Mica is Windows 11 only. On Windows 10 the effect call succeeds but
    // draws nothing, which would leave the see-through chrome over black.
    if (Platform.isWindows &&
        !supportsMica(windowsBuild(Platform.operatingSystemVersion))) {
      return;
    }
    try {
      await acrylic.Window.initialize();
      _hasWindowMaterial = true;
      await syncBrightness(dark: dark);
    } catch (e) {
      _hasWindowMaterial = false;
      debugPrint('[PlatformLook] window material failed: $e');
    }
  }

  /// The first Windows 11 build, where Mica arrived.
  static const firstMicaBuild = 22000;

  /// Whether a Windows [build] can draw Mica; an unknown build cannot.
  static bool supportsMica(int? build) =>
      build != null && build >= firstMicaBuild;

  /// The build number in `Platform.operatingSystemVersion` on Windows, such
  /// as 22631 in `"Windows 10 Pro" 10.0 (Build 22631)` (Windows 11 still
  /// reports itself as 10.0), or null if there is none.
  @visibleForTesting
  static int? windowsBuild(String operatingSystemVersion) {
    final match = RegExp(r'\(Build (\d+)\)').firstMatch(operatingSystemVersion);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Keeps the material's light or dark variant in step with the app's own
  /// theme, which can differ from the system's (Settings → Appearance).
  static Future<void> syncBrightness({required bool dark}) async {
    if (!_hasWindowMaterial) return;
    try {
      if (Platform.isMacOS) {
        await acrylic.Window.setEffect(effect: acrylic.WindowEffect.sidebar);
        await acrylic.Window.overrideMacOSBrightness(dark: dark);
      } else if (Platform.isWindows) {
        // Only reached on Windows 11: applyWindowMaterial skips Windows 10.
        await acrylic.Window.setEffect(
          effect: acrylic.WindowEffect.mica,
          dark: dark,
        );
      }
    } catch (e) {
      // Leave whatever the window had.
      debugPrint('[PlatformLook] setting the material failed: $e');
    }
  }

  /// The colour of the window's base layer (the scaffold, which shows in
  /// the gaps between panes), given its opaque colour: see-through over the
  /// window material when there is one, as is otherwise.
  static Color chromeColor(Color opaque) => _hasWindowMaterial
      ? opaque.withValues(alpha: opaque.a * chromeOpacity)
      : opaque;

  /// The colour of chrome drawn on top of that base layer (header, rail):
  /// clear over the window material, so the one tint below is all that
  /// covers it (two translucent layers stack to near-opaque), as is
  /// otherwise.
  static Color chromeOverlayColor(Color opaque) =>
      _hasWindowMaterial ? Colors.transparent : opaque;

  // ── Type ──────────────────────────────────────────────────────────────

  /// The UI font: the system's own on macOS (San Francisco, which Flutter
  /// picks when no family is set) and Windows (Segoe UI Variable on 11,
  /// Segoe UI before it); the bundled Inter on Linux, where the system font
  /// varies by distribution.
  static String? get uiFontFamily => switch (defaultTargetPlatform) {
    TargetPlatform.windows => 'Segoe UI Variable Text',
    TargetPlatform.macOS => null,
    _ => 'Inter',
  };

  static const uiFontFallback = ['Segoe UI'];

  /// Whether the platform's own font replaces the bundled Inter.
  static bool get usesSystemFont =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;

  // ── Shape ─────────────────────────────────────────────────────────────

  /// Corner radius of controls — fields, buttons, menus' items: 6 on macOS,
  /// 4 on Windows 11 (Fluent's control radius), 8 elsewhere.
  static double get controlRadius => switch (defaultTargetPlatform) {
    TargetPlatform.macOS => 6,
    TargetPlatform.windows => 4,
    _ => 8,
  };

  /// Corner radius of surfaces that float or frame — menus, dialogs, cards:
  /// 10 on macOS, 8 on Windows 11 (Fluent's overlay radius), 12 elsewhere.
  static double get surfaceRadius => switch (defaultTargetPlatform) {
    TargetPlatform.macOS => 10,
    TargetPlatform.windows => 8,
    _ => 12,
  };
}
