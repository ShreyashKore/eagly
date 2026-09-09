import 'dart:io';

/// Selects which implementation the `services/ios` factories hand back.
///
/// Defaults to the shipped libimobiledevice CLIs. Set `EAGLY_IOS_BACKEND=rust`
/// to exercise the `idevice` Rust crate instead — an environment variable
/// rather than a setting because this is a migration aid for developers, not a
/// user-facing choice, and it should disappear once the migration lands.
///
/// See docs/IOS_RUST_MIGRATION.md.
bool get useRustIosBackend =>
    Platform.environment['EAGLY_IOS_BACKEND'] == 'rust';
