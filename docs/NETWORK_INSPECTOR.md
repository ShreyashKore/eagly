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
- **Development builds only, and no authentication.** Production releases ship Inspektor's no-op
  artifacts. In debug, UAT and dev-release builds, the remote server runs only when the app turns
  it on. Like Metro, the protocol trusts whoever connects (§4.3). UAT builds are what keep the
  socket: the journal-file and device-log alternatives can't serve them (§1.1).
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

### 1.1 Scope decision: development builds only, no authentication (2026-10-18)

Inspektor is a development tool, like Chucker.
- **Production releases** ship the no-op artifacts, so there is no server code in them at all.
- **Debug, UAT and dev-release builds** include the remote server, which starts only when the app
  opts in.

Within that scope:

- **Authentication is dropped from the protocol.** This is the same trade Metro makes: while an
  opted-in build runs, anything that can reach its socket can read the traffic and set overrides.
  - The socket is loopback TCP (iOS) or an abstract Unix socket (Android). So "anything" means the
    host, through adb or usbmux, and other apps on the same device. It never means the network.
  - §4.3 lists what bounds the risk.
- **The socket stays, and the app stays the server.** UAT and dev-release builds are usually
  neither debuggable (Android) nor dev-signed (iOS). That rules out the alternatives:

  | Transport | Debug builds | UAT / dev-release builds | iOS over USB | Bodies, overrides, backfill |
  |---|---|---|---|---|
  | **Socket in the app; Eagly connects (chosen)** | ✅ | ✅ | ✅ through usbmux | ✅ |
  | App connects out to Eagly (Metro's direction) | ✅ | ✅ | ❌ No device→host route; needs Wi-Fi and a LAN listener | ✅ |
  | Journal file in app storage, tailed by Eagly | ✅ | ❌ `run-as` and `house_arrest` refuse these builds | ✅ | Partly |
  | Device log | ✅ | ✅ | ✅ | ❌ One-way, ~4 KB per entry, floods the app's own logs |

  The rejected transports, and the authentication design this decision removed, are written up in
  [the dropped-routes doc](NETWORK_INSPECTOR_DROPPED_ROUTES.md#transports-between-inspektor-and-eagly).
- **What this removes from the plan:** the authentication handshake, Eagly's iOS log-token tap,
  and two of the three spikes that had to run before phase 2.
- **What stays:** discovery, the tunnels, backfill, and the iOS paused state.

## 2. Capture routes

This section lists every route that was evaluated, so deferred ones don't have to be researched
again.

| Route | What it sees | What it needs | Android | iOS | Status |
|---|---|---|---|---|---|
| Inspektor SDK | Whatever its adapter hooks: OkHttp, URLSession, Ktor, React Native (through those two), Dart `HttpClient` / `http` / dio | The dependency, with its remote server turned on, in a non-production build | ✅ | ✅ | **Primary** |
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

The feature keeps its own `data/` and `services/` folders, the way the Logs feature does. Paths
below are under `lib/features/network/` unless they start with `lib/`. ✓ marks what phase 1 built.

```
model              data/network_transaction.dart          ✓ NetworkTransaction, headers, bodies, timings
                   data/network_transaction_store.dart    ✓ capped store + body cache with a byte budget
                   data/har.dart                          ✓ HAR 1.2 encode / decode
sources            services/network_source.dart           ✓ interface, one implementation per route
                     ├─ services/inspektor/                ✓ frame codec, messages, InspektorSource (§4)
                     ├─ services/har_source.dart           ✓ a HAR file opened from disk
                     ├─ services/cdp/  CdpSource              phase 4
                     └─ services/dart_vm/  DartVmSource       phase 4
discovery          services/inspektor/inspektor_watcher.dart ✓ Android; polls only while the pane is open
                   services/inspektor/inspektor_endpoint.dart ✓ endpoints, tunnels, /proc/net/unix parsing
device facade      lib/services/device_session_repository.dart ✓ findInspektorEndpoints / openInspektorTunnel
tunnels            lib/services/tools/adb_tool.dart          ✓ forwardToAbstractSocket / removeForward / grepProcNetUnix
                   rust/src/api/                             phase 2, iOS; port forward over usbmux
iOS backend        lib/services/ios/ios_network_service.dart phase 2, iOS; interface, Rust implementation only
feature controller network_controller.dart                ✓ FeatureController; lazy in DeviceSessionController
view               network_feature_view.dart, components/ ✓ WorkspacePane.network, rail, command palette
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

**Features stay isolated.** Discovery lives in the Network feature's `services/`, not in Logs. When
it needs log lines (the Dart VM service banner in phase 4b), it opens **its own filtered log
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

> **The canonical spec now lives in the Inspektor repo, as
> [`docs/REMOTE_PROTOCOL.md`](https://github.com/ShreyashKore/inspektor/blob/main/docs/REMOTE_PROTOCOL.md).**
> It is on Inspektor's `feature/remote-inspection` branch until that merges, together with the
> Kotlin server that implements it. Where the two differ, that spec wins. This section is the
> original draft: once the Inspektor branch merges, shrink it to a summary and a link, so there
> aren't two copies to drift apart.
>
> **Settled since this draft:**
> - the iOS and desktop port range is 38470–38477;
> - the Android socket is `@inspektor_<pid>_kotlin`;
> - the switch is `InspektorRemote.start()`;
> - `store.id` is kept in a file beside the database (§4.9).

### 4.1 Principles

- **Platform sockets only.** It must be implementable in Kotlin/JVM, Kotlin/Native and Dart with
  nothing but platform sockets. `inspektor-core` has no Ktor dependency and shouldn't gain one for
  this.
- **The server runs in the app and the client in Eagly.** That is the only direction that works
  over USB on both platforms: iOS has no device→host route without a jailbreak.
- **No authentication.** The scope and the safeguards that replace it are in §4.3.
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

### 4.3 Trust model: no authentication

There is no authentication step. Whoever reaches the socket can read every transaction and
create or delete overrides. That covers Eagly through adb or usbmux, and also other apps on the
same device, because iOS apps can connect to each other's loopback ports and Android apps can
connect to each other's abstract sockets. This was decided in §1.1.

What bounds it:

- **Production releases have no server.** They ship the no-op artifacts, which contain no
  transport code.
- **The server is opt-in.** It starts only when the app turns it on in Inspektor's config (§5).
- **It is reachable only on the device.**
  - The iOS listener binds `127.0.0.1`, and the Android listener is an abstract Unix socket, so
    the network can't reach either. That is unlike Metro, which listens on every interface.
  - It isn't HTTP, so a web page in a browser can't talk to it usefully. That is the attack
    Metro's `Origin` check exists for.
- **It is visible.** When the server starts, Inspektor writes one line to the device log naming
  its socket or port. On Android, Inspektor's existing notification can say so too.

Two rules keep "a browser can't use it" true. Both are requirements on every server
implementation:

1. **Close the connection on a frame that's too large or isn't valid JSON** (§4.4). That's what
   turns "a web page can send bytes" into "a web page gets disconnected".
   - A browser can only put an HTTP request on the socket, and the first 4 bytes of one are
     text.
   - Read as a length, `GET ` is about 1.1 GiB and `POST` about 1.25 GiB, far over the frame
     cap.
   - The page controls only the request body, which comes after headers the browser writes
     itself, so it can never forge a valid first frame.
   - The page can't read anything back either. `hello` isn't an HTTP response, so `fetch` fails,
     and a WebSocket attempt never gets its `101 Switching Protocols` reply.
2. **Any HTTP or WebSocket endpoint added later needs a token,** like the Dart VM service's.
   Adding one, for example so a browser-based viewer can connect, removes the protection above.
   Flutter's VM service binds to loopback and still requires a secret token in its URL for
   exactly this reason.

Optional hardening, outside the protocol: the Kotlin Android server can reject peers whose uid
isn't 0 (adbd as root), 2000 (shell, which is how `adb forward` connections arrive) or its own.
That is a few lines with `LocalSocket.getPeerCredentials()`, and it's the rule Chromium applies to
its DevTools sockets. Eagly doesn't notice either way.

If authentication is ever needed again, the superseded design is written up in
[the dropped-routes doc](NETWORK_INSPECTOR_DROPPED_ROUTES.md#authentication-on-the-socket-superseded).
A later protocol version could add it, with `hello` announcing the method.

### 4.4 Framing

Each frame is a 4-byte big-endian unsigned length followed by that many bytes of UTF-8 JSON, one
object per frame. A frame is at most 16 MiB; larger bodies are read in ranges with `body.get`.

When either side receives a frame longer than 16 MiB, or one that isn't a JSON object, it closes
the connection without replying. For the server this is a security rule (§4.3). For Eagly it means
a broken peer fails fast instead of being buffered.

### 4.5 Handshake

The server speaks first:

```json
{"type": "hello", "protocol": 1,
 "sdk":   {"name": "inspektor", "version": "0.9.0", "runtime": "kotlin",
           "adapters": ["okhttp", "ktor"], "overrides": true},
 "app":   {"id": "com.example.app", "name": "Example", "version": "1.4.0 (51)",
           "pid": 12345, "process": "com.example.app"},
 "store": {"id": "7c0e2f4a-…", "persistent": true, "oldestId": "1201"}}
```

The client can send requests as soon as `hello` arrives. There is no authentication step (§4.3).

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
  - `store.id` is a UUID kept in a file beside the database
    (`<app data dir>/inspektor-remote/store-id`), so it goes away with the app's data.
    - A table in the database was the first idea. It was dropped because Inspektor's schema sets
      its own `user_version`, which makes a new migration risky on iOS.
    - The cost: deleting only the database file keeps the old id.
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
- backfill followed by live events;
- body ranges;
- an override round trip;
- an unsupported protocol version.

They live in the Inspektor repo. The Kotlin and Dart servers are tested against them in CI, and
Eagly's client tests use a copy pinned to a protocol version.

## 5. What Eagly needs from Inspektor

**Must have, blocking phase 2 (milestone I-1).** Items 1–3 are done on Inspektor's
`feature/remote-inspection` branch; item 4 is still open.

1. **A remote server in `inspektor-core`, on Android and iOS, that stays off unless the app turns
   it on.** *(Done.)*
   - The switch became `InspektorRemote.start()`, an `@UnstableInspektorAPI` object with an empty
     twin in `inspektor-core-no-op`. It isn't a config flag, so one call covers every integration
     in the process. The Dart package should take the same shape.
   - On start, it logs one line naming its socket or port (§4.3).
   - Keeping it in core avoids another no-op twin, because the no-op artifacts already keep core
     out of production. *Alternative:* a separate `:inspektor-remote` module with no public
     symbols. Nothing would name it, so it wouldn't need a twin either.
2. **A live event stream out of `TransactionRecorder`.** The recorder already inserts, then
   updates; emit an event after each. Also persist `store.id` (§4.9). *(Done, one level lower:
   `InspektorDataSourceImpl` emits on every insert, update and delete, so writes from any
   integration, and from Inspektor's own UI, reach Eagly.)*
3. **Header sanitisation applied in core, before anything reaches the transport.** The
   modularization plan already puts sanitisation there. *(Done: the recorder sanitises before
   storing.)*
4. **The `adapter` recorded on every transaction.** *(Open. It needs a schema column, so it waits
   for a migration that is safe on iOS. Until then `hello.sdk.adapters` is `[]` and transactions
   carry no `adapter`.)*

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

**React Native**, which wraps the OkHttp and URLSession modules:

- **Android:** `OkHttpClientProvider.setOkHttpClientFactory`, which exists in RN's
  `OkHttpClientProvider.kt`. It has to be called before the networking module initialises.
- **iOS:** `RCTSetCustomNSURLSessionConfigurationProvider`, declared in `RCTHTTPRequestHandler.h`.
  It hands RN a session configuration whose `protocolClasses` include Inspektor's `URLProtocol`.
  That scopes the hook to RN's own session instead of a global `URLProtocol` registration.
  - **Built 2026-10-19, and tried first in a React Native app** through a short Swift file in
    that app.
  - **Inspektor ships it as a static XCFramework** with a podspec
    (`InspektorUrlSession.podspec`). The framework exports core too, so `InspektorRemote` is
    visible from Swift.
  - **Swift reaches the protocol through `InspektorUrlProtocolBridge`.** Kotlin/Native writes a
    Kotlin subclass of an Objective-C class into the header with none of its members, so the
    protocol's own `register` is invisible from Swift.
  - **`prepare` + `addTo` set up the scoped path** without the global `registerClass`.
  - **The Podfile keeps it out of production:** `:configurations` leaves Release-prod out, so
    there the app's `#if canImport(InspektorUrlSession)` is false.
  - **Cost: no TLS pinning on captured requests.** They go out through Inspektor's own session,
    so RN's session delegate never sees their TLS challenges, and delegate-based pinning (TrustKit,
    as react-native-ssl-public-key-pinning does it) isn't enforced. Forwarding challenges through
    `URLProtocolClient` would fix that.
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

### Phase 0: agree the protocol — mostly done

- ~~Move §4 into the Inspektor repo, and settle the iOS port range, the socket names and how the
  remote server is switched on.~~
  - The spec is Inspektor's `docs/REMOTE_PROTOCOL.md`, on `feature/remote-inspection`, with the
    Kotlin server that implements it.
  - Eagly's `InspektorSource` was run end to end against that server: hello, backfill, a live
    event, a failed request, and `body.get`.
- **Still open:** write the golden transcripts.
- **Exit:** the spec and fixtures are merged in Inspektor, and §4 here is a link.

### Phase 1: Eagly foundation, with no device work — done

What landed, all under `lib/features/network/` (§3 has the map):

- **The pane.** `NetworkController` is a `FeatureController` created lazily in
  `DeviceSessionController`. `NetworkFeatureView` has a list and a detail view, and the pane is
  reachable from `WorkspacePane.network`, the rail and the command palette. Polish comes later.
- **The model and its store.** A capped store keeps an updated transaction where it first
  appeared. Fetched bodies sit in a cache with a byte budget. Listeners hear about a burst of
  events (a backfill, a HAR file) at most once per `notifyInterval`.
- **HAR.** Opening a HAR file makes it a source of its own, so the pane is useful before any live
  capture exists. Export writes HAR 1.2 with every body the sources can still provide.
- **The Inspektor client:** the frame codec (§4.4, including the rules in §4.3), message parsing,
  and `InspektorSource`. It's tested against a fake in-process server and once over a real
  loopback socket.

Two traps the tests caught, both now documented in the code:
- Apply the frame decoder with `bind`, not `socket.transform`. A `Socket` is a
  `Stream<Uint8List>`, and `transform` throws on that runtime type.
- `loadBody` is called while widgets build, so it announces the fetch asynchronously.

**Still open:** the golden transcripts belong to phase 0. Until they exist, the client tests
script the server by hand (`test/support/inspektor_test_support.dart`).

### Phase 2: Inspektor over the wire (needs I-1) — Android done, iOS built but not yet run on hardware

**Android landed** (§3 has the map):

- **Discovery.** `InspektorWatcher` runs while the pane is open and the device is connected. Every
  2 s it makes one `adb shell grep -F @inspektor_ /proc/net/unix`.
- **Connecting.** For each new socket it opens an `adb forward` and connects an `InspektorSource`.
- **Filing.** Once `hello` names the store, the source is attached under
  `inspektor:<app>:<store>`, not per connection. A restarted app (new pid, new socket) therefore
  continues the same list, resuming after the last id Eagly saw, and its old bodies load through
  the new connection.
- **The resume point** is kept per store and survives Clear, so cleared requests don't come back on
  a reconnect.
- **Connection lifetime.** Connections outlive a closed pane; only polling stops. A socket that
  disappears has its forward removed, and disposing the session removes the rest.
- **Retries.** A failed connect is retried after 10 s, not on every poll.
- **Decision:** `ScrcpyClient` keeps its own forward helpers rather than moving to `AdbTool`. It
  stays a self-contained module, and mirroring isn't touched. The plan used to say "move".
- **Device test:** `test/device/network_inspektor_device_test.dart` (`EAGLY_TEST_ANDROID_SERIAL`).
  It follows the Inspektor sample live, restarts it, and checks the list continues with no repeats
  and that every forward it opened is gone afterwards.
  - It ignores forwards it didn't open: another Eagly watching the same device makes its own.
  - It passed on an API 36 emulator.

**iOS is built** (2026-10-19), behind `IosNetworkService` in `services/ios/`. It is Rust only
(`rust/src/api/ios_network.rs`), following docs/IOS_RUST_MIGRATION.md, with no CLI version:

- **`probe_ios_ports(udid, ports)`** makes a usbmuxd `Connect` per port, all in parallel, each on
  its own daemon connection. Each probe has a 3 s timeout. A refused port is closed, and a device
  usbmuxd no longer knows is an error.
- **`start_ios_port_forward(udid, device_port)`** is Eagly's `iproxy`. It listens on
  `127.0.0.1:0`, and pipes every accepted connection to the device port through a new usbmux
  connection. The device is looked up again each time, because its usbmux id changes on replug.
  **`stop_ios_port_forward(host_port)`** closes the forward and every connection through it.
- **Discovery:** the watcher's iOS poll probes 38470–38477. A port this session already tunnels to
  isn't probed, since a probe is a connection the app sees. Instead it is reported for as long as
  the tunnel lasts.
- **Restarts:** a restarted iOS app usually takes the same port, so the endpoint never leaves the
  list. The watcher therefore drops any connection that ends, and the next poll connects again.
  That also covers an Android app that stops and restarts its server in the same process.
- **Device test:** `test/device/network_inspektor_ios_device_test.dart`
  (`EAGLY_TEST_IOS_UDID`, `EAGLY_TEST_INSPEKTOR_BUNDLE`). It relaunches the app with `devicectl`,
  so it needs an app that makes requests at launch. It also prints what a poll's probes cost (§8).
- **First target:** a React Native app (see §5). It hasn't run end to end yet: the iPhone
  went offline before the device test could.

**Still to do:**

- **Android, superseded:**
  - ~~Move `AdbTool.forward` and `removeForward` out of `ScrcpyClient`.~~
  - ~~Discovery through `/proc/net/unix`.~~
- **Connection failures in the pane.** A protocol mismatch ("update Eagly") is only logged for
  now.
- **iOS on hardware:** run the device test, and the probe-cost and backgrounding checks (§8).
- **iOS `PidList`**, for process names.
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
- **No authentication, by decision (§1.1).** While an opted-in build runs, other apps on that
  device can read its traffic and set overrides. The bounds are in §4.3: no server in production,
  explicit opt-in, and on-device listeners only. Revisit if Inspektor is ever meant for builds
  that real users install.
- **iOS apps are suspended in the background**, so live capture stops. The paused state and
  backfill cover the gap, and the UI should say so rather than look broken.
- **Polling adb and usbmux costs the device link.** Mitigation: one shell per Android poll, polling
  only while the pane is open, and probing only the fixed port range.
- **Memory.** Mitigation: Eagly's ring buffer and body budget, and clearing the VM-service profile
  after each fetch.
- **Moving the forward helpers out of `ScrcpyClient` could regress mirroring.** Mitigation: the
  move is mechanical; check it with the existing mirror tests and one device session.

## 8. Spikes and checks

Dropping authentication (§1.1) removed two spikes: whether Dart can read the connecting peer's uid,
and whether iOS delivers a token line to Eagly's log tap. Both are kept with the superseded design
in
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
