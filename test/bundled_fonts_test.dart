import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/presentation/theme/bundled_fonts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app never downloads fonts (FLUTTER-17, FLUTTER-C9), so every Google
/// Fonts variant the theme asks for has to be in `assets/fonts/`. A missing
/// one throws at runtime instead of falling back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every font the theme uses loads from the bundle', () async {
    useBundledFonts();
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);

    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      expect(theme.textTheme.bodyMedium?.fontFamily, startsWith('Inter'));
      expect(
        theme.extension<EaglyTheme>()?.monoStyle.fontFamily,
        startsWith('JetBrainsMono'),
      );
    }
    await expectLater(GoogleFonts.pendingFonts(), completes);
  });

  test('the font licenses are registered', () async {
    useBundledFonts();
    final packages = <String>{};
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
    }
    expect(packages, containsAll(['Inter', 'JetBrains Mono']));
  });
}
