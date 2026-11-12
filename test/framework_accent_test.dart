import 'dart:math' as math;

import 'package:eagly/features/logs/data/models/log_framework.dart';
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

/// The distance between two hues on the colour wheel, in degrees.
double _hueDistance(Color a, Color b) {
  final d = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs();
  return math.min(d, 360 - d);
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final (name, themeOf) in [
    ('light', () => AppTheme.lightTheme),
    ('dark', () => AppTheme.darkTheme),
  ]) {
    // testWidgets, not test: building the theme starts google_fonts loads
    // (see test/text_emphasis_test.dart).
    testWidgets('$name: every framework accent reads as chip text', (_) async {
      final theme = themeOf();
      final scheme = theme.colorScheme;
      final tokens = theme.extension<EaglyTheme>()!;
      for (final framework in LogFramework.values) {
        expect(
          tokens.frameworkAccentColors,
          contains(framework),
          reason: '$framework has no accent',
        );
        final accent = tokens.frameworkColor(framework);
        // The chips sit on the pane's surface; a show-only chip fills
        // itself with the accent at 16%.
        final onlyFill = Color.alphaBlend(
          accent.withValues(alpha: 0.16),
          scheme.surface,
        );
        for (final (surfaceName, surface) in [
          ('surface', scheme.surface),
          ('surfaceContainer', scheme.surfaceContainer),
          ('show-only fill', onlyFill),
        ]) {
          expect(
            _contrast(accent, surface),
            greaterThan(4.5),
            reason: '$framework on $surfaceName',
          );
        }
      }
    });

    testWidgets('$name: Flutter and React Native are told apart', (_) async {
      final tokens = themeOf().extension<EaglyTheme>()!;
      expect(
        _hueDistance(
          tokens.frameworkColor(LogFramework.flutter),
          tokens.frameworkColor(LogFramework.reactNative),
        ),
        greaterThan(25),
      );
    });
  }
}
