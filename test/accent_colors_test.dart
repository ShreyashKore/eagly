import 'dart:math' as math;

import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// WCAG 2.x contrast ratio of [foreground] composited over [background].
double _contrast(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background);
  final a = fg.computeLuminance();
  final b = background.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// CIE L*a*b* of an opaque sRGB colour (D65).
List<double> _lab(Color color) {
  double linear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4) * 1.0;
  final r = linear(color.r), g = linear(color.g), b = linear(color.b);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3) * 1.0 : 7.787 * t + 16 / 116;
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

/// CIE76 colour difference: around 2 is a just-noticeable step, past 20
/// two colours read as different ones.
double _deltaE(Color a, Color b) {
  final la = _lab(a), lb = _lab(b);
  return math.sqrt(
    math.pow(la[0] - lb[0], 2) +
        math.pow(la[1] - lb[1], 2) +
        math.pow(la[2] - lb[2], 2),
  );
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final (name, themeOf) in [
    ('light', () => AppTheme.lightTheme),
    ('dark', () => AppTheme.darkTheme),
  ]) {
    // testWidgets, not test: building the theme starts google_fonts loads
    // (see test/text_emphasis_test.dart).
    testWidgets('$name: the accent never reads as a warning', (_) async {
      final theme = themeOf();
      final accent = theme.colorScheme.primary;
      final tokens = theme.extension<EaglyTheme>()!;
      for (final (role, color) in [
        ('warning', tokens.warningColor),
        ('paused', tokens.statusPausedColor),
        ('error', tokens.errorColor),
      ]) {
        expect(_deltaE(accent, color), greaterThan(20), reason: role);
      }
    });

    testWidgets('$name: the accent holds AA as text and as a fill', (_) async {
      final scheme = themeOf().colorScheme;
      expect(_contrast(scheme.onPrimary, scheme.primary), greaterThan(4.5));
      for (final surface in [
        scheme.surface,
        scheme.surfaceContainer,
        scheme.surfaceContainerHighest,
      ]) {
        expect(_contrast(scheme.primary, surface), greaterThan(4.5));
      }
    });
  }
}
