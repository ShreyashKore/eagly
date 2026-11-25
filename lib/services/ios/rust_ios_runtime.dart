import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

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
    await RustLib.init(externalLibrary: openBundledRustLibrary());
    return true;
  } catch (error) {
    AppLogger(source: 'RustIosRuntime').error(
      'Failed to load the Rust iOS backend; falling back to the CLI tools',
      detail: error.toString(),
    );
    return false;
  }
}

/// flutter_rust_bridge's own override for where the library is.
const _libraryDirVariable = 'FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR';

/// Opens the library the build hook bundled with the app, or null to leave
/// the search to flutter_rust_bridge: when nothing is bundled, or when its
/// directory override is set.
///
/// The bridge on its own looks in `<cwd>/rust/target/release/` first. A dev
/// run starts in the repo root, where that holds whatever the last manual
/// `cargo build --release` left; the hook builds elsewhere and never
/// refreshes it, so it goes stale and fails the content-hash check.
@visibleForTesting
ExternalLibrary? openBundledRustLibrary({
  Map<String, String>? environment,
  String? operatingSystem,
  ExternalLibrary Function(String name) open = ExternalLibrary.open,
}) {
  if ((environment ?? Platform.environment).containsKey(_libraryDirVariable)) {
    return null;
  }
  final name = switch (operatingSystem ?? Platform.operatingSystem) {
    'macos' => 'rust_lib_eagly.framework/rust_lib_eagly',
    'linux' => 'librust_lib_eagly.so',
    'windows' => 'rust_lib_eagly.dll',
    _ => null,
  };
  if (name == null) return null;
  try {
    return open(name);
  } on ArgumentError {
    return null;
  }
}
