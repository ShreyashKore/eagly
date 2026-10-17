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

// Where text actually sits: cards, feature panes, and the raised strips
// inside them (search bars, result panels).
final _surfaces = <String, Color Function(ColorScheme)>{
  'surface': (scheme) => scheme.surface,
  'surfaceContainer': (scheme) => scheme.surfaceContainer,
  'surfaceContainerHighest': (scheme) => scheme.surfaceContainerHighest,
};

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final (name, themeOf) in [
    ('light', () => AppTheme.lightTheme),
    ('dark', () => AppTheme.darkTheme),
  ]) {
    group('$name text emphasis', () {
      for (final MapEntry(key: surfaceName, value: surfaceOf)
          in _surfaces.entries) {
        // testWidgets, not test: building the theme starts google_fonts
        // loads, which fail loudly in a real zone and never settle in the
        // fake-async one.
        late ColorScheme scheme;
        late EaglyTheme tokens;
        late Color surface;
        void load() {
          final theme = themeOf();
          scheme = theme.colorScheme;
          tokens = theme.extension<EaglyTheme>()!;
          surface = surfaceOf(scheme);
        }

        testWidgets('every tier meets WCAG AA on $surfaceName', (_) async {
          load();
          expect(_contrast(scheme.onSurface, surface), greaterThan(4.5));
          expect(
            _contrast(tokens.secondaryTextColor, surface),
            greaterThan(4.5),
          );
          expect(
            _contrast(tokens.tertiaryTextColor, surface),
            greaterThan(4.5),
          );
        });

        testWidgets('the tiers are visibly apart on $surfaceName', (_) async {
          load();
          final primary = _contrast(scheme.onSurface, surface);
          final secondary = _contrast(tokens.secondaryTextColor, surface);
          final tertiary = _contrast(tokens.tertiaryTextColor, surface);
          // Each step drops the contrast by at least a fifth; closer than
          // that and the eye stops ranking them.
          expect(secondary, lessThan(primary * 0.8));
          expect(tertiary, lessThan(secondary * 0.8));
        });
      }
    });
  }
}
