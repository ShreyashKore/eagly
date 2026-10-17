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
(`dart format`) and Rust (`rustfmt` over stdin, one file at a time — `cargo fmt`
would reformat the whole crate under `rust/`) and re-stages it (a *partially*
staged file is reported instead of rewritten, so the hook can't sweep unstaged
hunks into your commit), and CI fails on any unformatted file.
`scripts/setup.sh` points git at the hooks; in an existing
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

The **Android SDK is the opposite case**: `emulator` and `avdmanager` are *not* bundled — they
are part of a multi-gigabyte Android Studio install, so Eagly locates an SDK the machine
already has (`lib/utils/android_sdk_path.dart`, overridable in **Settings → Android SDK**).
Environment variables alone are not enough to find it: an app launched from Finder or the Start
menu inherits the login environment, not a shell's, and `ANDROID_HOME`/`ANDROID_SDK_ROOT` are
usually unset even on machines where Android Studio works fine — hence the list of well-known
install roots that `AndroidSdkPath.candidateSdkRoots()` probes, and the manual override.

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
iOS backends                     services/ios/* — IosDeviceService, one interface over the bundled
                                 libimobiledevice CLIs and the `idevice` Rust crate (docs/IOS_RUST_MIGRATION.md)
discovery                        services/devices_repository.dart (DevicesRepository) — adb/idevice polling + track-devices
app coordinator                  session/device_session_manager.dart — one DeviceSessionController per device, tab order, selection
per-device session               session/device_session_controller.dart — owns the live Device + feature controllers (lazy)
per-feature controllers          session/feature_controller.dart (base) → LogController, MirrorController, CrashReportController, FileManagerController, UtilitiesController, TerminalController
views                            features/<feature>/..._feature_view.dart — extend presentation/components/feature_view.dart (FeatureView)
```

**iOS backends (migration in progress):** every iOS surface is moving from the bundled
libimobiledevice CLIs to the `idevice` Rust crate, called through flutter_rust_bridge. Both
implementations live behind an interface in `services/ios/`; Rust is the default and
`EAGLY_IOS_BACKEND=cli` falls back to libimobiledevice. The interface speaks domain types — only the
`Rust*` implementation may import `lib/src/rust/**`, which is generated and never edited by hand.
**The libimobiledevice CLIs and friends will be removed in a future version**, so new iOS work
goes on the Rust side first; keep the CLI path correct while it ships, but don't extend it.
See **docs/IOS_RUST_MIGRATION.md** before touching either side.

**Connectivity flow (important):** `DevicesRepository` produces `Device`s with a
`DeviceConnectionState`. `DeviceSessionManager._sync` pushes updates via
`DeviceSessionController.updateDevice`, which `notifyListeners()`. `FeatureController`
listens and turns connect/disconnect transitions into `onDeviceConnected()` /
`onDeviceDisconnected()` hooks — features never talk to each other directly.

## Domain notes

- **Log streaming:** `DeviceSessionRepository.startLogStream()` is an `async*` that yields
  `LogEntry`s; the underlying tool's `StreamController` closing ⇒ stream EOF. `LogController`
  buffers into a `LogBuffer` (ring), flushing pending logs on a 300 ms timer. **Read
  docs/LOG_STREAMING.md before touching parsing or flushing** — it lists the guarantees (no
  lost, split or reordered lines) and the tests that enforce them. The rules most easily
  broken: Android uses `adb logcat -v long` (never `threadtime`, which splits multi-line
  messages); parsers implement `LogLineParser`, and a line-based source goes through
  `parseLogLines` while the Rust iOS relay, which sends whole messages, goes through
  `parseLogRecords`; and special entries must flush `LogController`'s queue before they are
  appended. Run `test/device/log_stream_integrity_test.dart` against real devices before
  changing the pipeline.
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
- **Hidden columns persist across tabs and launches** unless the user opts out
  (`PreferencesService.rememberHiddenColumns`, default on; toggled from the column popup's
  last row and in Settings). The write happens in `LogViewer`'s popup handler, not in
  `LogController` — the controller only holds per-tab state. Opting back in saves the
  current tab's set; opting out leaves the stored default alone.
- **Log filter row:** `LogFilterArea` puts the filter on the left and the always-visible
  search (`LogSearchField`: highlight and step through matches, hides nothing) on the right,
  so neither is buried; the toolbar has no search button and there is no floating search
  box. ⌘F focuses search through `LogController.searchFocusNode`; ⌘L focuses the filter
  field (`LogController.activateFilterInput`). There is one filter bar — the inline
  `key:value` bar and its mode toggle / Settings choice are gone; don't bring back a second
  one.
- **Log filter bar:** it edits one `LogFilters` (per-field `FilterTerm` lists — each
  term has a match mode and negation, all ANDed — plus level and age). `LogFilterBar` /
  `LogFilterController` hold one `FilterCondition` pill per term — typed bare words
  are *any-field* terms and become "Any field" pills, never message pills. A pill with a
  blank value is a draft and contributes no term. The pills live inside one type-to-filter
  field serving both audiences: focusing it opens a "Filter by…" menu (pick a field, get a
  draft pill and its editor), and typed syntax (`tag:Auth`, `-message~:^x`, `level:e`)
  becomes pills on Space / ↵ through `applyTyped` (`LogFilters.parse`). Its popovers are
  `AnchoredPopover`s, which
  don't nest (a click in a second one counts as outside the first), so choices inside a card
  — the operator list — open inline rather than as a menu. `AnchoredPopover` positions its
  card with `OverlayPortal.overlayChildLayoutBuilder`; don't reach for
  `CompositedTransformFollower` for overlays — a `Tooltip` (or anything else on the layout
  builder) inside a follower asserts and paints Flutter's red error box. Text fields in a
  card or its anchor pass `AnchoredPopover.textContextMenuBuilder`, or Paste in their
  right-click menu closes the card.
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
  - **Dropping onto the Files pane** copies into the folder it shows instead, and an
    installable for this device first asks *Install* or *Copy*; other-platform installables
    are copied there rather than rejected. The pane is a `DropZone`
    (`presentation/components/drop_zone.dart`), **not** a second `DropTarget`: desktop_drop
    broadcasts each event to every mounted target containing the pointer, so nested targets
    would both act on one drop. `DeviceScreen`'s single target hit-tests for the zone under
    the pointer (`DropZone.at`, via `MetaData`) and hands it the drop — which is also why
    the screen-wide `DropOverlay` sits in an `IgnorePointer`.
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
- **Emulator manager:** `EmulatorManagerController` (feature `emulator_manager/`) lists the
  located SDK's AVDs, launches them, stops them over the adb console, and can create or delete
  one. The dialog is reachable from four places (header action, header context menu, landing
  card, command palette) and **must** dispose the controller.
  - **Two-tier refresh:** `refresh()` re-reads the SDK — `emulator -list-avds` plus one
    `config.ini` per AVD — and runs only on open, on Refresh, and after a mutation. The ~2 s
    poll (`pollInterval`) re-reads *runtime* state only: the devices `DevicesRepository` already
    tracks, plus one `adb emu avd name` per unresolved emulator serial (cached in
    `_serialAvdNames`, pruned when a serial disappears). Folding the SDK read into the poll
    would re-stat every AVD twice a second.
  - **Gotcha — `starting` is our own record, not something adb reports:**
    `DevicesRepository._mergeDevices` downgrades any Android device whose `status != 'device'`
    to `disconnected`, so a mid-boot emulator is indistinguishable from a stopped one. The
    `starting` state therefore comes from `_pendingLaunches` (name → launch time, expiring at
    `launchTimeout`), which is why an emulator someone started in Android Studio stays
    `stopped` here until it finishes booting.
  - **Gotcha — `isBusy` must stay narrow:** it means a launch or stop *command* is in flight —
    never the poll, never the boot. Same starvation lesson as `isWirelessBusy`: a three-minute
    boot must not disable the whole dialog.
  - Launching uses `ProcessStartMode.detached` (the emulator has to outlive Eagly), which costs
    the exit code and stdio — so a name is validated *before* the spawn
    (`AvdManagerTool.describeInvalidName`) and the boot is observed through `adb devices`.
    Detached children are deliberately excluded from `ToolProcessRunner._liveProcesses`.
  - `_pollGeneration` invalidates in-flight loops the way `_scanGeneration` does, and a tick
    notifies only when the runtime state actually changed. Both the tick and the
    `onEmulatorReady` callback are wrapped in try/catch: an exception escaping the `while`
    would leave `_polling` true and the loop permanently unrestartable.
  - AVD metadata is read straight off the INI files (`~/.android/avd/<name>.ini` points at
    `<name>.avd/config.ini`; `AvdMetadataReader`) rather than from `avdmanager list avd` — no
    JVM to start, and it is what each tile's API / device / ABI line is built from.
  - **Gotcha — `avdmanager` realities:** `create avd` asks on stdin whether to build a custom
    hardware profile, so it hangs forever on a pipe that never closes —
    `runTextWithTimeout(…, closeStdin: true)` makes it take its own default instead. It reports
    problems on an `Error:` line and prints a literal `null` line (`describeFailure` handles
    both), accepts only `[A-Za-z0-9._-]` in a name, and spends ~1.5 s just starting the JVM
    (hence the 90 s timeout). A system image's tag must match the device profile's tag —
    untagged profiles are phones/tablets, and an unknown image tag is treated as handheld.
  - Creating is gated on `canManageAvds` (the SDK must actually ship `avdmanager`), deleting is
    refused while the AVD is running, and both finish with `refresh(clearFeedback: false)` so
    the failure message survives the reload that follows it.
  - Not covered, deliberately: iOS simulators (`xcrun simctl`), system-image downloads
    (`sdkmanager`, licence prompts, multi-GB fetches) and hardware-profile editing.
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
  Never `await repository.refreshDevices(force: true)` from a test body while a
  `DeviceSessionManager` is alive: it hands back the manager's parked start-up
  `_reloadDevicesWith(retry: true)` future and the test deadlocks — set the fake tool's device
  list and `pump` past the retry delay instead.
- Commit/push only when asked; branch off `main` first.
- Never discard uncommitted working-tree changes you didn't just make (`git checkout --`,
  `git restore`, `stash drop`, etc.) — even if they look stray or unrelated to the current
  task. Treat any pre-existing uncommitted edit as the user's in-progress work; ask before
  touching it. (Incident: `README.md` edits were wiped twice this way and nearly lost.)
