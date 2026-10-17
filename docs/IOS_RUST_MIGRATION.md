# iOS: migrating from libimobiledevice to the `idevice` Rust crate

Eagly reaches iOS devices by spawning the bundled libimobiledevice CLIs and re-parsing their
human-readable stdout. We are replacing that, surface by surface, with
[`idevice`](https://github.com/jkcoxson/idevice) — a pure-Rust implementation of the same
protocols — called over [flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/).

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
 ├─ LibimobiledeviceIosDeviceService   wraps IdeviceIdTool + IdeviceInfoTool   ← default
 └─ RustIosDeviceService               wraps lib/src/rust/api/ios.dart

IosLogService                          live syslog streaming
 ├─ LibimobiledeviceIosLogService      wraps IdeviceSyslogTool                 ← default
 └─ RustIosLogService                  wraps lib/src/rust/api/ios.dart

IosAppService                          app inventory and lifecycle
 ├─ LibimobiledeviceIosAppService      wraps IdeviceInstallerTool              ← default
 └─ RustIosAppService                  wraps lib/src/rust/api/ios.dart

IosCrashReportService                  crash report retrieval
 ├─ LibimobiledeviceIosCrashReportService  wraps IdeviceCrashReportTool        ← default
 └─ RustIosCrashReportService              wraps lib/src/rust/api/ios.dart

DeviceFileSystem                       file browsing (shared with Android)
 ├─ IosFileSystem                      drives the afcclient REPL              ← default
 └─ RustIosFileSystem                  wraps lib/src/rust/api/ios.dart
```

Logic that sits *above* the transport is shared rather than duplicated per backend:
`buildIosDeviceInfo` maps lockdownd domains to the device-home model for both, `IosSyslogParser`
turns raw syslog lines into `LogEntry`s for both, `sortIosApps` / `takeRecentIosApps` order
and cap the app list for both, and `collectCrashReports` parses pulled report files for both.
Only the reading differs.

Rules that keep this from rotting:

- **The interface speaks domain types** (`IosDeviceInfo`), never generated ones. Only the `Rust*`
  implementation may import `lib/src/rust/**`; everything above it is backend-agnostic.
- **libimobiledevice stays the default** until a surface is proven on real hardware.
- **Tests fake the interface**, so they cover both backends and need no native library.

Switch backends with an environment variable — a developer migration aid, not a user setting:

```bash
EAGLY_IOS_BACKEND=rust fvm flutter run -d macos
```

## Status

| Surface | libimobiledevice | Rust | State |
| --- | --- | --- | --- |
| Discovery (`idevice_id`, `ideviceinfo`) | `IdeviceIdTool`, `IdeviceInfoTool` | `list_ios_devices`, `describe_ios_device` | both, **unverified on hardware** |
| Syslog streaming | `IdeviceSyslogTool` | `start_ios_syslog`, `stop_ios_syslog` | both, **unverified on hardware** |
| Extended device info | `IdeviceInfoTool.readDeviceDomains` | `read_ios_device_domains` | both, **unverified on hardware** |
| App install / list / uninstall | `IdeviceInstallerTool` | `list_ios_apps`, `install_ios_app`, `uninstall_ios_app` | both, **unverified on hardware** |
| Crash reports | `IdeviceCrashReportTool` | `pull_ios_crash_reports` | both, **unverified on hardware** |
| File manager (AFC) | `IosFileSystem` (`afcclient`, **not bundled**) | `RustIosFileSystem` | both, **unverified on hardware** |
| Utilities / Terminal | `DeviceToolRunner` | — | **blocked on a product decision — see below** |

## Working on the Rust side

```bash
cd rust && cargo check          # after editing rust/src/api/**
flutter_rust_bridge_codegen generate   # regenerate bindings; run from the repo root
cd rust && cargo clippy && cargo fmt
```

`rust/src/frb_generated.rs` and `lib/src/rust/**` are generated — never edit them. A new file
under `rust/src/api/` is invisible to codegen until it is declared in `rust/src/api/mod.rs`.

`frb_generated.dart` embeds a hash of the Rust API: if `RustLib.init()` throws at startup
complaining about a codegen version or content hash, re-run the generator.

**Streams.** A function taking a `StreamSink` becomes a Dart `Stream` and its return value is
discarded — `Result<(), E>` is the only shape that works, so a stream cannot hand back a session
handle. Cancellation is not propagated either: cancelling the Dart subscription leaves the tokio
task running, so every stream needs an explicit stop function. `start_ios_syslog` therefore takes
a caller-supplied session id and `stop_ios_syslog` cancels by that id — keyed per *stream*, never
per device, because eagly opens one log stream per tab and several tabs may watch one device.

Cargo features are enabled per surface in `rust/Cargo.toml` rather than via `full`, which is the
difference between a 30-second and a 4-minute cold build. Note `crashreportcopymobile` implies
`afc`, and the pairing error variants above need `pair`.

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
