import '../../features/app_log/app_logger.dart';
import '../../src/rust/frb_generated.dart';

/// Loads the `rust_lib_eagly` native library behind the `Rust*` iOS services,
/// and reports whether it loaded.
///
/// Skipped when `EAGLY_IOS_BACKEND=cli` selects the CLI fallback. A failure
/// (a missing library, or bindings whose content hash no longer matches) is
/// logged rather than thrown, so the app stays usable: `initIosBackend` falls
/// back to the CLIs for the rest of the session.
Future<bool> initRustIosRuntime() async {
  try {
    await RustLib.init();
    return true;
  } catch (error) {
    AppLogger(source: 'RustIosRuntime').error(
      'Failed to load the Rust iOS backend; falling back to the CLI tools',
      detail: error.toString(),
    );
    return false;
  }
}
