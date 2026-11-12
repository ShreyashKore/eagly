# Network Inspector: plan

> **Status: not built.** Phases 1 and 2 have landed on Android and iOS and are described in
> [docs/NETWORK_INSPECTOR.md](../docs/NETWORK_INSPECTOR.md), with the architecture (§3) and the
> protocol (§4). This file holds the rest: phases 3 to 5, what phases 0 to 2 still leave open,
> risks, spikes, open questions and the research for routes not built yet. Section numbers
> follow the docs file: the §1 and §2 sections here hold the rows and notes moved out of the
> docs file's §1 and §2, and other §1 to §4 references point there. Research was done on 2026-10-18
> against primary sources; claims that could not be confirmed are marked *unverified*. Sources
> are in [Appendix A](#appendix-a--research-notes).

## Summary

- **Mocking comes from Inspektor's override engine, edited from Eagly.** That was the main reason
  to build a MITM proxy. For apps that ship Inspektor, we no longer need one.
- **Two routes that need nothing installed stay as complements**, in this order:
  1. Android WebViews and Chrome, over the Chrome DevTools Protocol (CDP). Chromium runs its own
     network stack inside the process, so no Inspektor adapter can see that traffic.
  2. The Dart VM service, for Flutter debug builds that don't ship Inspektor.
- **Deferred:**
  - The desktop MITM proxy. It is the only way to see *other* apps' content.
  - iOS HAR logging through Apple's developer tools (DVT). It needs a developer disk image and a
    tunnel stack, which Eagly should build for other features first.
  - iOS WebView inspection.
- **Dropped:** each is written up in detail (how it works, what it would take, why it was dropped,
  when to revisit) in [NETWORK_INSPECTOR_DROPPED_ROUTES.md](NETWORK_INSPECTOR_DROPPED_ROUTES.md):
  - a JVMTI port of Android Studio's Network Inspector;
  - React Native through Metro;
  - a VPN companion app.

## 1. Routes kept for later

From the docs file's §1 table (what changed once Inspektor went multi-client), the rows for
routes that are not built:

| Route | First pass | Now | Why |
|---|---|---|---|
| Dart VM service | Phase 1, primary for Flutter | Complement, phase 4. For Flutter debug/profile apps *without* Inspektor | It needs no package. Inspektor's Dart client adds release/QA builds, overrides and history. |
| Android WebView and Chrome over CDP | Phase 1 | Complement, phase 4, first in line | Chromium's in-process network stack is invisible to every Inspektor adapter. |
| Desktop MITM proxy | Phase 2 | Deferred, phase 5 | Mocking for your own app now comes from Inspektor. The proxy only adds *other* apps. |
| iOS HAR logging (DVT) | Phase 4 | Deferred. Build the DVT stack for its other uses first | The URLSession adapter covers your own iOS apps. |
| iOS WebView (`webinspector`) | Optional | Optional (unchanged) | The only route to WKWebView traffic. |
| `pcapd` connection metadata | Optional | Optional (unchanged) | The only way to see other iOS apps with no setup. |

CDP and the VM service would map onto Eagly's Inspektor-shaped model (§3.1 below).

## 2. Capture routes kept for later

From the docs file's §2 table, the routes evaluated and not built:

| Route | What it sees | What it needs | Android | iOS | Status |
|---|---|---|---|---|---|
| CDP to `*_devtools_remote` sockets | Chrome, debuggable WebViews, Stetho apps. Full Network domain, bodies included | Nothing, for debuggable apps | ✅ | – | Phase 4 |
| Dart VM service HTTP profile | `dart:io`, plus `cupertino_http` / `cronet_http` / `ok_http` through `http_profile` | A debug or profile build | ✅ | ✅ | Phase 4 |
| `pcapd` | Per-packet process name, DNS, SNI and byte counts; a `.pcap` | USB | – | ✅ | Optional |
| Desktop MITM proxy | Anything that honours the proxy and trusts the CA | CA trust. On Android, the app must opt in. On iOS, the same Wi-Fi network | ✅ | ⚠️ | Deferred |
| iOS HAR logging (DVT `activitytracetap`) | Every URLSession request of a dev-signed app, bodies included | Developer Mode, a developer disk image (DDI), and the iOS 17.4+ tunnel | – | ✅ | Deferred |
| `com.apple.webinspector` | WKWebView and Safari | The Web Inspector toggle, and `isInspectable` in the app | – | ✅ | Optional |
| DVT network monitor | Per-process connections and byte counters | DDI and tunnel | – | ✅ | With the DVT stack |

### 2.1 Coverage once phases 1–4 land

| Debugging… | Android | iOS |
|---|---|---|
| Your own app with Inspektor, any framework | Inspektor | Inspektor |
| Your own Flutter app without Inspektor (debug or profile) | Dart VM service | Dart VM service |
| A WebView in your own app | CDP | – (`webinspector`, optional) |
| Chrome | CDP | – |
| Your own native app without Inspektor | – (proxy, deferred) | – (HAR logging, deferred) |
| Other apps | – (proxy plus a system CA, deferred) | `pcapd` metadata (optional); proxy deferred |

A note on Flutter: `dart:io` ignores the system proxy, and on Android it also ignores
user-installed CAs. Without code changes, a proxy cannot see a Flutter app. That is why Flutter
support has to come from the SDK or the VM service.

## 3. Architecture for the sources still to build

These extend §3 of [the docs file](../docs/NETWORK_INSPECTOR.md#3-architecture-in-eagly).
Planned additions to its map:

```
                     ├─ services/cdp/  CdpSource              phase 4
                     └─ services/dart_vm/  DartVmSource       phase 4
```

### 3.1 Model: other sources and later fields

- **Later:** WebSocket frames, redirect chains and initiator.

The other sources map onto the same model:

- **CDP:** `requestWillBeSent` → `responseReceived` → `loadingFinished`/`loadingFailed`, with
  bodies from `getResponseBody`.
- **Dart VM service:** the `HttpProfileRequest` objects.

### 3.2 Discovery of phase 4 targets

| Target | How Eagly finds it |
|---|---|
| Android, CDP (phase 4) | The same scan, looking for names ending in `_devtools_remote`. |
| Android, Dart VM (phase 4) | The "Dart VM service is listening on" banner in logcat. |
| iOS, Dart VM (phase 4) | mDNS `_dartVmService._tcp` (TXT record `authCode`), raced against the log banner the way flutter_tools does it. |

In the docs file, the iOS Inspektor row says only that the handshake names the app. Still to
add: `os_trace_relay`'s `PidList` maps a pid to its process name.

**Log taps for phase 4b.** When discovery needs log lines (the Dart VM service banner in phase
4b), it opens **its own filtered log tap**: `os_trace_relay` `start_trace(Some(pid))` on iOS,
and `adb logcat -T 1 -s <tag>` on Android.

### 3.4 Source interface: planned additions

The built `NetworkSource` (docs file §3.4) has `kind`, `label`, `events`, `body` and `dispose`.
The original design also had:

```dart
  NetworkSourceCapabilities get capabilities; // overrides? backfill? request bodies?
  Future<void> clear();
```

Capabilities would let the UI hide override editing for CDP and VM-service targets, and show
"history available" only where backfill exists.

### 3.5 Duplicates

The same request can be visible through more than one route:

- A Flutter app can be visible through both Inspektor and the VM service.
- An app with native OkHttp *and* Dart code can run two Inspektor servers in one process.

The rules:

- **Two Inspektor channels in one process merge into one target.** Each transaction keeps its
  `adapter` tag, so the UI can filter by stack.
- **When an Inspektor target exists for a process, Eagly doesn't attach the Dart VM source for that
  process.** It is offered only as an alternative.
- **If the proxy is ever built,** flows from an app that has an Inspektor target are hidden by
  default.

### 3.6 Privacy: not built yet

- **Not built yet:** HAR export redacting `Authorization`, `Cookie` and `Set-Cookie`, and the pane
  redacting the same headers under `--record-mode` (the mode for product videos). Until they land,
  an exported HAR and a recorded video contain these headers as captured.

## 5. What Eagly needs from Inspektor later

**Should have, for phase 3 onward:**

- **Override create/delete over the wire (milestone I-2).** *(Done ahead of time:
  `overrides.list`, `overrides.put`, `overrides.delete` and the `overrides.changed` event.)*
- **Bodies as bytes with a content type, not only as `String`, for images and protobuf (I-3).**
  Today they are text plus `isRequestBodyEncoded`.
- **Timing phases (I-3)** from OkHttp's `EventListener` and `URLSessionTaskMetrics`.
- **WebSocket frames (I-4)** from OkHttp's `WebSocketListener`, `URLSessionWebSocketTask` and
  `dart:io` `WebSocket`.

**Flutter.** The Inspektor plan rules out binding the Kotlin core into Flutter, and this design
fits that. With Eagly as the viewer, a Flutter app needs no native UI at all. The Dart
implementation needs:

- **Capture:**
  - `HttpOverrides.global`, for `dart:io`. That also covers `package:http`'s `IOClient` and dio's
    default adapter.
  - A `package:http` `BaseClient` wrapper, which covers `cupertino_http`, `cronet_http` and
    `ok_http`.
  - A dio interceptor.
- **Serving:** the §4 server (abstract socket on Android, TCP on iOS), an in-memory ring buffer,
  and a port of the override engine (four matchers and three actions).
- **Open question:** how to keep it out of release builds. Dart has no Gradle-style variants; a
  `const bool.fromEnvironment` gate plus tree shaking is the obvious candidate.

## 6. Phased plan

Each phase ships on its own. Where a phase depends on an Inspektor milestone (I-n from §5), it says
so.

### Phases 0 to 2: what is still open

Phases 0 to 2 have landed (docs file §6). What they leave open:

- **Golden transcripts** (phase 0). The exit for phase 0 is the spec and fixtures merged in
  Inspektor, with §4 of the docs file reduced to a link. Until the transcripts exist, the client
  tests script the server by hand (`test/support/inspektor_test_support.dart`).
- **Connection failures in the pane.** A protocol mismatch ("update Eagly") is only logged for
  now.
- **The probe cost matrix** beyond macOS and USB: Windows, Linux, Wi-Fi (§8).
- **iOS `PidList`**, for process names.
- **Target lifecycle:** process death, and iOS suspension, which should show the target as
  paused. Today a backgrounded iOS app's source shows as ended (docs file §8).
- **An iOS device test against Inspektor's `:sample`.** The iOS run so far used a React Native
  app; the phase 2 exit asks for Ktor and URLSession on iOS.

### Phase 3: overrides and richer detail (needs I-2; I-3 parts as they land)

- An override list and editor in Eagly, plus "mock this response" on a transaction.
- ~~Previews for binary bodies, a timing waterfall, and "Copy as cURL"~~: landed early with the
  pane in §3.7. cURL follows `Curl.kt`'s layout (long options, one per line) and quotes values
  for the shell; `Curl.kt`'s `\'` escape inside single quotes does not work in a shell.
- **Exit:** an override created in Eagly changes the app's next response.

### Phase 4: complements that need no install

- **4a. CDP for Android WebViews and Chrome:**
  - discover `_devtools_remote` sockets in `/proc/net/unix`;
  - read `/json/list` through the forward and open the target's WebSocket;
  - send `Network.enable` and fetch bodies with `Network.getResponseBody`;
  - map the events onto the model.
- **4b. Dart VM service:**
  - Find the service: the banner from a logcat or iOS log tap, plus iOS mDNS.
  - Reach it through `adb forward` or the usbmux forward.
  - Use `package:vm_service`'s `DartIOExtension`: `httpEnableTimelineLogging`, poll
    `getHttpProfile(updatedSince)`, fetch bodies with `getHttpProfileRequest`, and call
    `clearHttpProfile` after fetching, because `dart:io` buffers bodies with no limit.
  - Follow the DDS redirect when `flutter run` is attached.
  - Skip this source when an Inspektor target exists in the same process (§3.5).
- **4c (optional).** A `pcapd` connections view for iOS, plus "Save .pcap". `idevice` already has
  `PcapFileWriter`.

### Phase 5: deferred, revisit on demand

- **Desktop MITM proxy** for other apps. Design notes are in Appendix B.
- **The iOS DVT stack:** Developer Mode, the personalized DDI signed through TSS, the CoreDeviceProxy
  software tunnel, and RSD. Build it for its other uses first: process list, launching apps with
  environment variables, location simulation and system stats. After that, HAR logging and the
  network monitor are small additions.
- **An iOS `webinspector` client in Rust**, using pymobiledevice3 as the reference implementation.

## 7. Risks

- **The Kotlin and Dart servers drift apart.** Mitigation: the §4.10 fixtures run in CI on both,
  and Eagly pins a protocol version.
- **The iOS token comes through the device log (§4.3).** If the syslog relay ever drops or
  delays Inspektor's line, the connection fails at `auth` and the watcher retries after its retry
  delay. Not yet checked against a physical iPhone; run `network_inspektor_ios_device_test.dart`
  before relying on it.
- **iOS apps are suspended in the background**, so live capture stops. The paused state and
  backfill cover the gap, and the UI should say so rather than look broken.
- **Polling adb and usbmux costs the device link.** Mitigation: one shell per Android poll, polling
  only while the pane is open, and probing only the fixed port range.
- **Memory.** Mitigation: Eagly's ring buffer and body budget, and clearing the VM-service profile
  after each fetch.
- **Moving the forward helpers out of `ScrcpyClient` could regress mirroring.** Mitigation: the
  move is mechanical; check it with the existing mirror tests and one device session.

## 8. Spikes and checks

Protocol 2 restored authentication (§4.3), and with it one of the two spikes that dropping it had
removed: **whether iOS delivers the token line to Eagly's log tap.** Eagly's side is built and
tested against fakes; it still needs a run on a physical iPhone. The other spike, whether Dart can
read the peer's uid, waits for the Dart server. Both are written up in
[the dropped-routes doc](NETWORK_INSPECTOR_DROPPED_ROUTES.md#authentication-on-the-socket-superseded).

What's left:
- before phase 2: one spike and two smaller checks;
- before phase 4b: one check.

How to run them:

- **Rust experiments:** a throwaway binary crate that depends on `idevice` with the same version
  and features as `rust/Cargo.toml`. It can't live inside `rust/`: that crate builds only `cdylib`
  and `staticlib`, so examples there can't link it.
- **App experiments:** small test apps. Inspektor's `:sample` is the natural host once it has a
  server.

### Before phase 2: how fast does a usbmux probe of a closed port fail?

**Decides:** whether iOS discovery can poll a port range (§3.2, §4.2), and how often.

**Result on macOS over USB (2026-10-20), iPhone 16 on iOS 27.0:** all 8 ports probed in parallel,
one open, take a median of 1–2 ms and at most 7 ms per poll, from Dart through the bridge. Polling
every 2 s is cheap. The interference check and the Windows, Linux and Wi-Fi runs are still to do.

**Background**
- **The load:** discovery would try every port in the range, about 8, every ~2 s while the Network
  pane is open. That's 4 connection attempts per second per device.
- **What a probe costs:** each attempt is a usbmux `Connect` request.
  - `idevice`'s `connect_to_device` consumes its `UsbmuxdConnection`, so every probe also opens a
    new connection to the usbmux daemon.
  - A closed port should come back quickly with `ConnectionRefused` (usbmux result code 3).
- **Three different daemons:** Apple's `usbmuxd` on macOS, Apple Mobile Device Service (from iTunes
  or the Apple Devices app) on Windows, and the open-source `usbmuxd` on Linux. They may not behave
  the same.
- **Interference:** the same daemon and USB link carry Eagly's log stream and file transfers.

**How to run**
1. **Time the probes.** In a throwaway Rust binary, call `UsbmuxdConnection::default()`, then
   `connect_to_device(device_id, port, label)`, against:
   - a closed port;
   - the open port of Inspektor's sample.

   Do 100 rounds of each, both sequentially and with all 8 ports in parallel. Record p50 and p95
   latency, and the error returned.
2. **Check interference.** While probing, run the `os_trace_relay` stream and an AFC upload of a
   large file. Compare against a baseline without probing, watching for gaps in the log stream and
   drops in throughput.
3. **Cover the matrix:** macOS, Windows (Apple Mobile Device Service) and Linux (`usbmuxd`); over
   USB, and over Wi-Fi where the device is paired (see check B).

**Pass:**
- closed ports fail with a p95 under about 100 ms;
- parallel probes behave;
- the log stream and the file transfer show no visible effect.

**If it fails**
- **Probe only when something changes:** when `os_trace_relay`'s `PidList` shows a new process, and
  when the pane opens. Add a slow sweep every ~10 s as a safety net.
- **Or invert discovery:** Inspektor already logs a line naming its port when it starts (§4.3), and
  could repeat it periodically. Eagly would read it from a filtered log tap. Whether iOS delivers
  that line reliably is the phase 4b check below.
- **Bonjour (`_inspektor._tcp`) is the last resort.** It needs the Local Network permission and an
  `NSBonjourServices` entry in the app. Whether it is reachable over USB from Windows and Linux is
  *unverified*.

### Before phase 2: smaller checks

- **A. Is a backgrounded iOS app's listener reachable?** The expectation is no while the app is
  suspended. Run the sample, connect, background it, and watch the socket. Then foreground it and
  reconnect. This confirms the *paused* state and the backfill path in §4.9.
  - **Answered (2026-10-20): no.** With the phone locked, a probe of the app's port is refused at
    once. Today Eagly shows the source as ended, then live again once the app comes back. A
    *paused* state is still to build.
- **B. Do Wi-Fi-paired iPhones work?** Does `connect_to_device` work over usbmux's network
  transport? If it does, Inspektor targets work on wireless iPhones for free. If it doesn't, the
  pane says "connect over USB" for iOS.

### Before phase 4b: can Eagly read an app's log line quickly on iOS 17, 18 and 26?

**Decides:**
- how Eagly finds a Flutter app's Dart VM service on iOS: its banner in the log, raced against
  mDNS;
- whether Inspektor's port line could replace probing if the phase-2 spike fails.

**Background**
- **What's already known:** Eagly streams iOS logs through `os_trace_relay`, so app logs reach it in
  general.
- **What's open:** latency, redaction, filtering by pid, and the newest iOS.
- **Signs of trouble:** flutter_tools' iOS code carries comments saying:
  - syslog scraping broke on iOS 13 and works again from at least iOS 16;
  - `idevicesyslog` doesn't work for iOS 17 devices connected over Wi-Fi;
  - it "stopped working with at least Xcode 26", after which flutter_tools switched to `devicectl`
    and lldb. It's unknown whether that was a device change or a tooling change.
- **Writers behave differently:**
  - Flutter's `print`, which carries the VM service banner, shows up as
    `Runner(Flutter)[pid] <Notice>: flutter: …`.
  - `os_log` replaces a dynamic string with `<private>` unless the format marks it `%{public}`.

**How to run**
1. **Build a test app** with a button that writes `INSPEKTOR-SPIKE <nonce> <monotonic ms>` in four
   ways:
   - `NSLog`;
   - `os_log` with `%{public}s`;
   - Flutter's `print`;
   - Kotlin/Native `NSLog`, from Inspektor's sample.
2. **Write the Rust tap.** Get the app's pid from `OsTraceRelayClient::get_pid_list`, call
   `start_trace(Some(pid))`, and timestamp each line matching the nonce. Run it once with `None` as
   well (the unfiltered stream Eagly uses today), to confirm the pid filter doesn't drop lines.
3. **Measure each writer** over 100 taps: the latency from tap to arrival, and whether the text
   arrives intact.
4. **Cover the matrix:**
   - iOS 17.x, 18.x and 26.x;
   - the app launched from Xcode, from the home screen, and by Eagly;
   - USB, plus Wi-Fi where the device is paired.
5. **Cross-check failures** with `pymobiledevice3 syslog live --pid <pid>`, to tell an Eagly bug
   from device behaviour.

**Pass:** Flutter's `print`, and either `NSLog` or public `os_log`, arrive intact within a second
on all three iOS versions and in every launch mode.

**If it fails:**
- Find the VM service through mDNS alone: `_dartVmService._tcp`, with the token in TXT record
  `authCode`.
- Rely on port probing alone for Inspektor.

## 9. Open questions

- **The iOS port range.** It should avoid the Dart VM service's random ports and common dev-server
  ports.
- **How the remote server is switched on.** A code flag only, or also a manifest / `Info.plist`
  key, so a UAT build can be switched on or off without a code change? And should overrides over
  the wire need a second, separate switch, since they let the connecting side change the app's
  responses?
- **Auto-attach.** Should Eagly attach to the foreground app, or to every target found?
- **Keeping the Flutter package out of release builds** (§5).
- **Host targets.** Inspektor's JVM desktop target could be inspected over loopback TCP with no
  device. That would be cheap later, but Eagly is device-centric today.
- **iOS Simulator.** An app there listens on the host's loopback directly. Eagly doesn't support
  simulators yet.

---

## Appendix A — research notes

These are condensed findings for the complementary and deferred routes, checked 2026-10-18. The
dropped routes have their own write-up in
[NETWORK_INSPECTOR_DROPPED_ROUTES.md](NETWORK_INSPECTOR_DROPPED_ROUTES.md): React Native through
Metro, a port of Android Studio's Network Inspector, and a VPN companion app.

### Android

**Global proxy**

- `settings put global http_proxy host:port` takes effect immediately. ConnectivityService loads it
  through `ProxyTracker`, which persists it to `global_http_proxy_host`, `_port`, `_exclusion_list`
  and `_pac`.
- It overrides both the Wi-Fi proxy and any proxy a VPN sets.
- The system pushes it into every app process as `http(s).proxyHost`.
- Honoured by: HttpURLConnection, OkHttp (through `ProxySelector.getDefault()`), React Native,
  Chrome and WebView (`ProxyChangeListener`), and Cronet.
- **Not** honoured by `dart:io` (flutter/flutter#26359), raw sockets, or `Proxy.NO_PROXY`.
- Clear it with `settings put global http_proxy :0`. `settings delete` returns early, which leaves
  the in-memory proxy and `global_http_proxy_host` set; that comes from reading AOSP source, not a
  device test.
- The setting survives reboots, while the `adb reverse` tunnel does not.

Sources: [ProxyTracker.java](https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/service/src/com/android/server/connectivity/ProxyTracker.java),
[ConnectivityService.java](https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/service/src/com/android/server/ConnectivityService.java),
[Proxy.java](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/net/Proxy.java),
[flutter#26359](https://github.com/flutter/flutter/issues/26359).

**CA trust**

- Apps targeting API 24 or later trust only system CAs unless their network security config opts
  in. The debug-only form is
  `<debug-overrides><trust-anchors><certificates src="user"/></trust-anchors></debug-overrides>`,
  and it applies only when the app is debuggable.
- Since Android 11, a CA can't be installed by script, not even over adb. Push the file and open
  Settings with `am start -a android.settings.SECURITY_SETTINGS`.
- Android 14 moved system CAs into the Conscrypt APEX. HTTP Toolkit's root-only workaround is a
  tmpfs over `/system/etc/security/cacerts` plus a bind-mount entered with `nsenter` into every
  zygote and app mount namespace; it lasts until reboot.
- Android 17 turns on certificate transparency by default. Injected system CAs are affected; user
  CAs and `debug-overrides` anchors are not.
- On Android, `dart:io` reads only `/system/etc/security/cacerts`, so it ignores user CAs.

Sources: [network security config](https://developer.android.com/privacy-and-security/security-config),
[HTTP Toolkit on Android 11](https://httptoolkit.com/blog/android-11-trust-ca-certificates/),
[HTTP Toolkit on Android 14](https://httptoolkit.com/blog/android-14-install-system-ca-certificate/),
[security_context_linux.cc](https://github.com/dart-lang/sdk/blob/main/runtime/bin/security_context_linux.cc).

**WebView and Chrome over CDP**

- Socket names: `chrome_devtools_remote` for Chrome (`_<pid>` is appended if the name is taken),
  `webview_devtools_remote_<pid>` for WebView, and `stetho_<process>_devtools_remote` for Stetho.
- `chrome://inspect` finds them by reading `/proc/net/unix` over adb.
- Only shell, root or the app's own uid may connect.
- The HTTP endpoints are `/json/version`, `/json/list` and `/json/protocol`.
- WebView debugging switches on automatically for debuggable apps and for eng or userdebug builds
  (`StartupTasks`, `ApkInfo.isDebugAndroidOrApp()`). Release apps need
  `setWebContentsDebuggingEnabled(true)`. Chrome's docs are out of date on this point.

Sources: [android_device_info_query.cc](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/devtools/device/android_device_info_query.cc),
[devtools_auth.cc](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/content/browser/android/devtools_auth.cc),
[StartupTasks.java](https://github.com/chromium/chromium/blob/main/android_webview/java/src/org/chromium/android_webview/StartupTasks.java),
[Network.pdl](https://github.com/ChromeDevTools/devtools-protocol/blob/master/pdl/domains/Network.pdl).

**Root only**

- eCapture: Apache-2.0, eBPF uprobes on BoringSSL and OpenSSL; aarch64 needs kernel 5.5 or later.
- HTTP Toolkit's Frida scripts: AGPL-3.0, with unpinning and a Flutter-specific script.
- `emulator -tcpdump` captures an emulator's traffic from the host without root.

Sources: [eCapture](https://github.com/gojue/ecapture),
[frida-interception-and-unpinning](https://github.com/httptoolkit/frida-interception-and-unpinning).

### iOS

**HAR logging (deferred)**

- The DVT channel `com.apple.instruments.server.services.activitytracetap`, configured with
  `enableHTTPArchiveLogging: true`, makes CFNetwork write HAR JSON to unified logging under
  category `HAR`. Long entries are split with an `<incomplete>` prefix, and the entries are read
  through `os_trace_relay`.
- From iOS 15 this needs the target app to be dev-signed (`get-task-allow`).
- It covers URLSession and CFNetwork only, so not `dart:io`.
- pymobiledevice3's `developer dvt har` plus harlogger does exactly this. That Instruments' HTTP
  Traffic instrument (WWDC21 session 10212) uses the same path is inferred from the key name.
- `idevice` has generic DVT channels and `os_trace_relay`, but no `activitytracetap` client.

Sources: [Apple: Analyzing HTTP traffic with Instruments](https://developer.apple.com/documentation/foundation/analyzing-http-traffic-with-instruments),
[harlogger](https://github.com/doronz88/harlogger),
[activity_trace_tap.py](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/dvt/instruments/activity_trace_tap.py).

**The DVT stack**

- Requirements: Developer Mode; a DDI (classic below iOS 17, personalized through TSS on 17–26,
  Cryptex1 on 27+); and an RSD tunnel on iOS 17 and later.
- `idevice` builds the tunnel in userspace:
  `CoreDeviceProxy::connect` → `create_software_tunnel()` → `RsdHandshake` →
  `RemoteServerClient::connect_rsd`. That works on Windows and Linux without admin rights, for
  iOS 17.4 and later.
- iOS 17.0–17.3 needs RemotePairing or a root `tunneld`.
- DDI files have to be sourced separately; pymobiledevice3 uses doronz88/DeveloperDiskImage.

Sources: [ios17-tunnels guide](https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/ios17-tunnels.md),
[idevice](https://github.com/jkcoxson/idevice).

**`pcapd`**

- A plain lockdown service: no Developer Mode and no DDI.
- It is a `USBOnlyService`, so it doesn't work over Wi-Fi.
- Each packet carries `pid`/`comm` and `epid`/`ecomm` (the process the traffic is attributed to).
- TLS stays encrypted.
- `idevice` already has `PcapdClient` and `PcapFileWriter`.

Sources: [pcapd.py](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/pcapd.py),
[Apple: Recording a packet trace](https://developer.apple.com/documentation/network/recording-a-packet-trace).

**`webinspector`**

- A plain lockdown service that exchanges plist `_rpc_*` messages carrying WebKit Inspector JSON.
- pymobiledevice3's `webinspector cdp` bridges it to CDP, and its Network events were confirmed on a
  real WKWebView.
- It requires the Web Inspector toggle, and `isInspectable = true` for apps built against the
  iOS 16.4+ SDK.
- `idevice` lists it as planned but has no code for it.

Sources: [webinspector.py](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/webinspector.py),
[WebKit: enabling inspection](https://webkit.org/blog/13936/enabling-the-inspection-of-web-content-in-apps/).

**Proxy routing**

- There is no USB route without a jailbreak, because usbmuxd only carries host→device
  connections.
- The manual route: same Wi-Fi network, a manual proxy, install the profile, then turn on full
  trust under Certificate Trust Settings.
- `MCInstall` can push a profile over USB, but on an unsupervised device the user still confirms
  it on the device. `idevice` has no `MCInstall`.
- A global HTTP proxy payload is supervised-only. A Wi-Fi payload's proxy applies to one SSID.

Sources: [HTTP Toolkit iOS](https://httptoolkit.com/docs/guides/ios/),
[global proxy payload](https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.proxy.http.global.yaml),
[MASTG-TECH-0063](https://github.com/OWASP/mastg/blob/master/techniques/ios/MASTG-TECH-0063.md).

**SDKs that send to a desktop**

- Proxyman's Atlantis (Apache-2.0) and Pulse (MIT) browse Bonjour (`_Proxyman._tcp`,
  `_pulse._tcp`) and open a TCP connection *to* the Mac. They don't use usbmux.
- Atlantis frames each message as a `UInt64` length followed by gzipped JSON.

Sources: [Atlantis Transporter.swift](https://github.com/ProxymanApp/atlantis/blob/main/Sources/Transporter.swift),
[Pulse](https://github.com/kean/Pulse).

### Flutter and React Native

**Dart VM service**

- The `dart:io` extensions:
  - `ext.dart.io.httpEnableTimelineLogging`;
  - `getHttpProfile(updatedSince)`, polled;
  - `getHttpProfileRequest(id)`, which includes bodies;
  - `clearHttpProfile`;
  - the socket and WebSocket profile equivalents.
- It works in debug and profile builds but not release (`dart.vm.product`).
- `cupertino_http`, `cronet_http` and `ok_http` report through `http_profile`.
- The banner reads `The Dart VM service is listening on http://127.0.0.1:PORT/TOKEN=/`.
- The service binds to device loopback only, and the auth token is the first path segment.
- On iOS it is also advertised through mDNS as `_dartVmService._tcp`, with TXT record `authCode`.

Sources: [service_extension.md](https://dart.googlesource.com/sdk/+/stable/runtime/vm/service/service_extension.md),
[DartIOExtension](https://api.flutter.dev/flutter/vm_service/DartIOExtension.html),
[vmservice_server.dart](https://github.com/dart-lang/sdk/blob/main/sdk/lib/_internal/vm/bin/vmservice_server.dart),
[FlutterDartVMServicePublisher.mm](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterDartVMServicePublisher.mm).

**React Native**

- RN 0.83 added a Network panel to React Native DevTools, using plain CDP through Metro's inspector
  proxy. This is behind §5's correction to Inspektor's plan.
- Reading that stream from Eagly was considered and dropped. See
  [React Native through Metro](NETWORK_INSPECTOR_DROPPED_ROUTES.md#react-native-through-metro).

Sources: [RN 0.83](https://reactnative.dev/blog/2025/12/10/react-native-0.83).

### Proxy libraries and comparable products

**Libraries**

- **`hudsucker`:** MIT/Apache-2.0, version 0.25.0 (July 2026). HTTP/1.1, opt-in HTTP/2, WebSocket,
  and an `rcgen` CA.
- **`http-mitm-proxy` and `proxelar`:** smaller alternatives.
- **mitmproxy:** MIT, but the standalone binaries are 54–119 MB.
- **mockttp:** needs Node.
- **ProxyPin:** Apache-2.0. A Flutter UI over a Dart proxy core, with a Kotlin VPN service; the
  closest reference design to Eagly.

**Products**

- **HTTP Toolkit:** automates Android setup over adb, using a VPN app and root for the system CA.
  iOS setup is manual.
- **Proxyman:** Atlantis, plus on-device VPN apps.
- **Reqable:** built with Flutter. It handles Flutter apps through a VPN "enhanced mode" and needs
  root for the CA.

Sources: [hudsucker](https://github.com/omjadas/hudsucker), [ProxyPin](https://github.com/wanghongenpin/proxypin),
[HTTP Toolkit Android](https://httptoolkit.com/docs/guides/android/), [Proxyman Flutter](https://docs.proxyman.com/debug-devices/flutter),
[Reqable Flutter guide](https://reqable.com/blog/2024/06/27/post).

## Appendix B — proxy design notes (for when phase 5 is revisited)

- **Engine:** `hudsucker` inside `rust/`, streamed to Dart the way the iOS log relay is.
- **CA key:** generate the CA per install and keep it in the app support directory with `0600`
  permissions. Never ship a shared key.
- **Android routing as a lease.** A small `app_process` helper holds a socket open to Eagly and
  resets the proxy to `:0` when that socket dies. scrcpy-server does the same: its `CleanUp`
  process restores `show_touches`, `stay_on_while_plugged_in` and `screen_off_timeout` on unplug,
  as `strings` on the bundled jar's `classes.dex` shows. Also reset the proxy on every connect and
  at launch.
- **Emulators:** launch with `-http-proxy` from the Emulator manager. That routes *all* TCP,
  Flutter included. On AOSP and Google APIs images, `adb root` allows a system CA.
- **Android CA install:** push the CA to Downloads, open Security settings, and show the
  `debug-overrides` snippet.
- **QUIC:** clients don't use HTTP/3 through an explicit proxy. A VPN or TUN mode would have to
  block UDP 443.
- **iOS:** serve a CA download page from the proxy and guide the user through the Wi-Fi proxy
  setting and Certificate Trust Settings.
