# Network inspector: dropped routes

> This is a companion to [NETWORK_INSPECTOR.md](NETWORK_INSPECTOR.md). Everything here was
> evaluated for [#72](https://github.com/ShreyashKore/eagly/issues/72) and dropped on 2026-10-18.
> It's written up so that revisiting an option starts from the facts rather than a fresh research
> pass. Claims that could not be confirmed are marked *unverified*.

There are two kinds of dropped option:

- **[Capture routes](#capture-routes):** other ways to get at an app's traffic. These were dropped
  once Inspektor became the primary route.
- **[Transports](#transports-between-inspektor-and-eagly):** other ways for Inspektor's data to
  reach Eagly, plus the authentication design. These were dropped once Inspektor was scoped to
  development builds (NETWORK_INSPECTOR.md §1.1).

**Capture routes**

| Route | What it would have given | Dropped because | Revisit if |
|---|---|---|---|
| [React Native through Metro](#react-native-through-metro) | React Native `fetch`/XHR/image traffic, with no package | It duplicates React Native DevTools' own Network panel, can evict it, sees only the JS layer, and works only in debug builds | Inspektor's React Native package stalls, or RN debuggers support several clients by default |
| [A port of Android Studio's Network Inspector](#a-port-of-android-studios-network-inspector) | OkHttp, HttpURLConnection and gRPC traffic of any debuggable Android app, with no code changes | Inspektor's OkHttp adapter covers the same stacks, and the port is a large native surface built on internal APIs | Users want zero-code native Android capture and won't add Inspektor |
| [VPN companion app](#vpn-companion-app) | Traffic from apps that ignore the system proxy, routed into the desktop proxy | It only feeds the proxy, which is deferred, and it doesn't fix Flutter's CA trust on unrooted devices | The proxy exists and users need apps that ignore the system proxy |

**Transports**

| Option | What it would have given | Dropped because | Revisit if |
|---|---|---|---|
| [Journal file in the app's storage](#journal-file-in-the-apps-storage) | No discovery, no socket servers, no auth, and history that survives a crash | `run-as` and `house_arrest` refuse the UAT and dev-release builds Inspektor must serve | History from before an app restart matters on debug builds |
| [Device log as the transport](#device-log-as-the-transport) | Almost no new code; any runtime can write a log line | ~4 KB per entry, it evicts the app's own logs, it ends up in bug reports, and it's one-way | Never as the transport; a one-line announcement is still useful |
| [App connects out to Eagly](#app-connects-out-to-eagly-metros-direction) | Metro's model: on Android, no discovery and no per-app forwards | No route from an iPhone to the computer over USB; needs Wi-Fi and a LAN listener | The iOS Simulator, or Wi-Fi-only iOS inspection |
| [Authentication on the socket](#authentication-on-the-socket-superseded) | Other apps on the device locked out | Inspektor is scoped to development builds, and that trade is accepted, as with Metro | Inspektor is ever meant for builds real users install |

## Capture routes

### React Native through Metro

#### What it is

React Native 0.83 (2025-12-10) added a Network panel to React Native DevTools. The data comes from
inside the app: `jsinspector-modern`'s `NetworkHandler.cpp` emits Chrome DevTools Protocol (CDP)
events — `Network.requestWillBeSent`, `requestWillBeSentExtraInfo`, `responseReceived`,
`dataReceived`, `loadingFinished` and `loadingFailed`. It answers `Network.getResponseBody` from an
on-device preview buffer capped at 100 MB.

The route considered here was for Eagly to be a second consumer of that stream.

#### How it works

1. **The app connects out to Metro.** In a debug build, the app connects to the inspector proxy in
   Metro's dev-middleware on the developer's machine. Android reaches it through
   `adb reverse tcp:8081 tcp:8081`; iOS reaches it over the network.
2. **Metro lists the pages.** `GET http://localhost:8081/json` (or `/json/list`) returns the
   debuggable pages. Each has a `webSocketDebuggerUrl` of the form
   `ws://localhost:8081/inspector/debug?device=…&page=…`.
3. **A client subscribes.** A CDP client opens that WebSocket and sends `Network.enable`. Events
   stream back, and bodies are fetched with `Network.getResponseBody`.

Metro runs on the host, so Eagly would have needed no tunnel to the device, only HTTP and a
WebSocket to localhost.

#### What Eagly would have built

- **Discovery:** poll Metro's `/json/list` while the Network pane is open. Metro uses port 8081 by
  default, but projects change it, so the port would be configurable. Pages would be matched to
  Eagly's devices using the device and app fields Metro reports.
- **Transport and mapping:** a WebSocket CDP client. That is the same client phase 4a builds for
  Android WebViews and Chrome, so the mapping from CDP Network events to Eagly's model would be
  shared.
- **Cost after phase 4a:** small. Only discovery and device matching would be new.

#### What it covers, and what it doesn't

- **Covers:** `fetch`, `XMLHttpRequest` and `<Image>` loads made through React Native's networking
  module.
- **Doesn't cover:**
  - Traffic from native modules and native SDKs that bring their own HTTP client (analytics,
    payments, image libraries with their own pipeline). The inspector hooks the JS-facing networking
    layer, not the process's HTTP stack as a whole.
  - Expo's `expo/fetch`. Expo ships its own "Expo Network" panel for it.
  - WebSocket traffic in 0.83. The `webSocket*` events exist on RN's main branch; which release
    ships them is *unverified*.
  - Mocking and throttling. As of the 0.87 docs, neither is implemented.
  - Release builds. The inspector stack only runs in debug.

#### Why it was dropped

1. **It duplicates a first-party tool.** React Native DevTools shows the same data, from the same
   source, and most RN developers already have it open. Eagly would only add "next to the device
   logs".
2. **It can kick the developer's debugger off.** If the device doesn't report
   `supportsMultipleDebuggers`, the inspector proxy disconnects the existing debugger when a new one
   attaches. Eagly connecting would silently end the developer's DevTools session, or the other way
   round.
3. **Inspektor's React Native package covers more.**
   - It captures at the native client React Native's networking module uses: the `OkHttpClient`
     supplied through `OkHttpClientProvider.setOkHttpClientFactory` on Android, and the session
     configured through `RCTSetCustomNSURLSessionConfigurationProvider` on iOS.
   - It therefore sees the same JS `fetch`/XHR requests, and it also works in release/QA builds that
     ship it and supports overrides.
   - A native SDK with its own client can be covered by installing Inspektor's OkHttp or URLSession
     adapter in that client. The Metro route can never see such SDKs.
4. **It's debug-only and needs Metro.** It captures nothing in QA builds, or when the JS bundle is
   embedded and Metro isn't running.
5. **The APIs keep moving.** `jsinspector-modern`, the inspector proxy's endpoints and its page
   metadata have all changed across recent React Native releases, so Eagly would be chasing them.
6. **It depends on a connection Eagly has already disrupted.** Metro's `adb reverse` tunnel has
   dropped when Eagly made bursts of adb calls (see `_deviceInfoScript` in AGENTS.md). Any route
   built on Metro's connection inherits that sensitivity.

#### When to revisit

- If Inspektor's React Native package stalls, and RN users want *something* in Eagly without
  adding a package.
- If React Native's debugger stack supports several clients by default, so Eagly could watch
  without evicting DevTools.
- The cost would then be small, because the CDP client and mapping already exist after phase 4a.

#### Sources

- [React Native 0.83 release post](https://reactnative.dev/blog/2025/12/10/react-native-0.83)
- [React Native DevTools docs](https://reactnative.dev/docs/react-native-devtools)
- [Debugging docs](https://reactnative.dev/docs/debugging)
- [Inspector proxy README](https://github.com/facebook/react-native/blob/main/packages/dev-middleware/src/inspector-proxy/__docs__/README.md)
- [`NetworkHandler.cpp`](https://github.com/facebook/react-native/blob/main/packages/react-native/ReactCommon/jsinspector-modern/network/NetworkHandler.cpp)
- [`OkHttpClientProvider.kt`](https://github.com/facebook/react-native/blob/main/packages/react-native/ReactAndroid/src/main/java/com/facebook/react/modules/network/OkHttpClientProvider.kt)
- [`RCTHTTPRequestHandler.h`](https://github.com/facebook/react-native/blob/main/packages/react-native/Libraries/Network/RCTHTTPRequestHandler.h)

### A port of Android Studio's Network Inspector

#### What it is

Android Studio's Network Inspector (under App Inspection) shows the OkHttp, HttpURLConnection and
gRPC traffic of a debuggable app with no changes to the app. Its device-side half is open source
under Apache-2.0, in AOSP's `platform/tools/base` (branch `mirror-goog-studio-main`, directory
`app-inspection/inspectors/network`). It builds to `network-inspector.jar` with d8
`--min-api 26`; the BUILD file comments "only supported on O+ devices".

The route considered was for Eagly to run that inspector, or an equivalent, without Studio.

#### How Studio runs it

1. **Copy the agent into the app.** Studio's transport daemon uses `run-as <package>` to copy
   `perfa.jar` and `libjvmtiagent_<abi>.so` into the app's `code_cache` directory.
2. **Attach to the running process.** It runs
   `cmd activity attach-agent <process> <path>/libjvmtiagent_<abi>.so=<args>`. ART only allows this
   for debuggable apps (ART TI, Android 8.0 and later).
3. **Hook the HTTP stacks.** The agent hosts the **androidx.inspection** runtime. Its `ArtTooling`
   registers method entry and exit hooks by rewriting bytecode through JVMTI. The network inspector
   uses these to:
   - wrap the connection returned by `URL.openConnection()`, covering HttpURLConnection;
   - add its own interceptor to the list returned by `OkHttpClient.networkInterceptors()`, covering
     OkHttp 2 and 3+;
   - hook gRPC's `ManagedChannelBuilder`, `AndroidChannelBuilder` and `OkHttpChannelBuilder`
     (`forAddress` and `forTarget`), and scan for gRPC channels that already exist.
4. **Send events back.** Events are protobuf messages defined in `network-inspector.proto`, carried
   to Studio through the transport daemon. The inspector also supports rules that rewrite
   responses.

#### What Eagly would have built

- **A JVMTI host:** our own native agent library for each ABI (arm64-v8a, armeabi-v7a, x86_64,
  x86), built with the NDK and shipped the way `scrcpy-server` is.
- **A loader:** it would load `network-inspector.jar` plus the androidx.inspection runtime with a
  `DexClassLoader`. That runtime is `DefaultArtTooling` and its native `art_tooling` library, whose
  README says it "is provided by Android Studio in runtime".
- **A replacement for the transport daemon's role:** an abstract socket inside the app, reached
  from Eagly with `adb forward`, carrying the protobuf commands and events.
- **Eagly side:** protobuf decoding, and mapping onto Eagly's model.
- **Attach logic:** `run-as` to copy, then `attach-agent` on the running process.
  - Requests made before the agent attaches are missed.
  - Catching app start-up would need a startup agent (`am start --attach-agent`). The exact API
    level where that became available is *unverified*.
- **Cost:** moderate-to-high, plus ongoing upkeep.

#### What it would cover

- **Apps:** debuggable apps on API 26 and later, with no code changes.
- **Stacks:** HttpURLConnection; OkHttp and everything built on it (Retrofit, Ktor's OkHttp engine,
  Coil's and Glide's OkHttp integrations, React Native's Android networking); and gRPC.
- **Not covered:** Cronet, WebView, Flutter's `dart:io`, Ktor's CIO engine, native C/C++
  networking, and builds that aren't debuggable.

#### Why it was dropped

1. **Inspektor's OkHttp adapter covers the same stacks for the cost of one dependency line.** It
   also works in QA builds that aren't debuggable, and uses the same override engine on every
   platform.
2. **It rests on internal contracts.** The androidx.inspection runtime is documented as something
   Studio provides at runtime. The inspector's proto and hooks change with Studio releases. No
   project reuses the inspector outside Studio.
3. **It adds a native build to Eagly's toolchain.** That means the NDK and four ABIs in CI,
   alongside the Rust crate.
4. **The bytecode hooks match by name.** A debug build with R8 enabled can rename the OkHttp classes
   the hooks target. How Studio's inspector copes with that is *unverified*.
5. **It's Android only.** The iOS counterpart would have been HAR logging through DVT, which is a
   separate project and also deferred.
6. **It might collide with Studio.** Running two inspection agents in one process, Studio's App
   Inspection and Eagly's, is untested (*unverified*).

#### When to revisit

- **Trigger:** many Eagly users want zero-code capture of debuggable native Android apps, and won't
  add Inspektor.
- **Try the smaller variant first: inject Inspektor itself.**
  1. Use the same JVMTI attach and exit-hook trick to load `inspektor-core` and `inspektor-okhttp`
     into the debuggable process.
  2. In the `OkHttpClient.networkInterceptors()` exit hook, add Inspektor's interceptor.

  The app then speaks the Inspektor protocol, so Eagly needs no new client code. This still needs
  the JVMTI host, but not Studio's proto, its transport, or its inspector jar.

#### Sources

- [Network inspector source (AOSP)](https://android.googlesource.com/platform/tools/base/+/refs/heads/mirror-goog-studio-main/app-inspection/inspectors/network/)
- [Transport daemon `daemon.cc`](https://android.googlesource.com/platform/tools/base/+/refs/heads/mirror-goog-studio-main/transport/native/daemon/daemon.cc)
- [androidx.inspection](https://github.com/androidx/androidx/tree/androidx-main/inspection/inspection)
- [ART TI](https://source.android.com/docs/core/runtime/art-ti)
- [Network Inspector user docs](https://developer.android.com/studio/debug/network-profiler)

### VPN companion app

#### What it is

An Android app that uses
[`VpnService`](https://developer.android.com/reference/android/net/VpnService) gets a TUN interface,
and every IP packet from every app passes through it. The app ends each TCP connection and forwards
it to a desktop MITM proxy, either over Wi-Fi or through `adb reverse` to `127.0.0.1` so it works
over USB.

Unlike the global HTTP proxy setting, this also catches apps that ignore the system proxy: Flutter's
`dart:io`, callers that pass `Proxy.NO_PROXY`, and raw sockets.

#### How existing tools do it

**HTTP Toolkit's Android app** (`tech.httptoolkit.android.v1`, AGPL-3.0, v1.7.0)

- **Starting and stopping:** over adb with
  `am start -a tech.httptoolkit.android.ACTIVATE -d "https://android.httptoolkit.tech/connect/?data=<url-safe base64 JSON>"`,
  and stopped with `…DEACTIVATE`. The activity alias requires `INJECT_EVENTS`, which the shell user
  has.
- **Configuration:** the JSON carries `addresses`, `port`, `localTunnelPort`, `enableSocks` and
  `certFingerprint`.
- **Choosing a route to the desktop:**
  - The app tries each address by fetching `http://android.httptoolkit.tech/config` through it, and
    checks the returned `certificate` against the fingerprint.
  - If none works, it uses `127.0.0.1:localTunnelPort`. The desktop keeps that alive with
    `adb reverse`, re-applied every 2 s.
- **What gets redirected:** TCP on ports 80, 443, 4443, 8000, 8080, 8443, 8888 and 9000. On Android
  10+ it also sets the VPN's HTTP proxy.
- **What doesn't:**
  - The MTU is set to 1279, which deliberately disables IPv6.
  - UDP, and with it QUIC, goes straight out without inspection.
- **Certificates:** it checks trust but doesn't install the CA.

**PCAPdroid** (GPL-3.0, v2.0.2) captures through `VpnService` without root, and is built to be
controlled by other tools:

- **Control:** `am start -n com.emanuelef.remote_capture/.activities.CaptureCtrl -e action start|stop|get_status …`.
- **Consent:** the user is asked on every start unless an `api_key` is passed (supported since
  1.8.6). Android 17 adds a local-network prompt.
- **Forwarding:** `socks5_enabled`, with `socks5_proxy_host` and `socks5_proxy_port`, sends all TCP
  to a SOCKS5 proxy. Combined with `adb reverse`, that is a no-root path into a desktop proxy.
- **QUIC:** `block_quic` (`never`, `always` or `to_decrypt`) forces a fallback to TCP.
- **Decryption:** its own TLS decryption runs mitmproxy on the device and needs a user CA.

**ProxyPin** (Apache-2.0) is a Flutter app with a Kotlin VPN service and a Dart proxy core. It's
the reference to read if Eagly ever writes its own.

**Proxyman** (6.4+) and **Reqable** use the same idea to catch Flutter apps on Android.

#### What Eagly would have built

One of two things:

- **Drive PCAPdroid in SOCKS5 mode.** This needs no code of our own on the device. Its GPL license
  is fine for a separate app driven by intents. Eagly's proxy would need a SOCKS5 front end.
- **Write our own VPN app.** That means an APK to build, sign, version and install alongside Eagly.
  Unlike `scrcpy-server`, a `VpnService` can't be an `app_process` jar: it has to be an installed
  app that declares the service.

Either way, it would also need QUIC blocking (dropping UDP 443), DNS and IPv6 handling, and a UX for
the consent dialog.

#### What it would cover

- All TCP traffic from all apps, whether or not they honour the proxy, routed to the desktop proxy.
- Decryption would still depend on each app trusting the proxy's CA (see below).

#### Why it was dropped

1. **Its only job is to feed the proxy, which is deferred.** Without a proxy, there's nothing to
   route traffic to.
2. **It doesn't fix Flutter on unrooted devices.** It solves Flutter's *routing* problem, since
   `dart:io` ignores the proxy, but not its *trust* problem.
   - On Android, `dart:io` trusts only `/system/etc/security/cacerts`.
   - Without root there's no way to add a system CA, so the TLS handshake fails.
   - Reqable and Proxyman need root, or an emulator, for exactly this reason.
   - Flutter is covered instead by Inspektor's Dart package and the Dart VM service.
3. **Consent and exclusivity.** Android shows a VPN consent dialog that can't be scripted, and only
   one VPN can be active at a time. Starting ours drops the user's corporate VPN.
4. **Another artifact to ship.** An installable APK must be built, signed, versioned and kept
   compatible with Android's VPN and local-network rules. HTTP Toolkit's app can't be bundled
   because of AGPL-3.0, and PCAPdroid can only be driven, not shipped.
5. **Cheaper options cover the cases where it would help:**
   - On emulators, `emulator -http-proxy` routes *all* TCP with no app at all.
   - For apps that honour the proxy, the global proxy setting (held as a lease, see
     [Appendix B](NETWORK_INSPECTOR.md#appendix-b--proxy-design-notes-for-when-phase-5-is-revisited))
     is enough.

#### When to revisit

- Only after the proxy exists (phase 5), and if users need apps that ignore the system proxy on
  rooted devices or emulators.
- Try driving PCAPdroid in SOCKS5 mode first. Write our own app only if that isn't enough.

#### Sources

- [httptoolkit-android manifest](https://github.com/httptoolkit/httptoolkit-android/blob/main/app/src/main/AndroidManifest.xml)
- [`ProxySetup.kt`](https://github.com/httptoolkit/httptoolkit-android/blob/main/app/src/main/java/tech/httptoolkit/android/ProxySetup.kt)
- [`SessionManager.java`](https://github.com/httptoolkit/httptoolkit-android/blob/main/app/src/main/java/tech/httptoolkit/android/vpn/SessionManager.java)
- [HTTP Toolkit server's adb interceptor](https://github.com/httptoolkit/httptoolkit-server/blob/main/src/interceptors/android/android-adb-interceptor.ts)
- [PCAPdroid app API](https://github.com/emanuele-f/PCAPdroid/blob/master/docs/app_api.md)
- [PCAPdroid TLS decryption](https://emanuele-f.github.io/PCAPdroid/tls_decryption)
- [ProxyPin](https://github.com/wanghongenpin/proxypin)
- [Proxyman: Flutter](https://docs.proxyman.com/debug-devices/flutter)
- [Reqable: Flutter guide](https://reqable.com/blog/2024/06/27/post)
- [Dart `security_context_linux.cc`](https://github.com/dart-lang/sdk/blob/main/runtime/bin/security_context_linux.cc)

## Transports between Inspektor and Eagly

These were the other ways considered for getting Inspektor's data to Eagly, once the capture route
was settled. The socket in the app won; see NETWORK_INSPECTOR.md §1.1 and §4. All were decided on
2026-10-18.

### Journal file in the app's storage

#### What it is

Publish/subscribe with a file as the topic. Inspektor appends one JSON line per transaction event
to a capped, rotating file in its own storage, and Eagly tails it. The file would be something like
`files/inspektor/journal.jsonl` on Android, or a folder under `Library/Application Support/` on
iOS.

#### How Eagly would read it

- **Android:** `adb exec-out run-as <package> tail -F files/inspektor/journal.jsonl`. Checked on an
  API 36 emulator:
  - `run-as` works on a debuggable app (`com.rn`);
  - toybox `tail` supports `-f` and `-F`, and `-F` follows the file by name, so it survives
    rotation.
- **iOS:** `house_arrest`'s `vend_container(bundle_id)` gives AFC access to the app's whole storage
  folder. `idevice` has it behind its `house_arrest` feature, which Eagly doesn't enable yet. Eagly
  would read the new bytes every ~0.5 s.
- **Overrides:** Eagly writes an overrides file into the same folder (`run-as … sh -c 'cat > …'`,
  or an AFC write), and Inspektor watches it with a `FileObserver` or a dispatch source. Inspektor
  already keeps its overrides as a JSON file (KStore).

#### What it had going for it

- **No discovery, no socket servers, no auth.** The OS already limits `run-as` to debuggable apps
  and to adb, and limits container access to the paired computer.
- **A tiny SDK side in every runtime:** append to a file, watch a file.
- **History from the start of the file.** It stays readable while an iOS app is suspended, and
  after it crashes.

#### Why it was dropped

It only reaches the builds the OS lets a developer into, and Inspektor's scope includes UAT and
dev-release builds:

- `run-as` refuses apps that aren't debuggable. A dev-flavour release build handed to QA usually
  isn't.
- Container access through `house_arrest` is limited to dev-signed (`get-task-allow`) apps, which
  rules out ad-hoc, TestFlight and enterprise UAT builds. This matches Xcode's "Download
  Container", but it is *unverified*.

The socket works in any build that ships Inspektor, so it won.

#### When to revisit

If history from just before an app restart matters on debug builds. The socket already backfills
from Inspektor's database once the app is running again, so this would only add the gap before a
restart.

### Device log as the transport

#### What it is

Inspektor writes each transaction as tagged JSON into logcat or the iOS unified log, and Eagly
filters those lines out of the log streams it already reads.

#### What it had going for it

- **Every runtime can write a log line:** Kotlin, Dart's `print`, React Native's JS.
- **Eagly needs almost no new code.**
- **The OS already restricts readers:** only adb or the paired computer can read the device log.

#### Why it was dropped

- **Size.**
  - On Android, one logcat entry carries at most 4068 bytes (`adb logcat -g` on an API 36
    emulator), and longer messages are cut.
  - The iOS unified log also cuts long messages. Apple's own HAR logging splits entries with an
    `<incomplete>` prefix for this reason.
  - Bodies would need splitting into many entries.
- **It pushes out the app's own logs.** The log buffers are shared and small: 2 MiB each on that
  emulator, and often less on phones (*unverified*). When a buffer fills, logd drops entries from
  the noisiest app first, which is the one being debugged.
- **It leaks into files people share.** Android bug reports and iOS sysdiagnose archives include
  the logs, and both get attached to tickets.
- **It's one-way.** There are no bodies on demand and no override editing. On iOS there is no
  history either, because Eagly's `os_trace_relay` stream is live only.

#### What survives

A short announcement line is still a useful *discovery* hint. Inspektor's start-up line naming its
socket or port (NETWORK_INSPECTOR.md §4.3) is exactly that, and it's the fallback named in the
phase-2 probe spike.

### App connects out to Eagly (Metro's direction)

#### What it is

Eagly is the server and Inspektor dials it, the way React Native apps dial Metro.

#### How it would work

- **Android:**
  - Eagly runs `adb reverse tcp:<port> tcp:<port>` once per device.
  - Inspektor connects to `127.0.0.1:<port>`. Emulators can also reach the host at `10.0.2.2`.
  - There's no discovery and no per-app forward: apps announce themselves when they connect.
- **iOS:**
  - usbmux only carries connections from the computer to the device, so over USB the app has no
    way to reach Eagly.
  - The app would need Wi-Fi, Eagly would have to listen on the LAN, and the app would find it
    through Bonjour (`_inspektor._tcp`).
  - Bonjour needs the Local Network permission and an `NSBonjourServices` entry in the app.
    Proxyman's Atlantis and Pulse work this way.

#### Why it was dropped

- **Eagly is USB-first**, and this direction can't do iOS over USB.
- **Supporting both directions would double the transport code in every SDK.**
- **Listening on the LAN is exactly the exposure behind Metro's CVE-2025-11953.**

#### When to revisit

- For the iOS Simulator, where an app can reach the computer's loopback directly.
- If Wi-Fi-only iOS inspection becomes a goal.

### Authentication on the socket (superseded)

> **Restored on 2026-10-25 as protocol 2**, in a simpler form; see NETWORK_INSPECTOR.md §4.3.
> Android checks the peer's uid. On iOS, the server writes one token per start rather than per
> connection, and repeats the line for every connection. There is no trust-on-first-use fallback.

#### What it was

The protocol's first draft authenticated every connection, because a listening socket is reachable
by other apps on the device.

- **`peercred`, on Android:**
  - The server reads `SO_PEERCRED` and accepts only uid 0 (adbd running as root), uid 2000 (shell)
    or its own uid. Connections that arrive through `adb forward` come from shell.
  - This is the rule Chromium's `devtools_auth.cc` applies to its DevTools sockets.
  - Kotlin uses `LocalSocket.getPeerCredentials()`.
  - Dart would use `Socket.getRawOption(RawSocketOption(RawSocketOption.levelSocket, 17,
    Uint8List(12)))`. `SO_PEERCRED` is 17 on every Android ABI, and the 12 bytes are
    `struct ucred { int32 pid; uint32 uid; uint32 gid; }`, little-endian. This is *unverified*.
- **`logtoken`, on iOS and as Dart's fallback:**
  - For each connection, the server writes a one-time token to the device log as a public line.
  - Eagly reads it from a log tap filtered by pid (`os_trace_relay`'s `start_trace(Some(pid))`, or
    `adb logcat`) and sends it back.
  - Only adb or the paired computer can read the device log, so only they learn the token.
- **Fallback if iOS log lines proved unreliable: trust on first use.** The app asks "Allow Eagly to
  inspect this app?" once per computer, and keeps a key in the Keychain, like adb's RSA prompt. A
  token written into the app's container through `house_arrest` was a second option, for
  dev-signed apps only (*unverified*).
- **`hello` came before authentication.** It carried only public identity, so discovery could
  label a target without authenticating.

#### Why it was dropped

Inspektor is scoped to development builds: production uses the no-op artifacts, and elsewhere the
server needs an explicit opt-in. So the protocol accepts the same trade Metro makes
(NETWORK_INSPECTOR.md §4.3). Dropping it also removed two spikes that had to run before phase 2:
whether Dart can read `SO_PEERCRED`, and whether iOS delivers the token line.

#### What stays possible

The Kotlin Android server can still reject peers by uid as local hardening. That needs no protocol
change, and Eagly doesn't notice.

#### When to restore

Restore it if Inspektor is ever meant to run in builds real users install, or if the opt-in proves
too easy to leave on. Check two things first:

1. **Can Dart read `SO_PEERCRED`?**
   - Bind `ServerSocket.bind(InternetAddress('@inspektor_spike', type: InternetAddressType.unix),
     0)`, and read the peer's uid on each connection.
   - Connect through `adb forward tcp:0 localabstract:inspektor_spike`; expect uid 2000, or 0 when
     adbd runs as root.
   - Connect from a second app; expect that app's uid, and a rejection.
   - Repeat on API 26, 29, 34 and 36, on a phone and an emulator, in debug and release builds.
2. **Does iOS deliver the token line?** Run the phase-4b log check in NETWORK_INSPECTOR.md §8,
   with the token line as the payload.
