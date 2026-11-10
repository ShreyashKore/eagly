import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Serves the theme's Google Fonts from the app bundle, never the network.
///
/// `assets/fonts/` holds every variant [AppTheme] asks for: Inter 400, 500,
/// 600 and 700, and JetBrains Mono 400. They are the files google_fonts would
/// download (`fonts.gstatic.com/s/a/<hash>.ttf`), byte for byte, named so it
/// finds them in the asset manifest first.
///
/// Fetching at runtime failed two ways: users who can't reach
/// fonts.gstatic.com got fallback fonts and an error (FLUTTER-17), and on
/// Windows saving the download to the app support folder threw "access
/// denied" when the file was in use (FLUTTER-C9). A variant the theme starts
/// asking for must be added to `assets/fonts/` too; with fetching off, a
/// missing one throws — `test/bundled_fonts_test.dart` catches that.
void useBundledFonts() {
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in const [
      ('Inter', 'Inter-OFL.txt'),
      ('JetBrains Mono', 'JetBrainsMono-OFL.txt'),
    ]) {
      final text = await rootBundle.loadString('assets/fonts/$file');
      yield LicenseEntryWithLineBreaks([family], text);
    }
  });
}
