# CLAUDE.md

Eagly — a cross-platform **desktop** (macOS/Windows/Linux) log viewer for Android & iOS
devices. Streams `adb logcat` and `idevicesyslog`, plus screen mirror, file manager,
crash reports, app install, and wireless ADB. Flutter app; Dart package name and repo
dir are both **`eagly`**, so imports are `package:eagly/...`.

## Commands

This repo pins Flutter via **fvm** (`.fvmrc` → 3.41.7). Always prefix with `fvm`:

```bash
fvm flutter run -d macos        # run (also: windows / linux)
fvm flutter test                # all tests
fvm flutter test test/log_controller_test.dart
fvm flutter analyze lib test    # lints (flutter_lints; clean except 1 known deprecation)
fvm dart format <files>         # format before finishing; CI-style 80-col wrapping
```

Bundled CLI tools (`adb`, `libimobiledevice`, `scrcpy-server`) live under
`platform-tools/<os>/` and are resolved at runtime by `lib/utils/tools_path.dart`. They
are **not** on PATH — never assume a system `adb`. `scripts/download_platform_tools.sh`
fetches them.

## Architecture

Strict layered ownership, no DI framework — plain `ChangeNotifier` + `ListenableBuilder`/
`AnimatedBuilder`. `DeviceSessionManager` is created in `HomePage`'s State and passed down
by constructor; `DevicesRepository.instance` is the one singleton.

```
tools (process wrappers)         services/tools/*  — AdbTool, IdeviceSyslogTool, … extend ToolProcessRunner
  └─ device facade               services/device_session_repository.dart — per-device, wraps all tools
discovery                        services/devices_repository.dart (DevicesRepository) — adb/idevice polling + track-devices
app coordinator                  session/device_session_manager.dart — one DeviceSessionController per device, tab order, selection
per-device session               session/device_session_controller.dart — owns the live Device + feature controllers (lazy)
per-feature controllers          session/feature_controller.dart (base) → LogController, MirrorController, CrashReportController, FileManagerController
views                            features/<feature>/..._feature_view.dart
```

**Connectivity flow (important):** `DevicesRepository` produces `Device`s with a
`DeviceConnectionState`. `DeviceSessionManager._sync` pushes updates via
`DeviceSessionController.updateDevice`, which `notifyListeners()`. `FeatureController`
listens and turns connect/disconnect transitions into `onDeviceConnected()` /
`onDeviceDisconnected()` hooks — features never talk to each other directly.

## Domain notes

- **Log streaming:** `DeviceSessionRepository.startLogStream()` is an `async*` that yields
  `LogEntry`s; the underlying tool's `StreamController` closing ⇒ stream EOF. `LogController`
  buffers into a `LogBuffer` (ring), flushing pending logs on a 300 ms timer.
- **`LogEntry`:** `type == LogEntryType.log` is a real device line; all other types
  (`started`/`paused`/`stopped`/`resumed`/`notice`/`error`) are *special* status entries
  rendered inline and skipped by copy/selection. Build them via `LogEntryUtils`.
- **Stall recovery (LogController):** the live stream can die silently (logcat EOF) or
  wedge (no EOF, device still listed). Detection = `onDone`/`onError` + an Android-only
  watchdog that actively probes (`service.pingDevice()`). Recovery is **tiered**: gentle
  restart → `adb reconnect` → full-width warning banner with Restart/New-tab. Recovery
  **preserves** captured logs; only a fresh user `startLogcat()` clears them. iOS relies on
  stream EOF (no cheap liveness probe).
- **Device statuses:** Android is connected only when `adb` status == `device` (offline/
  unauthorized ⇒ disconnected). iOS presence in `idevice_id -l` ⇒ connected.
- **Multiple log tabs** per device via `LogSessionManager` (first live tab is permanent;
  extra live + imported tabs allowed).
- **App install & drag-and-drop:** `DeviceSessionController.handleDroppedPaths()` routes
  dropped paths — installable bundles (`.apk` on Android / `.ipa` on iOS, classified by
  `AppInstallService.inferSupportedPlatform`) go to `installAppFromPath()`; everything else
  is copied onto the device via `FileManagerController.copyExternalFiles()`. Installs run
  one-at-a-time behind a per-device guard.
- **Imported logs workspace:** opening a log file with no device hosts it in a single
  synthetic `DeviceSessionController` (`isImportedWorkspace`, id `__imported-logs__`); each
  file becomes a sub-tab. It appears as a tab but is excluded from the landing-screen
  device list.

## Conventions

- Match surrounding style: terse doc comments on public/non-obvious members, `// ──` section
  dividers, private helpers prefixed `_`, `unawaited(...)` for fire-and-forget futures.
- Theme tokens come from the `EaglyTheme` extension: `context.eaglyTheme.<token>` (status
  colors, `warningColor`, `inlineNotice*`). Don't hardcode colors.
- Tests live in `test/` (mirrors feature names). Shared fakes in
  `test/support/session_test_support.dart` (`FakeSessionService`, `FakeAdbTool`, …). Tunable
  timing constants are exposed as `@visibleForTesting static` fields (e.g.
  `LogController.recoveryBackoff`) — set in `setUp`, reset in `tearDown`.
- Commit/push only when asked; branch off `main` first.
