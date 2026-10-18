# Network Inspector: plan

> **Status: plan only. Nothing here is implemented yet.** It tracks
> [#72](https://github.com/ShreyashKore/eagly/issues/72). It was written on 2026-10-18 from research
> against primary sources: AOSP, Chromium, the Dart SDK, WebKit, React Native, pymobiledevice3 and
> the `idevice` crate. Claims that could not be confirmed are marked *unverified*. Sources are in
> [Appendix A](#appendix-a--research-notes).

**Goal.** Let developers debug their own app's HTTP traffic from Eagly the way Chrome DevTools'
Network tab works: a live list with headers, bodies, timing and export. It should work on Android
and iOS, whatever the app is written in: native, Kotlin Multiplatform, Flutter or React Native.
Covering WebViews is a stretch goal. Covering other people's apps is a further stretch.

## TL;DR

- **Eagly becomes [Inspektor](https://github.com/ShreyashKore/inspektor)'s desktop viewer.**
  Inspektor is being made capture-agnostic: OkHttp, URLSession, Ktor, React Native through those
  two, and Flutter in Dart. We control both ends, so the cheapest route is:
  1. The SDK captures traffic inside the app process. That needs no proxy and no certificates,
     and works in any build type that ships the SDK.
  2. The SDK serves its transactions over a local socket.
  3. Eagly reaches that socket through adb or usbmux and renders it.
- **The wire protocol is the contract between the two projects; there is no shared library.** It
  must be implementable in Kotlin (JVM and Native) and in Dart, so it is plain length-prefixed JSON
  over a stream socket. §4 is the v1 draft; the spec itself should live in the Inspektor repo.
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

## 1. What changed once Inspektor went multi-client

The first pass of this plan treated Inspektor as one Ktor-only source among many. It leaned on a
proxy and on platform tooling for everything else. Inspektor is now planned to cover OkHttp,
URLSession, Ktor, React Native and Flutter (see its
[multi-client plan](https://github.com/ShreyashKore/inspektor/blob/refactor-into-smaller-modules/.agents/notes/multi-client-modularization-plan.md)),
and that changes the order:

| Route | First pass | Now | Why |
|---|---|---|---|
| Inspektor SDK → Eagly | Phase 3, Ktor apps only | **Primary**, phases 0–3 | Covers every framework. Traffic is already decrypted, the on-device database gives history, and overrides come with it. |
| Dart VM service | Phase 1, primary for Flutter | Complement, phase 4. For Flutter debug/profile apps *without* Inspektor | It needs no package. Inspektor's Dart client adds release/QA builds, overrides and history. |
| Android WebView and Chrome over CDP | Phase 1 | Complement, phase 4, first in line | Chromium's in-process network stack is invisible to every Inspektor adapter. |
| React Native through Metro's CDP | Phase 1 | [Dropped](NETWORK_INSPECTOR_DROPPED_ROUTES.md#react-native-through-metro) | Inspektor's React Native package covers it, and RN 0.83 ships its own Network panel. |
| Desktop MITM proxy | Phase 2 | Deferred, phase 5 | Mocking for your own app now comes from Inspektor. The proxy only adds *other* apps. |
| iOS HAR logging (DVT) | Phase 4 | Deferred. Build the DVT stack for its other uses first | The URLSession adapter covers your own iOS apps. |
| iOS WebView (`webinspector`) | Optional | Optional (unchanged) | The only route to WKWebView traffic. |
| JVMTI port of Studio's Network Inspector | Optional | [Dropped](NETWORK_INSPECTOR_DROPPED_ROUTES.md#a-port-of-android-studios-network-inspector) | Inspektor's OkHttp adapter covers the same stacks. |
| `pcapd` connection metadata | Optional | Optional (unchanged) | The only way to see other iOS apps with no setup. |
| VPN companion app | Optional | [Dropped](NETWORK_INSPECTOR_DROPPED_ROUTES.md#vpn-companion-app) unless the proxy is built | Its only job is to feed the proxy. |
| Eagly's data model | Shaped like CDP | **Shaped like Inspektor's transaction** (HAR-like). CDP and the VM service map onto it | The primary source should map with no loss, including an override's "original vs replaced" values. |

Seen from Inspektor's side, Eagly *is* the "remote viewer" that its plan lists as the escape hatch.
It lets Flutter and React Native apps be inspected without shipping Compose Multiplatform UI into
them.

## 2. Capture routes

This section lists every route that was evaluated, so deferred ones don't have to be researched
again.

| Route | What it sees | What it needs | Android | iOS | Status |
|---|---|---|---|---|---|
| Inspektor SDK | Whatever its adapter hooks: OkHttp, URLSession, Ktor, React Native (through those two), Dart `HttpClient` / `http` / dio | The dependency | ✅ | ✅ | **Primary** |
| CDP to `*_devtools_remote` sockets | Chrome, debuggable WebViews, Stetho apps. Full Network domain, bodies included | Nothing, for debuggable apps | ✅ | – | Phase 4 |
| Dart VM service HTTP profile | `dart:io`, plus `cupertino_http` / `cronet_http` / `ok_http` through `http_profile` | A debug or profile build | ✅ | ✅ | Phase 4 |
| `pcapd` | Per-packet process name, DNS, SNI and byte counts; a `.pcap` | USB | – | ✅ | Optional |
| Desktop MITM proxy | Anything that honours the proxy and trusts the CA | CA trust. On Android, the app must opt in. On iOS, the same Wi-Fi network | ✅ | ⚠️ | Deferred |
| iOS HAR logging (DVT `activitytracetap`) | Every URLSession request of a dev-signed app, bodies included | Developer Mode, a developer disk image (DDI), and the iOS 17.4+ tunnel | – | ✅ | Deferred |
| `com.apple.webinspector` | WKWebView and Safari | The Web Inspector toggle, and `isInspectable` in the app | – | ✅ | Optional |
| DVT network monitor | Per-process connections and byte counters | DDI and tunnel | – | ✅ | With the DVT stack |
| JVMTI agent (Studio's inspector) | OkHttp, HttpURLConnection and gRPC in debuggable apps | API 26+ | ✅ | – | [Dropped](NETWORK_INSPECTOR_DROPPED_ROUTES.md#a-port-of-android-studios-network-inspector) |
| React Native through Metro | React Native `fetch` / XHR | RN 0.83 or later | ✅ | ✅ | [Dropped](NETWORK_INSPECTOR_DROPPED_ROUTES.md#react-native-through-metro) |
| VPN companion app | All TCP from all apps, routed into the proxy | The proxy; a consent dialog; root for Flutter's CA | ✅ | – | [Dropped](NETWORK_INSPECTOR_DROPPED_ROUTES.md#vpn-companion-app) |
| eBPF (eCapture) or Frida | Everything | Root | ✅ | – | Out of scope |
| `CFNETWORK_DIAGNOSTICS` | Headers only | A DVT launch | – | ✅ | Rejected: HAR logging does strictly more |

### Coverage once phases 1–4 land

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

## 3. Architecture in Eagly

The new pieces slot into the layering described in AGENTS.md:

```
tunnels            AdbTool.forward / removeForward       moved out of ScrcpyClient
                   Rust: iOS port forward over usbmux     new, under rust/src/api/
discovery          services/network/target_discovery.dart  per device; polls only while the pane is open
sources            services/network/network_source.dart    interface, one implementation per route
                     ├─ inspektor/  InspektorSource         protocol client (§4)
                     ├─ cdp/        CdpSource               phase 4
                     └─ dart_vm/    DartVmSource            phase 4
feature controller features/network/network_controller.dart  extends FeatureController; lazy in DeviceSessionController
view               features/network/network_feature_view.dart; WorkspacePane.network
iOS backend        services/ios/ios_network_service.dart   interface, Rust implementation only (the CLIs are going away)
```

### 3.1 Model

`NetworkTransaction` follows Inspektor's `HttpTransaction`, which is already shaped like HAR, so
the primary source maps one to one. Its fields:

- **Identity:** a key made of target, store id and transaction id.
- **Request:** method; URL plus scheme, host and path; protocol; headers; content type; size; and
  a body that is fetched only when needed. Headers are an ordered list of name/value pairs, because
  duplicates and order both matter.
- **Response:** code, message, headers, content type, size, a lazily fetched body, TLS version and
  cipher suite.
- **Timing:** request and response timestamps and the duration. Optionally the phases: DNS,
  connect, TLS, send, wait and receive.
- **State:** pending, complete or failed, plus the error.
- **Override:** which override applied, and the original request and response values.
- **Provenance:** the source kind (`inspektor`, `cdp`, `dart_vm`) and the adapter (`okhttp`,
  `urlsession`, `ktor`, `dart:io`, …).
- **Later:** WebSocket frames, redirect chains and initiator.

Bodies are fetched on demand and cached under a byte budget. The transaction list lives in a ring
buffer, like `LogBuffer`. Eagly both exports and imports HAR 1.2. Inspektor already exports HAR,
so a file from a QA device opens in Eagly from day one.

The other sources map onto the same model:

- **CDP:** `requestWillBeSent` → `responseReceived` → `loadingFinished`/`loadingFailed`, with
  bodies from `getResponseBody`.
- **Dart VM service:** the `HttpProfileRequest` objects.

### 3.2 Targets and discovery

A *target* is one capturing endpoint in one process: the device, the process, and the kind of
source. Discovery produces a per-device list of targets, like `chrome://inspect`. The pane lists
them for the user to pick from; whether Eagly attaches to the foreground app automatically is a
later UI decision.

| Target | How Eagly finds it |
|---|---|
| Android, Inspektor | `grep @inspektor_ /proc/net/unix`, run as a single `adb shell`. |
| Android, CDP (phase 4) | The same scan, looking for names ending in `_devtools_remote`. |
| Android, Dart VM (phase 4) | The "Dart VM service is listening on" banner in logcat. |
| iOS, Inspektor | Probe a fixed port range over usbmux from Rust; a refused connect returns at once. The handshake names the app, and `os_trace_relay`'s `PidList` maps a pid to its process name. |
| iOS, Dart VM (phase 4) | mDNS `_dartVmService._tcp` (TXT record `authCode`), raced against the log banner the way flutter_tools does it. |

- `adb shell` can read `/proc/net/unix` on API 36; this was checked on a Play-image emulator.
  Google Messages' *production* build exposes `@stetho_…_devtools_remote` sockets there, so the
  discovery mechanism works on current Android.
- Each Android poll is a single `adb shell`. AGENTS.md records why: a burst of adb clients contends
  with `adb reverse` and drops Metro.
- Discovery polls about every 2 s, and only while the Network pane is open. Controllers are lazy,
  so this needs nothing extra.

**Features stay isolated.** Discovery lives in `services/network/`, not in the Logs feature. When
it needs log lines (the iOS auth token, the VM-service banner), it opens **its own filtered log
tap**: `os_trace_relay` `start_trace(Some(pid))` on iOS, and `adb logcat -T 1 -s <tag>` on
Android. The Network pane never depends on a Logs pane being open.

### 3.3 Tunnels

- **Android:** `adb forward tcp:0 localabstract:<name>`. `ScrcpyClient._adbForward` and
  `_adbForwardRemove` already do this. Move them to `AdbTool` and share them. The forward is
  removed when its target goes away.
- **iOS:** a Rust equivalent of `iproxy`. It listens on `127.0.0.1:0`, pipes each accepted
  connection to `UsbmuxdConnection::connect_to_device(port)`, and returns the host port. The
  `usbmuxd` feature is already enabled.

With both tunnels in place, `InspektorSource` is the same Dart `Socket` code on both platforms.

### 3.4 Source interface

```dart
abstract interface class NetworkSource {
  NetworkSourceCapabilities get capabilities; // overrides? backfill? request bodies?
  Stream<NetworkSourceEvent> get events;      // upserts, clears, connection status
  Future<NetworkBody> body(String transactionId, NetworkBodyPart part);
  Future<void> clear();
  Future<void> dispose();
}
```

Capabilities let the UI hide override editing for CDP and VM-service targets, and show "history
available" only where backfill exists.

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

### 3.6 Privacy

- Captured traffic is kept in memory only. Nothing is written unless the user exports it.
- HAR export offers header redaction for `Authorization`, `Cookie` and `Set-Cookie`. Inspektor's
  `sanitizeHeader` already redacts on the device, before anything reaches the wire.
- Under `--record-mode`, the pane redacts the same headers. That mode exists for product videos.

## 4. Eagly ↔ Inspektor protocol, v1 draft

> **The canonical spec should live in the Inspektor repo**, as `docs/REMOTE_PROTOCOL.md` plus
> fixtures. Every capture implementation conforms to it, and Eagly is just one client. Once it
> moves, shrink this section to a summary and a link, so there aren't two copies to drift apart.

### 4.1 Principles

- **Platform sockets only.** It must be implementable in Kotlin/JVM, Kotlin/Native and Dart with
  nothing but platform sockets. `inspektor-core` has no Ktor dependency and shouldn't gain one for
  this.
- **The server runs in the app and the client in Eagly.** That is the only direction that works
  over USB on both platforms: iOS has no device→host route without a jailbreak.
- **Additive evolution.** Clients ignore unknown fields and unknown events.
- **No body bytes on the wire unless asked for.**

### 4.2 Transport and discovery

| | Android | iOS |
|---|---|---|
| Listener | Abstract Unix socket `@inspektor_<pid>_<runtime>`, where `runtime` is `kotlin` or `dart` | TCP on `127.0.0.1`, on the first free port of a small fixed range (about 8 ports; choose once) |
| Kotlin | `LocalServerSocket(name)`, which is abstract by default | POSIX sockets or Network.framework |
| Dart | `InternetAddress('@inspektor_…', type: InternetAddressType.unix)`. Abstract sockets are supported on Android since Dart 2.x (SDK CHANGELOG) | `ServerSocket.bind(InternetAddress.loopbackIPv4, port)` |
| How Eagly finds it | `/proc/net/unix` | Probing the port range over usbmux |
| How Eagly reaches it | `adb forward tcp:0 localabstract:…` | The Rust usbmux forward |

Don't end socket names in `_devtools_remote`. `chrome://inspect` would list the socket and then
fail to speak CDP to it.

### 4.3 Authentication

Payloads include auth headers and bodies, so another app on the device must not be able to read
them.

- **`peercred` (Android):**
  - The server reads `SO_PEERCRED` and accepts uid 0 (adbd running as root), uid 2000 (shell) and
    its own uid. Connections that arrive through `adb forward` come from shell.
  - This is the rule Chromium's `devtools_auth.cc` applies to its own DevTools sockets.
  - Kotlin uses `LocalSocket.getPeerCredentials()`.
  - Dart would read the option through `RawSocketOption` / `getRawOption` with `SOL_SOCKET` and
    `SO_PEERCRED`. That is *unverified* (spike 2); if it doesn't work, Dart falls back to
    `logtoken`.
- **`logtoken` (iOS, and the fallback):**
  1. On each new connection, the server generates a one-time token.
  2. It writes the token to the device log as a public `os_log` line (logcat on Android).
  3. Eagly reads it from its filtered log tap and sends it back.

  Only a host that can read the device log through lockdown or adb learns the token. iOS apps can
  connect to each other's loopback ports, which is why a bare TCP listener isn't enough.
- **`hello` comes before auth.** It carries only public identity and no traffic, so discovery can
  label a target without authenticating.

### 4.4 Framing

Each frame is a 4-byte big-endian unsigned length followed by that many bytes of UTF-8 JSON, one
object per frame. A frame is at most 16 MiB; larger bodies are read in ranges with `body.get`.

### 4.5 Handshake

The server speaks first:

```json
{"type": "hello", "protocol": 1,
 "sdk":   {"name": "inspektor", "version": "0.9.0", "runtime": "kotlin",
           "adapters": ["okhttp", "ktor"], "overrides": true},
 "app":   {"id": "com.example.app", "name": "Example", "version": "1.4.0 (51)",
           "pid": 12345, "process": "com.example.app"},
 "store": {"id": "7c0e2f4a-…", "persistent": true, "oldestId": "1201"},
 "auth":  ["peercred"]}
```

What happens next depends on the auth method:

- **`logtoken`:** the client sends `{"type": "auth", "method": "logtoken", "token": "…"}`.
- **`peercred`:** the server has already accepted or rejected the peer, so the client sends
  nothing.

The server then sends `{"type": "ready"}`, or closes the connection after sending
`{"type": "error", "code": "unauthorized"}`.

If Eagly can't speak the server's `protocol` version, it says which side needs updating. A server
can also refuse a client with `{"type": "error", "code": "unsupported_protocol", "supported": [1]}`.

### 4.6 Methods and events

The shape follows JSON-RPC:

- **Client request:** `{"id": 7, "method": "…", "params": {…}}`.
- **Reply:** `{"id": 7, "result": …}` or `{"id": 7, "error": {"code": "…", "message": "…"}}`.
- **Server push:** `{"type": "event", "event": "…", "data": {…}}`.

| Method | Params | Result |
|---|---|---|
| `subscribe` | `afterId?`, `inlineBodyLimit` (bytes; default 0) | `{}`. Backfill after `afterId` arrives first as `transaction.updated` events, then live events follow. |
| `transactions.list` | `afterId?`, `limit` | A page of transactions without bodies, plus `hasMore` |
| `transactions.get` | `ids` | Those transactions, without bodies |
| `body.get` | `id`, `part` (`request`, `response`, `originalRequest`, `originalResponse`), `offset?`, `length?` | `{"encoding": "utf8" \| "base64", "data", "size", "truncated"}` |
| `transactions.clear` | – | `{}` |
| `overrides.list` | – | `[Override]` |
| `overrides.put` | `Override` | The stored `Override`, including its id |
| `overrides.delete` | `id` | `{}` |
| `ping` | – | `{}` |

| Event | Data |
|---|---|
| `transaction.started` | The transaction with its request half filled in |
| `transaction.updated` | The full transaction as currently known: response, completion or error |
| `transactions.cleared` | – |
| `overrides.changed` | `[Override]` |
| Later: `websocket.frame` | `id`, `direction`, `opcode`, `data` |

Each event carries the transaction's whole current state, not a diff. Without bodies a transaction
is small, and upserts are simpler on both sides.

### 4.7 Transaction object

It mirrors `HttpTransaction`, with headers flattened from `Set<Map.Entry<String, List<String>>>`
into ordered pairs:

```json
{"id": "1842", "adapter": "okhttp", "method": "POST",
 "url": "https://api.example.com/v1/login", "protocol": "h2",
 "requestDate": "2026-10-18T09:12:03.412Z", "responseDate": "2026-10-18T09:12:03.643Z", "tookMs": 231,
 "request":  {"headers": [["content-type", "application/json"], ["authorization", "***"]],
              "contentType": "application/json", "size": 64, "body": "available"},
 "response": {"code": 200, "message": "OK", "headers": [["content-type", "application/json"]],
              "contentType": "application/json", "size": 1543, "body": "available",
              "tlsVersion": "TLSv1.3", "cipherSuite": "TLS_AES_128_GCM_SHA256"},
 "error": null,
 "timings": {"dnsMs": 4, "connectMs": 38, "tlsMs": 51, "sendMs": 1, "waitMs": 120, "receiveMs": 17},
 "override": {"id": "ov-3", "original": {"response": {"code": 500, "headers": [], "body": "available"}}}}
```

`body` is one of `available`, `empty`, `truncated` or `not_captured`. `not_captured` covers a log
level below `BODY`, one-shot or duplex bodies, and filtered calls. When the body is `available`
and fits `inlineBodyLimit`, it is inlined as `bodyData` with an `encoding` field. `timings` and
`override` are optional.

### 4.8 Overrides

The wire form is Inspektor's `Override` JSON, which today is the KStore file format:

- `RequestType`;
- matchers: `UrlMatcher`, `UrlRegexMatcher`, `HostMatcher`, `PathMatcher`;
- `OverrideAction`: `FixedRequest`, `FixedResponse` or `FixedRequestResponse`.

Pin this format in the spec. A Dart implementation must produce and consume exactly the same JSON.
Eagly's override editor works against that schema, and is hidden when `hello.sdk.overrides` is
false.

### 4.9 Backfill and reconnect

- **Kotlin core:**
  - `store.id` is a UUID kept *inside* the database, in a one-row table added by a migration. A
    recreated database therefore gets a new id.
  - Rows are `INTEGER PRIMARY KEY AUTOINCREMENT`, so ids are never reused, even after `deleteAll`.
    `afterId` is enough as a cursor and needs no "updated" column.
  - Eagly remembers `(store.id, lastId)` per target. On reconnect it calls `subscribe(afterId)`,
    then `transactions.get` for any transactions it still holds as pending.
- **Dart, in memory:** `persistent: false`. Ids are monotonic per process, and backfill is
  whatever the ring buffer still holds.
- **iOS apps stop accepting connections when suspended in the background.** Eagly marks the target
  *paused*, not gone, until its pid disappears, and backfills when the app resumes.

Backfill is an advantage neither a proxy nor the VM service has: requests made before Eagly
attached, such as during app start-up, are still there.

### 4.10 Conformance fixtures

Golden transcripts are files of JSON frames for each case:

- handshake;
- auth success and auth failure;
- backfill followed by live events;
- body ranges;
- an override round trip;
- an unsupported protocol version.

They live in the Inspektor repo. The Kotlin and Dart servers are tested against them in CI, and
Eagly's client tests use a copy pinned to a protocol version.

## 5. What Eagly needs from Inspektor

**Must have, blocking phase 2 (milestone I-1):**

1. **A remote server in `inspektor-core`, on Android and iOS, started automatically, with an
   opt-out in `InspektorCoreConfig`.**
   - On Android it starts through androidx.startup; `ContextInitializer` already exists.
   - On iOS it starts when the first `TransactionRecorder` is created.
   - Keeping it in core avoids another no-op twin, and core is already debug-only through the
     no-op artifacts. *Alternative:* a separate `:inspektor-remote` module with no public symbols;
     nothing names it, so it needs no twin either.
2. **A live event stream out of `TransactionRecorder`.** The recorder already inserts, then
   updates; emit an event after each. Also persist `store.id` (§4.9).
3. **Header sanitisation applied in core, before anything reaches the transport.** The
   modularization plan already puts sanitisation there.
4. **The `adapter` recorded on every transaction.**

**Should have, for phase 3 onward:**

- **Override create/delete over the wire (milestone I-2).** `OverrideRepository` already keeps a
  warm `StateFlow` cache; it only needs `put` and `delete` exposed.
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

**React Native**, which wraps the OkHttp and URLSession modules:

- **Android:** `OkHttpClientProvider.setOkHttpClientFactory`, which exists in RN's
  `OkHttpClientProvider.kt`. It has to be called before the networking module initialises.
- **iOS:** `RCTSetCustomNSURLSessionConfigurationProvider`, declared in `RCTHTTPRequestHandler.h`.
  It hands RN a session configuration whose `protocolClasses` include Inspektor's `URLProtocol`.
  That scopes the hook to RN's own session instead of a global `URLProtocol` registration.
- **iOS UI:** with Eagly as the viewer, the RN package could ship without the Compose UI on iOS.
  XCFramework weight is risk 12 in Inspektor's plan.

**Corrections to Inspektor's modularization plan:**

- **Risk 15 is out of date.** React Native DevTools shipped a Network panel in **RN 0.83, released
  2025-12-10.** It covers `fetch`, XHR and images, but has no WebSocket events and no mocking, and
  it runs in debug builds only. Seeing requests is therefore no longer a differentiator on React
  Native. Overrides, persistence, release/QA builds and a desktop viewer still are.
- **Flipper's repository was archived on 2025-09-26.**

## 6. Phased plan

Each phase ships on its own. Where a phase depends on an Inspektor milestone (I-n from §5), it says
so.

### Phase 0: agree the protocol

- Move §4 into the Inspektor repo, and settle the iOS port range, the socket names and the auth
  methods.
- Write the golden transcripts.
- **Exit:** the spec and fixtures are merged in Inspektor, and this section is a link.

### Phase 1: Eagly foundation, with no device work

- **`features/network/`:**
  - `NetworkController`, a `FeatureController` created lazily in `DeviceSessionController`.
  - `NetworkFeatureView`: a plain list and detail view. Polish comes later.
  - `WorkspacePane.network`, following *Adding a pane* in docs/WORKSPACE_LAYOUT.md.
- **`services/network/`:** the model, `NetworkSource`, a ring buffer with a byte budget for bodies,
  and HAR export and import.
- **Protocol client:** an `InspektorProtocol` codec (framing and messages) and an
  `InspektorSource`, both tested against a **fake in-process server** that replays the fixtures.
- **Tests:**
  - the codec against the fixtures;
  - the controller against a fake source: upsert, merge, clear, fetching bodies, and the ring
    buffer evicting old entries;
  - a golden file for HAR export.
- **Exit:** `fvm flutter test` is green, and the pane shows fixture traffic in a debug build.

### Phase 2: Inspektor over the wire (needs I-1)

- **Android:**
  - Move `AdbTool.forward` and `removeForward` out of `ScrcpyClient`.
  - Discovery through `/proc/net/unix`.
  - The `peercred` path.
- **iOS, behind a new `IosNetworkService` interface in `services/ios/`.** The implementation is
  Rust only, following docs/IOS_RUST_MIGRATION.md; no CLI version, since the CLIs are being
  removed.
  - `start_ios_port_forward(udid, device_port) -> host_port` and `stop_ios_port_forward`.
  - `probe_ios_ports(udid, ports) -> Vec<u16>`.
  - A filtered log tap for `logtoken`: `os_trace_relay` with `start_trace(Some(pid))`.
  - `PidList`, for process names.
- **Target lifecycle:**
  - backfill and reconnect;
  - process death;
  - iOS suspension, which shows the target as paused;
  - removing forwards when targets go away.
- **Device test** in `test/device/`, against Inspektor's `:sample` on a real Android phone and an
  iPhone.
- **Exit:** Inspektor's sample shows up live in Eagly, with backfill after a reconnect. On Android
  it runs Ktor and OkHttp; on iOS, Ktor and URLSession.

### Phase 3: overrides and richer detail (needs I-2; I-3 parts as they land)

- An override list and editor in Eagly, plus "mock this response" on a transaction.
- Previews for binary bodies, a timing waterfall, and "Copy as cURL". The format should match
  Inspektor's `Curl.kt`.
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
- **The iOS `logtoken` route depends on reading the device log** (spike 1). If Eagly can't read
  app logs on some iOS version, the fallback is a trust-on-first-use prompt in the app, with the
  host key kept in the Keychain. A token written into the app's container through `house_arrest`
  is a second option, for dev-signed apps only (*unverified*).
- **iOS apps are suspended in the background**, so live capture stops. The paused state and
  backfill cover the gap, and the UI should say so rather than look broken.
- **Polling adb and usbmux costs the device link.** Mitigation: one shell per Android poll, polling
  only while the pane is open, and probing only the fixed port range.
- **Memory.** Mitigation: Eagly's ring buffer and body budget, and clearing the VM-service profile
  after each fetch.
- **Moving the forward helpers out of `ScrcpyClient` could regress mirroring.** Mitigation: the
  move is mechanical; check it with the existing mirror tests and one device session.

## 8. Spikes to run before committing

Run these before phase 2. Each one answers a single question that decides part of §4, and each has
a fallback, so a failed spike changes the design but not the plan. The first three decide the
protocol; the two smaller checks shape the UX.

How to run them:

- **Rust spikes:** a throwaway binary crate that depends on `idevice` with the same version and
  features as `rust/Cargo.toml`. It can't live inside `rust/`: that crate builds only `cdylib` and
  `staticlib`, so examples there can't link it.
- **App spikes:** small test apps. Inspektor's `:sample` is the natural host once it has a server.

### Spike 1: can Eagly read an app's log line quickly on iOS 17, 18 and 26?

**Decides:**
- `logtoken` authentication on iOS (§4.3);
- the banner fast path for iOS discovery: the Dart VM service in phase 4b, and the fallback in
  spike 3.

**Background**
- `logtoken` only works if the token line reaches Eagly quickly and isn't redacted. Eagly already
  streams iOS logs through `os_trace_relay`, so app logs reach it in general. The open questions
  are latency, redaction, pid filtering and the newest iOS.
- flutter_tools' iOS code carries comments saying:
  - syslog scraping broke on iOS 13 and works again from at least iOS 16;
  - `idevicesyslog` doesn't work for iOS 17 devices connected over Wi-Fi;
  - it "stopped working with at least Xcode 26", after which flutter_tools switched to `devicectl`
    and lldb.

  It's unknown whether that last one was a device change or a tooling change.
- Different writers behave differently:
  - Kotlin/Native can call `NSLog` or `os_log`.
  - A Dart-only Inspektor has Flutter's `print`, which the engine routes into the device log (it
    shows up as `Runner(Flutter)[pid] <Notice>: flutter: …`), or FFI to `syslog(3)`.
  - `os_log` replaces a dynamic string with `<private>` unless the format marks it `%{public}`.

**How to run**
1. **Build a test app** with a button that writes `INSPEKTOR-SPIKE <nonce> <monotonic ms>` in five
   ways:
   - `NSLog`;
   - `os_log` with `%{public}s`;
   - `syslog(LOG_NOTICE, …)`;
   - Flutter's `print`;
   - Kotlin/Native `NSLog`, from Inspektor's sample.
2. **Write the Rust tap.** Get the app's pid from `OsTraceRelayClient::get_pid_list`, call
   `start_trace(Some(pid))`, and print when each line matching the nonce arrives. Run it once with
   `None` as well (the unfiltered stream Eagly uses today), to confirm the pid filter doesn't drop
   lines.
3. **Measure each writer** over 100 taps: the latency from tap to arrival, and whether the text
   arrives intact rather than as `<private>` or truncated.
4. **Cover the matrix:**
   - iOS 17.x, 18.x and 26.x;
   - the app launched from Xcode (debugger attached), from the home screen, and by Eagly;
   - USB, plus Wi-Fi where the device is paired.
5. **Cross-check failures** with `pymobiledevice3 syslog live --pid <pid>`, to tell an Eagly bug
   from device behaviour.

**Pass:** on all three iOS versions and in every launch mode, `os_log` with `%{public}` and `NSLog`
arrive intact within one second with the pid filter on. Record which Dart writer works; the
protocol names it.

**If it fails**
- **If only some writers fail:** pin the protocol to a writer that works, and name it in §4.3.
- **If no writer works on some iOS version:** switch iOS authentication to trust-on-first-use,
  the same model as adb's RSA prompt.
  1. On the first connection from a host, the app shows "Allow Eagly to inspect this app?".
  2. It stores a per-host key in the Keychain, so it doesn't ask again.

  A second option is writing the token into the app's container through `house_arrest`, but that
  works only for dev-signed apps (*unverified*).

### Spike 2: can Dart read the connecting peer's uid on Android?

**Decides:** whether a Dart-only Inspektor on Android uses `peercred`, like the Kotlin one, or falls
back to `logtoken` (§4.3).

**Background**
- **The Kotlin side is easy:** it gets the peer from `LocalSocket.getPeerCredentials()`.
- **The Dart side has no direct API.** `dart:io` has no peer-credential call, but
  `Socket.getRawOption(RawSocketOption(level, option, value))` exposes a raw `getsockopt`.
- **The values involved:** on Linux and every Android ABI, `SOL_SOCKET` is 1
  (`RawSocketOption.levelSocket`) and `SO_PEERCRED` is 17. The value is
  `struct ucred { int32 pid; uint32 uid; uint32 gid; }`: 12 bytes, little-endian.
- **What's unknown:**
  - whether `getRawOption` works on a Unix-domain socket in Dart, and from which Dart version;
  - whether SELinux allows the call inside an app.
- **The uids to expect:** connections that come through `adb forward` should arrive as uid 2000
  (shell) on user builds, and as uid 0 when adbd runs as root.

**How to run**
1. **Build a minimal Flutter app** that binds
   `ServerSocket.bind(InternetAddress('@inspektor_spike', type: InternetAddressType.unix), 0)`.
   On each connection, it reads the peer with
   `getRawOption(RawSocketOption(RawSocketOption.levelSocket, 17, Uint8List(12)))`, decodes pid,
   uid and gid, and `print`s them.
2. **Check discovery:** `adb shell grep @inspektor_spike /proc/net/unix` should list the socket.
3. **Connect from the host:** run `adb forward tcp:0 localabstract:inspektor_spike`, then connect
   with `nc 127.0.0.1 <port>`. Expect uid 2000, or 0 when adbd runs as root.
4. **Connect from another app:** a second tiny app connects with `LocalSocket`. Expect that app's
   uid, and expect the server to reject it.
5. **Cover the matrix:**
   - API 26, 29, 34 and 36;
   - an arm64 phone, and an x86_64 emulator on both user and userdebug images;
   - Flutter debug and release builds.

**Pass:** every row reports the right uid.

**If it fails:** the Dart implementation uses `logtoken` on Android.
- **It's equally safe.** Since Android 4.1 an app can read only its own logcat entries, so only
  shell and root can see the token.
- **It's cheap.** Flutter's `print` already lands in logcat under the `flutter` tag. The cost is a
  filtered `adb logcat` tap on Eagly's side for each connection.

### Spike 3: how fast does a usbmux probe of a closed port fail?

**Decides:** whether iOS discovery can poll a port range (§3.2, §4.2), and how often.

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
- **Or invert discovery:** the app logs a banner with its port when it starts listening, and again
  periodically, and Eagly reads it from the log tap. This leans on spike 1.
- **Bonjour (`_inspektor._tcp`) is the last resort.** It needs the Local Network permission and an
  `NSBonjourServices` entry in the app. Whether it is reachable over USB from Windows and Linux is
  *unverified*.

### Smaller checks

- **A. Is a backgrounded iOS app's listener reachable?** The expectation is no while the app is
  suspended. Run the sample, connect, background it, and watch the socket. Then foreground it and
  reconnect. This confirms the *paused* state and the backfill path in §4.9.
- **B. Do Wi-Fi-paired iPhones work?** Does `connect_to_device` work over usbmux's network
  transport? If it does, Inspektor targets work on wireless iPhones for free. If it doesn't, the
  pane says "connect over USB" for iOS.

## 9. Open questions

- **The iOS port range.** It should avoid the Dart VM service's random ports and common dev-server
  ports.
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
