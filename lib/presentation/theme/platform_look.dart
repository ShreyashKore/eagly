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
  static const chromeOpacity = 0.55;

  /// Gives the window its platform material. Call once, before the first
  /// frame, after `windowManager.ensureInitialized()`. Failures leave the
  /// window opaque — the look is a nicety, never a reason not to start.
  static Future<void> applyWindowMaterial({required bool dark}) async {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    try {
      await acrylic.Window.initialize();
      _hasWindowMaterial = true;
      await syncBrightness(dark: dark);
    } catch (_) {
      _hasWindowMaterial = false;
    }
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
        // Mica needs Windows 11; on Windows 10 the call does nothing visible
        // and the translucent chrome falls back to the window's own colour.
        await acrylic.Window.setEffect(
          effect: acrylic.WindowEffect.mica,
          dark: dark,
        );
      }
    } catch (_) {
      // Leave whatever the window had.
    }
  }

  /// The colour of window chrome — header, rail, the gaps between panes —
  /// given its opaque colour: see-through over the window material when
  /// there is one, as is otherwise.
  static Color chromeColor(Color opaque) => _hasWindowMaterial
      ? opaque.withValues(alpha: opaque.a * chromeOpacity)
      : opaque;

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
