# iOS: migrating from libimobiledevice to the `idevice` Rust crate

Eagly reaches iOS devices by spawning the bundled libimobiledevice CLIs and re-parsing their
human-readable stdout. We are replacing that, surface by surface, with
[`idevice`](https://github.com/jkcoxson/idevice) — a pure-Rust implementation of the same
protocols — called over [flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/).

**The libimobiledevice CLIs and friends will be removed in a future version.** The Rust backend
is the one that stays, so new iOS features and fixes land there first; the CLI path is kept
correct while it ships, not extended.

## Why

- **Typed errors instead of stderr string-matching.** `IdeviceError` distinguishes
  `DeviceLocked`, `InvalidHostID`, `PairingDialogResponsePending`, `UserDeniedPairing`,
  `PasswordProtected` — states we currently guess at with `output.contains('pair')`.
- **Capabilities the CLIs do not expose:** install progress callbacks, a usbmuxd device-event
  stream (the iOS equivalent of `adb track-devices`), a real liveness probe via `heartbeat`.
- **`afcclient` is bundled on no platform**, so the iOS file manager only works today for users
  who installed libimobiledevice themselves. Compiling in the `afc` feature ships it.
- **Packaging.** The 33 files staged into `platform-tools/macos/` — the dylib closure,
  `install_name_tool` path rewriting, the ad-hoc re-signing pass, the Ubuntu `libssl1.0.0` .deb
  staged on Linux for an OpenSSL 1.0 soname — all collapse into one framework built in-tree.

## How both backends coexist

Each iOS surface gets an interface under `lib/services/ios/`, with two implementations:

```
IosDeviceService                       discovery + lockdownd domains
 ├─ LibimobiledeviceIosDeviceService   wraps IdeviceIdTool + IdeviceInfoTool
 └─ RustIosDeviceService               wraps lib/src/rust/api/ios.dart         ← default

IosLogService                          live syslog streaming
 ├─ LibimobiledeviceIosLogService      wraps IdeviceSyslogTool
 └─ RustIosLogService                  wraps lib/src/rust/api/ios.dart         ← default

IosAppService                          app inventory and lifecycle
 ├─ LibimobiledeviceIosAppService      wraps IdeviceInstallerTool
 └─ RustIosAppService                  wraps lib/src/rust/api/ios.dart         ← default

IosCrashReportService                  crash report retrieval
 ├─ LibimobiledeviceIosCrashReportService  wraps IdeviceCrashReportTool
 └─ RustIosCrashReportService              wraps lib/src/rust/api/ios.dart     ← default

IosNetworkService                      TCP ports on the device, for the Network pane
 └─ RustIosNetworkService              wraps lib/src/rust/api/ios_network.dart (no CLI version:
                                       with the CLIs the device simply has no ports)

DeviceFileSystem                       file browsing (shared with Android)
 ├─ IosFileSystem                      drives the afcclient REPL
 └─ RustIosFileSystem                  wraps lib/src/rust/api/ios.dart         ← default
```

Logic that sits *above* the transport is shared rather than duplicated per backend:
`buildIosDeviceInfo` maps lockdownd domains to the device-home model for both, `IosSyslogParser`
turns raw syslog text into `LogEntry`s for both (the CLI's lines via `parseLogLines`, the Rust
relay's whole-message records via `parseLogRecords`), `sortIosApps` / `takeRecentIosApps` order
and cap the app list for both, and `collectCrashReports` parses pulled report files for both.
Only the reading differs.

Rules that keep this from rotting:

- **The interface speaks domain types** (`IosDeviceInfo`), never generated ones. Only the `Rust*`
  implementation may import `lib/src/rust/**`; everything above it is backend-agnostic.
- **Rust is the default**; libimobiledevice remains as a fallback until every surface is proven
  on real hardware.
- **Tests fake the interface**, so they cover both backends and need no native library.

Switch backends with an environment variable — a developer migration aid, not a user setting:

```bash
EAGLY_IOS_BACKEND=cli fvm flutter run -d macos   # fall back to libimobiledevice
```

## Status

| Surface | libimobiledevice | Rust | State |
| --- | --- | --- | --- |
| Discovery (`idevice_id`, `ideviceinfo`) | `IdeviceIdTool`, `IdeviceInfoTool` | `list_ios_devices`, `describe_ios_device` | both, **unverified on hardware** |
| Syslog streaming | `IdeviceSyslogTool` | `start_ios_syslog`, `stop_ios_syslog` | both, **Rust reads `os_trace_relay` — unverified on hardware since the switch** |
| Extended device info | `IdeviceInfoTool.readDeviceDomains` | `read_ios_device_domains` | both, **unverified on hardware** |
| App install / list / uninstall | `IdeviceInstallerTool` | `list_ios_apps`, `install_ios_app`, `uninstall_ios_app` | both, **unverified on hardware** |
| App icons (SpringBoard) | — | `fetch_ios_app_icon` | Rust only; the CLI backend shows initials. Verified on an iPhone 16 (iOS 27.0) with the ignored `app_icons` test in `api/ios.rs`: 57 apps, 192×192 PNGs, ~80 ms each |
| Crash reports | `IdeviceCrashReportTool` | `pull_ios_crash_reports` | both, **unverified on hardware** |
| File manager (AFC) | `IosFileSystem` (`afcclient`, **not bundled**) | `RustIosFileSystem` | both, **unverified on hardware** |
| Network inspection: port probe and forward | — | `probe_ios_ports`, `start_ios_port_forward`, `stop_ios_port_forward` (`api/ios_network.rs`) | Rust only (`IosNetworkService`), verified on an iPhone 16 (iOS 27.0) with `test/device/network_inspektor_ios_device_test.dart` |
| Screen mirror: probe, screenshots, touch / keys / buttons, pasteboard, rotation | — | `probe_ios_mirror`, `capture_ios_screenshot`, `start_ios_screenshot_stream`, `start_ios_input` and the `send_ios_*` calls (`api/ios_mirror.rs`) | Rust only (`IosMirrorService`). Probe, screenshots, the screenshot stream, touch and Home verified on an iPhone 16e (iOS 26.6) with `test/device/ios_mirror_device_test.dart`; keys, the pasteboard and rotation are not covered by it. The picture on macOS comes from QuickTime's route instead. See **docs/IOS_SCREEN_MIRROR.md** |
| Utilities / Terminal | `DeviceToolRunner` | — | **blocked on a product decision — see below** |

### Syslog: what hardware showed

Both backends stream without losing, splitting or reordering lines — checked against the raw
output on an iPhone (iOS 26.7 and 27.0) with `test/device/log_stream_integrity_test.dart`.
`start_ios_syslog` originally read the legacy `syslog_relay`, which had three gaps versus
`idevicesyslog`:

- **`syslog_relay` has no Debug or Info messages** — roughly 80–85% of what `idevicesyslog`
  shows, which reads `os_trace_relay`.
- **No sub-second timestamps.**
- **Its records keep the device hostname**, so process and package names came out as
  `Shreyashs-iPhone backboardd`, which broke package filtering.

`start_ios_syslog` now reads `os_trace_relay` (`OsTraceRelayClient`) and formats each record
into the same line `idevicesyslog` prints (`format_os_trace_log`), so all three gaps are gone:
Info/Debug levels, `%b %e %H:%M:%S.%06u` timestamps, and a clean `process(image)` label with no
hostname. Relay records are whole messages, embedded newlines included, and go through
`parseLogRecords`, not the CLI's line-by-line `parseLogLines`. The switch is **not yet
re-verified on hardware** — re-run `test/device/log_stream_integrity_test.dart` against a device
before declaring it done. Details, numbers and the device check: **docs/LOG_STREAMING.md**.

### Open issues (from the PR #66 review, 2026-10-17)

Found reviewing `fix/ios-rust-backend`. CLI-only issues are left out on purpose — that backend
is going away. Fixed since on `release/1.5.4`: UTC timestamps shown as local time, one
undecodable record ending the stream (decode errors are now skipped), no CLI fallback when the
Rust library fails to load, and the log docs citing tests and an ordering fix the branch
lacked.

**Should fix:**

1. **The crate panics on malformed packets.** `OsTraceRelayReceiver::next` slices without
   bounds checks (`len() - 1` on zero-length strings, fixed offsets into short packets). A panic
   kills the syslog task before `forget_syslog_session` runs, leaking the registry entry, and
   ends the stream like a disconnect. Needs a crate fix or a bump past 0.1.65.
2. **Rust records still go through the line parser.** Each line of a record is checked against
   the header regex and the `[connected:…]` status pattern even though the record boundary
   already ends the entry: a message line that looks like a header splits the entry under a fake
   process/PID, and an `[connected:x]` line drops the rest of the message. And because
   `parseLogRecords` flushes after every record, a record whose first line misses the header
   regex (e.g. empty `filename` and `image_name` → `(.+?)\[` can't match) is filed under the
   previous record's process and PID. The root cause is the round trip — Rust formats a
   structured `OsTraceLog` into idevicesyslog text that Dart regex-parses back, which is also
   where the timezone bug came from, and it runs `\M-` decoding over raw UTF-8. Preferred fix:
   send a struct (epoch micros, pid, level, process, image, message) over the bridge and build
   `LogEntry` directly. Smaller fix: in record mode, don't resume the flushed header and skip
   the status-line check.

**Minor:**

- Stop race: if `stop()` runs after Rust has dropped the session but before Dart's `onDone`,
  `ended` is still false and `stop_ios_syslog` leaves a cancelled token nobody claims.
- The resume-after-flush logic (`_flushedHeader`, `resumed()`, `isResumed`, blank-entry check)
  is duplicated in both parsers and has already drifted; if the text path stays, move it into a
  shared base in `log_line_parser.dart`.
- `parseLogLines` keeps a 100 ms periodic timer running for every open stream, even with nothing
  pending (Android path).
- A logcat header outside `[VDIWEF]` (e.g. `?`) or reshaped by device format settings is now
  appended to the previous entry's text instead of dropped.

## Working on the Rust side

```bash
cd rust && cargo check          # after editing rust/src/api/**
flutter_rust_bridge_codegen generate   # regenerate bindings; run from the repo root
cd rust && cargo clippy && cargo fmt && cargo test
```

The app build compiles the crate itself: `hook/build.dart` is a Dart build hook
(flutter_rust_bridge_hooks over native_toolchain_rust) that `flutter build`, `run` and `test`
invoke, and Flutter bundles the result as a code asset (`rust_lib_eagly.framework` on macOS,
`librust_lib_eagly.so` on Linux, `rust_lib_eagly.dll` on Windows). There is no CocoaPods or
Swift Package Manager plugin behind it. The Rust version and targets come from
`rust/rust-toolchain.toml`; rustup installs them on first build, and the hook refuses a target
that isn't listed there. It always builds `--release`, and it builds into `.dart_tool/`, not
`rust/target/`.

`rust/src/frb_generated.rs` and `lib/src/rust/**` are generated — never edit them. A new file
under `rust/src/api/` is invisible to codegen until it is declared in `rust/src/api/mod.rs`.

`frb_generated.dart` embeds a hash of the Rust API: if `RustLib.init()` fails complaining about a
codegen version or content hash, re-run the generator. It runs at startup unless
`EAGLY_IOS_BACKEND=cli` (`initIosBackend()` → `services/ios/rust_ios_runtime.dart`). A
failure is logged, not thrown, and the session falls back to the CLI backend — so if iOS
behaves like the CLIs when you expected Rust, look in the app log for "Failed to load the Rust
iOS backend". Only the CLI fallback never loads the library.

**Streams.** A function taking a `StreamSink` becomes a Dart `Stream` and its return value is
discarded — `Result<(), E>` is the only shape that works, so a stream cannot hand back a session
handle. Cancellation is not propagated either: cancelling the Dart subscription leaves the tokio
task running, so every stream needs an explicit stop function. `start_ios_syslog` therefore takes
a caller-supplied session id and `stop_ios_syslog` cancels by that id — keyed per *stream*, never
per device, because eagly opens one log stream per tab and several tabs may watch one device.

Cargo features are enabled per surface in `rust/Cargo.toml` rather than via `full`, which is the
difference between a 30-second and a 4-minute cold build. Note `crashreportcopymobile` implies
`afc`, and the pairing error variants above need `pair`. The screen mirror adds the CoreDevice tunnel
(`core_device_proxy`, `tunnel_tcp_stack`, `rsd`, `core_device`), `display_stream` (which also gates
the crate's HID module) and `springboardservices`.

The crate is pinned exactly (`=0.1.65`): it is pre-1.0 and its README warns of breaking changes at
every release until 0.2.0. It is also built against the `ring` TLS backend rather than the default
`aws-lc`, which needs cmake and (on Windows) NASM.

## Utilities and Terminal: why these are not ported

Every other surface was a transport swap behind an interface. These two are not, because their
domain model *is* the command line.

`UtilityInvocation` is `(executable, argv)`; `DeviceSessionRepository.runUtility` prepends the
tool's device selector (`-u <udid>`) and returns a `ToolCommandResult` of stdout, stderr and an
exit code, which the UI renders as raw text. The Terminal feature goes further: it lets the user
type arbitrary arguments for 18 different `idevice*` binaries.

There is no "run an arbitrary binary with arbitrary arguments" in a library that exposes one typed
client per service. Porting them means picking one of:

1. **Map each catalogued command to a typed call and synthesise CLI-shaped stdout.** Feasible for
   the fixed Utilities catalog — `diagnostics_relay` covers restart/shutdown/sleep/IORegistry,
   lockdown covers device name/date/WiFiAddress, `pair` covers validate/unpair,
   `location_simulation` covers set/reset. But the text would not match what the CLIs print, and
   the UI shows it verbatim, so users comparing against the real tools would see it drift. It also
   does nothing for Terminal's free-form arguments.
2. **Redesign Utilities as a typed command palette** — each entry a Rust call with typed
   parameters and a structured result, rather than an argv and a text blob. Honest, and better
   than what is there, but a UI change rather than a port. Terminal would become iOS-unsupported
   (it already refuses free-form shell on iOS).
3. **Keep libimobiledevice bundled for these two features only.** Cheapest, and everything else
   still moves — but it forfeits dropping the bundled CLIs, which is the packaging payoff.

Only (2) reaches a build with no libimobiledevice in it. This is a product decision, not an
implementation one, so it is recorded here rather than made.
