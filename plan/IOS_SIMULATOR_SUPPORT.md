# iOS simulator support — scope

Status: **scoped, not built.** Written 2026-10-21.

## Why simulators don't show up today

Every iOS device Eagly knows about comes from usbmuxd: the Rust backend's
`list_ios_devices()` (`rust/src/api/ios.rs`) and the CLI fallback's
`idevice_id -l` (`lib/services/tools/idevice_id_tool.dart`). A simulator is not a
usbmuxd device — only `xcrun simctl` knows about it — so a booted simulator never
appears. AGENTS.md (emulator manager notes) lists iOS simulators as deliberately not
covered.

Everything below is macOS-only: `simctl` ships with Xcode. Windows and Linux see
nothing. It is Xcode tooling, not libimobiledevice, so the Rust migration does not
apply — no crate replaces CoreSimulator, and a CLI wrapper is the right shape.

## Phase 1 — discovery and logs

The features are small; the cost is the ~44 sites across 23 files under `lib/` that
branch on `IosDevice` today, each of which must decide what a simulator does.

1. **Model: a `SimulatorDevice` sibling of `IosDevice`** in the sealed `Device`
   (`lib/data/device.dart`), with `platform => DevicePlatform.ios`.
   - Not an `isSimulator` flag on `IosDevice`: that silently routes simulators into
     the usbmuxd/lockdown paths at every `case IosDevice():`, and each fails at runtime.
   - A sibling makes the compiler list every site; most become a one-line "not on
     simulators".
   - Sites that should treat it like an iPhone — icons, labels, `isIosLogContext` and
     the log filters — become `IosDevice() || SimulatorDevice()`.

2. **Discovery.** A `SimctlTool` (`ToolProcessRunner`) runs
   `xcrun simctl list devices booted -j`, polled on the existing 4 s iOS timer in
   `DevicesRepository`.
   - The JSON already carries `udid`, `name`, `state`, the runtime key
     (`iOS-26-5` → "iOS 26.5") and `deviceTypeIdentifier` (→ "iPhone 17 Pro"), so
     there is no describe step and nothing to cache.
   - Shut down = disconnected, like an unplugged device. No Xcode / no `xcrun` = an
     empty list, silently.

3. **Logs.** `xcrun simctl spawn <udid> log stream --style ndjson`, one JSON object
   per line, parsed by a new `SimulatorLogParser` and wired into
   `DeviceSessionRepository.startLogStream`.
   - Keep `eventType == "logEvent"`; level from `messageType`
     (Default/Info/Debug/Error/Fault); process from the basename of
     `processImagePath`; pid from `processID`; tag from `subsystem`/`category` (more
     than physical iOS logs give); message from `eventMessage`.
   - Drop the harmless `getpwuid_r did not find a match` line on stderr.
   - `--level debug` is very noisy; `info` is probably the right default.

4. **Device home.** Show what `simctl` knows — name, runtime, device type, UDID, data
   size — and hide the lockdown-backed cards.

5. **Tests.** Fixture tests for the `simctl` JSON and the ndjson parser; a repository
   test that simulators merge into the device list.

In phase 1 every other feature answers "not on simulators".

## Later phases — feature by feature

| Feature | On a simulator | How |
|---|---|---|
| Screenshot / recording | Easy | `simctl io <udid> screenshot` / `recordVideo` (stop with SIGINT) |
| App list / launch / quit / uninstall | Easy | `listapps` (old-style plist; `plutil -convert json` makes it JSON), `launch`, `terminate`, `uninstall` |
| Install | Partial | `simctl install` takes only a simulator-built `.app`; refuse a device `.ipa` with a clear message |
| File manager | Easy | App containers are host folders (`DataContainer` in `listapps`), so a local-folder backend — simpler than a device |
| Deep links, location | Easy | `openurl`, `location` (a device needs the developer disk image for location) |
| Simulator-only utilities | Easy | `push`, `pbcopy`/`pbpaste`, `ui` appearance, `status_bar` override, `privacy` grants |
| Network inspector | Medium | Simulators share the host network, so Inspektor's 38470–38477 are on `127.0.0.1` without usbmux — but all booted simulators and macOS apps share that range, so a connection can't be tied to one simulator unless Inspektor reports its device |
| Crash reports | Unverified | Written to `~/Library/Logs/DiagnosticReports` on the host; not checked whether a report names its simulator |
| Terminal | Limited | `simctl spawn <udid> <cmd>` runs commands inside the simulator |
| Mirror | Skip | The QuickTime route and DDI are physical-only; a Simulator-window ScreenCaptureKit plugin plus private-API input isn't worth it — the Simulator app already mirrors |
| Performance stats, pairing, wireless, battery | No | No equivalent |
