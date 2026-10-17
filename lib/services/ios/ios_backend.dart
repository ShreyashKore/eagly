import 'dart:io';

import 'rust_ios_runtime.dart';

/// Selects which implementation the `services/ios` factories hand back.
///
/// Defaults to the `idevice` Rust crate. Set `EAGLY_IOS_BACKEND=cli` to fall
/// back to the shipped libimobiledevice CLIs — an environment variable
/// rather than a setting because this is a migration aid for developers, not a
/// user-facing choice, and it should disappear once the migration lands.
///
/// See docs/IOS_RUST_MIGRATION.md.
bool get useRustIosBackend =>
    Platform.environment['EAGLY_IOS_BACKEND'] != 'cli';

/// Prepares the selected backend. Only the Rust one has anything to load.
Future<void> initIosBackend() async {
  if (useRustIosBackend) await initRustIosRuntime();
}
