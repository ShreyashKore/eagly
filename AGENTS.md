# AGENTS.md

Eagly — a cross-platform **desktop** (macOS/Windows/Linux) log viewer for Android & iOS
devices. Streams `adb logcat` and `idevicesyslog`, plus screen mirror, file manager,
crash reports, app install, device utilities, and wireless ADB. Flutter app; Dart package
name and repo dir are both **`eagly`**, so imports are `package:eagly/...`.

## Commands

This repo pins Flutter via **fvm** (`.fvmrc` → 3.47.0). Always prefix with `fvm`:

```bash
fvm flutter run -d macos        # run (also: windows / linux)
fvm flutter test                # all tests
fvm flutter test test/log_controller_test.dart
fvm flutter analyze lib test    # lints (flutter_lints; clean except 1 known deprecation)
fvm dart format .               # format the whole project; CI-style 80-col wrapping
fvm dart format --output=none --set-exit-if-changed .   # what CI gates on
```

Formatting is enforced, not advisory: `.githooks/pre-commit` formats staged Dart
and re-stages it (a *partially* staged file is reported instead of rewritten, so
the hook can't sweep unstaged hunks into your commit), and CI fails on any
unformatted file. `scripts/setup.sh` points git at the hooks; in an existing
clone run `git config core.hooksPath .githooks` once. `--no-verify` bypasses it.

**Verifying the scrcpy wire protocol.** `scrcpy-server` is a *versioned binary
protocol*, and guessing at it produces bugs that look like device quirks. The
bundled jar is the spec: unzip it and read the message framing off
`ControlMessageReader` / `Controller`, then confirm end-to-end on a device.

```bash
unzip -o platform-tools/macos/scrcpy-server -d /tmp/srv   # classes.dex
"$ANDROID_HOME"/build-tools/*/dexdump -d /tmp/srv/classes.dex > /tmp/srv/dump.txt
# `read()`'s packed-switch maps message type → parse method; each parse* method
# spells out the field widths (readUnsignedByte / readInt / readLong).
```

This is how the payload caps below were pinned (they are *not* the values older
scrcpy docs quote), and how the keyboard work was checked: drive a real device
from a throwaway `dart run` harness against `ScrcpyClient`, then read the result
back with `adb shell uiautomator dump` rather than trusting that a message
"looks right".

Bundled CLI tools (`adb`, `libimobiledevice`, `scrcpy-server`) live under
`platform-tools/<os>/` and are resolved at runtime by `lib/utils/tools_path.dart`. They
are **not** on PATH — never assume a system `adb`. The whole libimobiledevice suite ships,
not just the tools with a dedicated wrapper: `idevicediagnostics`, `idevicescreenshot`,
`idevicedate`, `idevicename`, `idevicepair`, `idevicesetlocation`, `idevicebackup2`, … —
reach for one before concluding an Android feature has no iOS counterpart.

Dev scripts (`scripts/`):

- `setup.sh` — one-shot first-time onboarding: validates the toolchain, installs platform
  build deps, downloads the bundled tools, and runs `pub get` (`--packaging` also installs
  Fastforge). See `docs/SETUP.md`.
- `download_platform_tools.sh <os…>` — fetches `adb`/`libimobiledevice`; on Linux it also
  invokes `build_linux_ffmpeg.sh`, on Windows it fetches the FFmpeg dev libs.
- `build_linux_ffmpeg.sh` — builds the minimal, glibc-only H.264 FFmpeg bundled for the
  native scrcpy decoder into `.ffmpeg-dev/linux/` (keeps the `.deb` distro-independent).
- `copy_macos_bundled_tools.sh` — stages the bundled tools into the macOS build.

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
per-feature controllers          session/feature_controller.dart (base) → LogController, MirrorController, CrashReportController, FileManagerController, UtilitiesController, TerminalController
views                            features/<feature>/..._feature_view.dart — extend presentation/components/feature_view.dart (FeatureView)
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
- **Screen captures:** screenshots and `screenrecord` videos taken from the mirror pane
  go straight to a capture folder — `CaptureStorage` (`features/mirror/services/`), default
  `<Pictures>/Eagly`, overridable in Settings — under a timestamped, de-duplicated name.
  No save dialog unless `PreferencesService.captureAskEveryTime` is on. The confirmation
  uses `showSavedFileSnackBar`, whose Open / Show-in-folder actions go through
  `utils/file_reveal.dart` (`open -R` / `explorer /select,` / `xdg-open` on the parent).
- **Mirror input:** touches, keys and clipboard all ride the scrcpy *control*
  socket (`ScrcpyControl`, opened only when `ScrcpyVideoOptions.control`). Keyboard
  forwarding is **focus-gated**: `MirrorController.keyboardFocusNode` is handed to
  `ScrcpyView`, clicking the surface takes focus, and only then do key events go to
  the device — that focus is also what stops the host beeping at "unhandled" keys,
  since a forwarded key is reported as `KeyEventResult.handled`.
  `ScrcpyKeyboardTranslator` decides *how* each key travels: a printable character
  goes as **INJECT_TEXT** (the desktop keymap already resolved the layout, so a
  non-QWERTY host types what its keys say), everything else as an **INJECT_KEYCODE**
  down/up pair carrying an Android `META_*` bitmask. It remembers what it pressed so
  a key-up is only sent for a key-down it actually sent, and `releaseAll()` unsticks
  held keys when focus is lost. On macOS ⌘ stands in for the device's Ctrl, but only
  for `{A, C, V, X, Z}` — every other ⌘ chord is returned as *unhandled* so ⌘Q/⌘W
  still belong to the app. ⌘/Ctrl+V pushes the *desktop* clipboard with
  `SET_CLIPBOARD(paste: true)` rather than injecting a keycode; the device would
  otherwise paste its own clipboard. Server-side payload caps are real and differ
  (clipboard 262130 bytes, inject-text 300 — longer text is chunked on UTF-8
  boundaries). Device→desktop clipboard mirroring stays on by default, minus the
  echo of our own push.
- **App install & drag-and-drop:** `DeviceSessionController.handleDroppedPaths()` routes
  dropped paths — installable bundles (`.apk` on Android / `.ipa` on iOS, classified by
  `AppInstallService.inferSupportedPlatform`) go to `installAppFromPath()`; everything else
  is copied onto the device via `FileManagerController.copyExternalFiles()`. Installs run
  one-at-a-time behind a per-device guard.
- **Utilities feature:** a declarative catalog (`features/utilities/data/utility_catalog.dart`)
  of curated `adb` / `adb shell` commands with a libimobiledevice equivalent where one
  exists. Each `UtilityCommand` owns its label, params, confirmation text and a
  **per-platform builder** returning a `UtilityInvocation` (tool + args) or `null` when
  that platform has no equivalent — that null is the *only* platform switch in the
  feature, so `UtilitiesController` and the view never mention a command or a platform.
  Invocations run through `DeviceSessionRepository.runUtility()`, which prepends the
  tool's device selector (`adb -s` / `idevice* -u`) and runs it via
  `ToolProcessRunner.runTextWithTimeout` (killable, unlike `Process.run`). Adding a
  command = one entry in the catalog. `adb shell` scripts are sent as a single argument
  and evaluated by the *device's* `sh` (no host shell); quote user input with
  `shellQuote()`. Two optional fields make a command *app-targeted*:
  `packageParamKey` names the param that takes a package name, which is what
  puts the command on the Apps pane's right-click menu (pre-filled with the
  clicked app — see `features/apps/components/app_utility_menu.dart`), and
  `systemAppSafe` opts it in for preinstalled packages. It defaults to false,
  so a new app command is refused on system apps until it says otherwise;
  only read-only ones opt in. Params whose useful values are known but not
  exhaustive (permissions, `dumpsys` services, screen sizes) use
  `UtilityParam.suggestion` with a list from
  `features/utilities/data/utility_suggestions.dart` — a text field with a
  dropdown, never a whitelist.
