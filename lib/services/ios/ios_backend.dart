import 'dart:io';

import 'package:flutter/foundation.dart';

import 'rust_ios_runtime.dart';

/// Selects which implementation the `services/ios` factories hand back.
///
/// Defaults to the `idevice` Rust crate. Set `EAGLY_IOS_BACKEND=cli` to fall
/// back to the shipped libimobiledevice CLIs — an environment variable
/// rather than a setting because this is a migration aid for developers, not a
/// user-facing choice, and it should disappear once the migration lands. The
/// CLIs are also used when the Rust library fails to load, so a broken build
/// degrades to the old backend instead of losing every iOS surface.
///
/// See docs/IOS_RUST_MIGRATION.md.
bool get useRustIosBackend =>
    !rustIosRuntimeFailed && Platform.environment['EAGLY_IOS_BACKEND'] != 'cli';

/// Whether [initIosBackend] tried to load the Rust library and failed.
@visibleForTesting
bool rustIosRuntimeFailed = false;

/// Prepares the selected backend. Only the Rust one has anything to load.
Future<void> initIosBackend() async {
  if (useRustIosBackend) rustIosRuntimeFailed = !await initRustIosRuntime();
}
