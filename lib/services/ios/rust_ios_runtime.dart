import '../../features/app_log/app_logger.dart';
import '../../src/rust/frb_generated.dart';

/// Loads the `rust_lib_eagly` native library behind the `Rust*` iOS services.
///
/// Skipped when `EAGLY_IOS_BACKEND=cli` selects the CLI fallback, so a build
/// without the library (or with mismatched bindings) can still reach iOS
/// devices that way. A failure is logged rather than thrown: the app stays
/// usable, and each `Rust*` call reports its own error.
Future<void> initRustIosRuntime() async {
  try {
    await RustLib.init();
  } catch (error) {
    AppLogger(
      source: 'RustIosRuntime',
    ).error('Failed to load the Rust iOS backend', detail: error.toString());
  }
}