- **Terminal feature:** free-form `adb` / libimobiledevice command entry, multi-tab like
  Logs (`TerminalSessionManager`; first tab permanent). Each `TerminalController` owns a
  scrollback, a history and a *target device*, and the point of the feature is that the
  device selector is implicit: `features/terminal/data/terminal_tools.dart` holds the table
  of dispatchable CLIs (executable, `deviceFlag`, the flags that already select a device,
  and the host-side subcommands that take none), and `TerminalTool.argumentsFor()` prepends
  `-s <serial>` / `-u <udid>` unless the line already targets something. A line naming no
  known tool becomes `adb shell <line>` on Android (one argument, evaluated by the
  *device's* `sh`); iOS has no shell so the user is pointed at `tools`. `@<device> <cmd>`
  aims one line elsewhere, `use <device>` pins the whole tab. Built-ins (`help`, `clear`,
  `devices`, `use`, `tools`, `history`) never start a process. Processes run through
  `DeviceSessionRepository.startTerminalProcess()`, which owns startup/merging/teardown
  only — no timeout (`adb logcat` may stream forever), stdin is writable, and cancellation
  is the caller's job. Adding a dispatchable binary = one entry in `terminalTools`.
- **Wireless ADB:** one dialog (`features/wireless_connection/`) with two panes — **Pair a
  device** (QR card pinned on top, discovered devices scrolling under it) and **Manual
  entry**. The whole pane is driven by *one* background mDNS scan
  (`WirelessConnectionController._runScanLoop`) that both refreshes the nearby list and
  watches for the QR code being scanned; there is no separate "discover" action.
  - **How QR pairing actually works:** the payload `WIFI:T:ADB;S:<name>;P:<password>;;` is
    generated *by us* — a random service name and password, no device involved. After the
    device scans it, it starts advertising an mDNS **pairing** service whose name equals
    the name we embedded; the scan loop matches on that name and calls
    `adb pair <host:port> <password>`. So generating a code is pure local computation and
    must never be gated on discovery — that was the original bug.
  - **Gotcha — the retry loop:** `DevicesRepository.discoverMdnsServices()` defaults to
    `retry: true`, polling up to `_mdnsRetryCountMax × _mdnsRetryInterval` (20 × 500 ms ≈
    10 s) until something appears. Right for a one-shot; fatal inside a poll loop. The scan
    loop passes `retry: false` and paces itself with
    `WirelessConnectionController.scanInterval`.
  - **Gotcha — `isWirelessBusy` must stay narrow:** it means *pairing or connecting* only.
    Folding the passive scan back into it re-creates the original starvation (a discovery
    in flight refusing QR generation for ~10 s). The scan loop instead *skips a pass* while
    busy, so two adb invocations never contend.
  - The QR code has no server-side expiry (it is our own random string), so there is no
    scan timeout — only leaving the pane or an adb failure stops the loop. It *is*
    single-use: after a pair attempt consumes it, `regenerateQrCode()` publishes a new one
    unless the flow reached a connected device.
  - `_scanGeneration` invalidates in-flight loops: `stopScanning()`/`dispose()` bump it so a
    loop parked in `Future.delayed(scanInterval)` returns instead of resuming. The dialog
    **must** dispose the controller (it did not before) or the loop outlives it.
  - The loop notifies listeners only when the service list actually changed — at ~1 Hz an
    unconditional `notifyListeners()` rebuilds the dialog (and its text fields) constantly.
  - Pairing yields a *pairing* port; connecting needs the separate *connect* port, resolved
    from the same mDNS snapshot (`_resolveWirelessConnectAddresses`). Pair auto-continues
    into connect when a connect endpoint is known, which is why `WirelessPairResult`
    distinguishes `paired` from `autoConnected`.
  - Device-side realities worth telling the user (the `HintNote`s do): the device's pairing
    screen must stay open or it stops advertising, and client-isolating networks (guest or
    public Wi-Fi) block mDNS entirely — Manual entry is the escape hatch.
- **Imported logs workspace:** opening a log file with no device hosts it in a single
  synthetic `DeviceSessionController` (`isImportedWorkspace`, id `__imported-logs__`); each
  file becomes a sub-tab. It appears as a tab but is excluded from the landing-screen
  device list.

## Conventions

- **Agent skills live in `.agents/skills/<name>/SKILL.md`** — that directory is
  the source of truth, and `.claude/skills` is a symlink to it so Claude Code
  reads the same files with nothing to sync. Wire a new agent up with another
  symlink (`ln -s ../.agents/skills .<agent>/skills`); never copy the files.
  See `.agents/skills/README.md`.
- **This file is the only copy of the project instructions.** `CLAUDE.md` is a
  nine-line pointer to it — write changes here, and never copy content back
  there. The two were byte-copies once and drifted 35 lines apart before anyone
  noticed.
- Match surrounding style: terse doc comments on public/non-obvious members, `// ──` section
  dividers, private helpers prefixed `_`, `unawaited(...)` for fire-and-forget futures.
- Theme tokens come from the `EaglyTheme` extension: `context.eaglyTheme.<token>` (status
  colors, `warningColor`, `inlineNotice*`). Don't hardcode colors.
- Explanations for a user who looks stuck go in a `HintNote`
  (`presentation/components/hint_note.dart`) wrapped in a `DelayedReveal`
  (`presentation/components/delayed_reveal.dart`): the note is not built at all until the
  operation has visibly dragged on, so the common path stays uncluttered.
- Tests live in `test/` (mirrors feature names). Shared fakes in
  `test/support/session_test_support.dart` (`FakeSessionService`, `FakeAdbTool`, …). Tunable
  timing constants are exposed as `@visibleForTesting static` fields (e.g.
  `LogController.recoveryBackoff`) — set in `setUp`, reset in `tearDown`.
- Widget-testing anything with a spinner or a background poll (see
  `test/wireless_connection_dialog_test.dart`): `pumpAndSettle` **never** returns while a
  `CircularProgressIndicator` is on screen — advance with explicit `pump(duration)`. The
  pending-timer check runs when the test *body* ends, before `tearDown`, so tear the widget
  down inside the body and pump past any parked interval. `AnimatedSection` keeps its child
  mounted at `heightFactor: 0`, so `find.text` still matches a "hidden" child — hide by not
  building the child (what `DelayedReveal` does via `AnimatedContent`).
- Commit/push only when asked; branch off `main` first.
- Never discard uncommitted working-tree changes you didn't just make (`git checkout --`,
  `git restore`, `stash drop`, etc.) — even if they look stray or unrelated to the current
  task. Treat any pre-existing uncommitted edit as the user's in-progress work; ask before
  touching it. (Incident: `README.md` edits were wiped twice this way and nearly lost.)
