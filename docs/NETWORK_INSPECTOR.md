# Network Inspector

> **Status: phases 1 and 2 have landed on Android and iOS (§6).** This file describes what is
> built. Phases 3 to 5, the risks, the open spikes and questions, and the research for routes
> not built yet are in [plan/NETWORK_INSPECTOR.md](../plan/NETWORK_INSPECTOR.md). It tracks
> [#72](https://github.com/ShreyashKore/eagly/issues/72). It was written on 2026-10-18 from research
> against primary sources: AOSP, Chromium, the Dart SDK, WebKit, React Native, pymobiledevice3 and
> the `idevice` crate. Claims that could not be confirmed are marked *unverified*.

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
  over a stream socket. §4 is the original draft; the spec itself lives in the Inspektor repo.
- **Development builds only, and only the developer's tools get in.** Production releases ship
  Inspektor's no-op artifacts. In debug, UAT and dev-release builds, the remote server runs only
  when the app turns it on, and only in a development build or one that opts in. Since protocol 2,
  Android checks the peer's uid and iOS asks for a token from the device log (§4.3). UAT builds
  are what keep the socket: the journal-file and device-log alternatives can't serve them (§1.1).
- **Not built yet:** editing overrides from Eagly, the two routes that need nothing installed
  (CDP for WebViews and Chrome, the Dart VM service) and the deferred routes. They are in
  [the plan](../plan/NETWORK_INSPECTOR.md). Dropped routes are written up in
  [NETWORK_INSPECTOR_DROPPED_ROUTES.md](../plan/NETWORK_INSPECTOR_DROPPED_ROUTES.md).

## 1. What changed once Inspektor went multi-client

The first pass of this plan treated Inspektor as one Ktor-only source among many. It leaned on a
proxy and on platform tooling for everything else. Inspektor is now planned to cover OkHttp,
URLSession, Ktor, React Native and Flutter (see its
[multi-client plan](https://github.com/ShreyashKore/inspektor/blob/refactor-into-smaller-modules/.agents/notes/multi-client-modularization-plan.md)),
and that changes the order:

| Route | First pass | Now | Why |
|---|---|---|---|
| Inspektor SDK → Eagly | Phase 3, Ktor apps only | **Primary**, phases 0–3 | Covers every framework. Traffic is already decrypted, the on-device database gives history, and overrides come with it. |
| React Native through Metro's CDP | Phase 1 | [Dropped](../plan/NETWORK_INSPECTOR_DROPPED_ROUTES.md#react-native-through-metro) | Inspektor's React Native package covers it, and RN 0.83 ships its own Network panel. |
| JVMTI port of Studio's Network Inspector | Optional | [Dropped](../plan/NETWORK_INSPECTOR_DROPPED_ROUTES.md#a-port-of-android-studios-network-inspector) | Inspektor's OkHttp adapter covers the same stacks. |
| VPN companion app | Optional | [Dropped](../plan/NETWORK_INSPECTOR_DROPPED_ROUTES.md#vpn-companion-app) unless the proxy is built | Its only job is to feed the proxy. |
| Eagly's data model | Shaped like CDP | **Shaped like Inspektor's transaction** (HAR-like) | The primary source should map with no loss, including an override's "original vs replaced" values. |

The routes this reordering kept as complements, deferred or optional (the Dart VM service, CDP
for WebViews and Chrome, the MITM proxy, iOS HAR logging, `webinspector`, `pcapd`) are not built.
Their rows are in [the plan](../plan/NETWORK_INSPECTOR.md#1-routes-kept-for-later).

Seen from Inspektor's side, Eagly *is* the "remote viewer" that its plan lists as the escape hatch.
It lets Flutter and React Native apps be inspected without shipping Compose Multiplatform UI into
them.

### 1.1 Scope decision: development builds only, no authentication (2026-10-18)

> **Reversed on 2026-10-25, in protocol 2.** A security review found the trade too loose. Before
> Android 9, any app can connect to another app's abstract socket, and on iOS any app can reach a
> loopback port. Such an app could read weeks of traffic, tokens included, and plant overrides
> that survive a restart. Inspektor now authenticates the client, much as the superseded design
> did (§4.3). It also refuses to serve a build that isn't a development build unless that build
> opts in. The decision below is kept for its reasoning about transports, which still holds.

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
  [the dropped-routes doc](../plan/NETWORK_INSPECTOR_DROPPED_ROUTES.md#transports-between-inspektor-and-eagly).
- **What this removes from the plan:** the authentication handshake, Eagly's iOS log-token tap,
  and two of the three spikes that had to run before phase 2.
- **What stays:** discovery, the tunnels, backfill, and the iOS paused state (not built yet).

## 2. Capture routes

This section lists the routes that were evaluated and what became of each. Only the Inspektor
SDK route is built. The routes kept for later (phase 4, optional, deferred) are in
[the plan](../plan/NETWORK_INSPECTOR.md#2-capture-routes-kept-for-later), with what they see and
need, so they don't have to be researched again.

| Route | What it sees | What it needs | Android | iOS | Status |
|---|---|---|---|---|---|
| Inspektor SDK | Whatever its adapter hooks: OkHttp, URLSession, Ktor, React Native (through those two), Dart `HttpClient` / `http` / dio | The dependency, with its remote server turned on, in a non-production build | ✅ | ✅ | **Primary**, built |
| JVMTI agent (Studio's inspector) | OkHttp, HttpURLConnection and gRPC in debuggable apps | API 26+ | ✅ | – | [Dropped](../plan/NETWORK_INSPECTOR_DROPPED_ROUTES.md#a-port-of-android-studios-network-inspector) |
| React Native through Metro | React Native `fetch` / XHR | RN 0.83 or later | ✅ | ✅ | [Dropped](../plan/NETWORK_INSPECTOR_DROPPED_ROUTES.md#react-native-through-metro) |
| VPN companion app | All TCP from all apps, routed into the proxy | The proxy; a consent dialog; root for Flutter's CA | ✅ | – | [Dropped](../plan/NETWORK_INSPECTOR_DROPPED_ROUTES.md#vpn-companion-app) |
| eBPF (eCapture) or Frida | Everything | Root | ✅ | – | Out of scope |
| `CFNETWORK_DIAGNOSTICS` | Headers only | A DVT launch | – | ✅ | Rejected: HAR logging does strictly more |

What each kind of app would be covered by once phases 1 to 4 land is in
[the plan](../plan/NETWORK_INSPECTOR.md#21-coverage-once-phases-14-land).


## 3. Architecture in Eagly

The feature keeps its own `data/` and `services/` folders, the way the Logs feature does. Paths
below are under `lib/features/network/` unless they start with `lib/`. ✓ marks what phases 1 and 2 built.

```
model              data/network_transaction.dart          ✓ NetworkTransaction, headers, bodies, timings
                   data/network_transaction_store.dart    ✓ capped store + body cache with a byte budget
                   data/har.dart                          ✓ HAR 1.2 encode / decode
                   data/network_filter.dart               ✓ the list's filter: query syntax, toggles, time window
                   data/network_timeline.dart             ✓ time ranges for the overview and waterfall
                   data/network_copy.dart                 ✓ Copy as cURL, headers as text
sources            services/network_source.dart           ✓ interface, one implementation per route
                     ├─ services/inspektor/                ✓ frame codec, messages, InspektorSource (§4)
                     └─ services/har_source.dart           ✓ a HAR file opened from disk
discovery          services/inspektor/inspektor_watcher.dart ✓ Android and iOS; polls only while the pane is open
                   services/inspektor/inspektor_endpoint.dart ✓ endpoints, tunnels, /proc/net/unix parsing
device facade      lib/services/device_session_repository.dart ✓ findInspektorEndpoints / openInspektorTunnel
tunnels            lib/services/tools/adb_tool.dart          ✓ forwardToAbstractSocket / removeForward / grepProcNetUnix
                   rust/src/api/ios_network.rs               ✓ iOS; port probe and forward over usbmux
iOS backend        lib/services/ios/ios_network_service.dart ✓ iOS; interface, Rust implementation only
feature controller network_controller.dart                ✓ FeatureController; lazy in DeviceSessionController
view               network_feature_view.dart, components/ ✓ WorkspacePane.network, rail, command palette;
                                                          the DevTools-style pane in §3.7
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
- **Provenance:** the source kind (`NetworkSourceKind`: `inspektor` or `har`, a HAR file opened
  from disk) and the adapter (`okhttp`, `urlsession`, `ktor`, `dart:io`, …).

Bodies are fetched on demand and cached under a byte budget. The transaction list lives in a ring
buffer, like `LogBuffer`. Eagly both exports and imports HAR 1.2. Inspektor already exports HAR,
so a file from a QA device opens in Eagly from day one.

Other sources (CDP, the Dart VM service) would map onto the same model; how is in
[the plan](../plan/NETWORK_INSPECTOR.md#31-model-other-sources-and-later-fields).

### 3.2 Targets and discovery

A *target* is one capturing endpoint in one process: the device, the process, and the kind of
source. Discovery produces a per-device list of targets, like `chrome://inspect`. There is no
picking step: `InspektorWatcher` opens a tunnel to every endpoint it finds and, once the app's
`hello` names its store, attaches the source under that store's key (`inspektor:<app>:<store>`).

| Target | How Eagly finds it |
|---|---|
| Android, Inspektor | `grep @inspektor_ /proc/net/unix`, run as a single `adb shell`. |
| iOS, Inspektor | Probe a fixed port range over usbmux from Rust; a refused connect returns at once. The handshake names the app. |

- `adb shell` can read `/proc/net/unix` on API 36; this was checked on a Play-image emulator.
  Google Messages' *production* build exposes `@stetho_…_devtools_remote` sockets there, so the
  discovery mechanism works on current Android.
- Each Android poll is a single `adb shell`. AGENTS.md records why: a burst of adb clients contends
  with `adb reverse` and drops Metro.
- Discovery polls about every 2 s, and only while the Network pane is open. Controllers are lazy,
  so this needs nothing extra.

**Features stay isolated.** Discovery lives in the Network feature's `services/`, not in Logs. When
it needs log lines, as for the iOS token (§4.3), it opens **its own log tap**. The Network pane
never depends on a Logs pane being open.

### 3.3 Tunnels

- **Android:** `adb forward tcp:0 localabstract:<name>`, through
  `AdbTool.forwardToAbstractSocket` and `removeForward`. `ScrcpyClient` keeps its own forward
  helpers (a phase 2 decision, §6). The forward is removed when its target goes away.
- **iOS:** a Rust equivalent of `iproxy`, `start_ios_port_forward` in
  `rust/src/api/ios_network.rs`. It listens on `127.0.0.1:0`, pipes each accepted
  connection to `UsbmuxdConnection::connect_to_device(port)`, and returns the host port.

With both tunnels in place, `InspektorSource` is the same Dart `Socket` code on both platforms.

### 3.4 Source interface

```dart
abstract interface class NetworkSource {
  NetworkSourceKind get kind;              // inspektor or har
  String get label;                        // the app, or the file
  Stream<NetworkSourceEvent> get events;   // upserts, clears, status changes
  Future<NetworkBody> body(String transactionId, NetworkBodyPart part);
  Future<void> dispose();
}
```

`events` is single-subscription and buffers until the pane listens, so nothing a source sends
first is lost. Its events are `NetworkTransactionUpserted` (always the whole transaction),
`NetworkTransactionsCleared` and `NetworkSourceStatusChanged` (`connecting`, `live`, `ended` or
`failed`). The definition is `services/network_source.dart`. Per-source capabilities and a
`clear()` method are [planned](../plan/NETWORK_INSPECTOR.md#34-source-interface-planned-additions).

### 3.5 Duplicates

Only Inspektor and HAR sources exist so far. The rules for when the same request is visible
through more than one route are in [the plan](../plan/NETWORK_INSPECTOR.md#35-duplicates).

### 3.6 Privacy

- Captured traffic is kept in memory only. Nothing is written unless the user exports it.
- Inspektor's `sanitizeHeader` can redact headers on the device, before anything reaches the wire.
  That is the app's choice; Eagly shows and exports whatever it receives.

Redacting `Authorization`, `Cookie` and `Set-Cookie` in HAR export and under `--record-mode`
is not built: an exported HAR and a recorded video contain these headers as captured
([plan](../plan/NETWORK_INSPECTOR.md#36-privacy-not-built-yet)).

### 3.7 The pane

The pane follows Chrome DevTools' Network panel, so it needs no learning. Top to bottom:

- **Filter bar** (`components/network_filter_bar.dart`). One query field that takes DevTools'
  syntax, parsed by `NetworkFilter` (`data/network_filter.dart`):
  - Bare text matches the URL. `-` negates a term, `/…/` is a regex, and quotes keep spaces.
  - Keys: `domain:` (with `*`), `path:`, `method:`, `status-code:` (`4xx`), `mime-type:`,
    `larger-than:`, `slower-than:`, `is:` (`pending`, `failed`, `error`, `overridden`),
    `scheme:`, `has-request-header:`, `has-response-header:` and `source:`.
  - The field suggests keys, then the values the capture holds for that key, with counts.
  - Below it sit status toggles (2xx … Failed, Pending) and type toggles (JSON, Doc, Text, Img,
    Media, Other). An empty set means all.
- **Timeline overview** (`components/network_overview.dart`). Every request the filter keeps,
  as a bar on one time axis, packed into lanes and colored by status:
  - hovering reads out the time, and the request under the pointer;
  - clicking a bar opens that request;
  - dragging sets the filter's `NetworkTimeWindow`.
  The header's timeline button hides it.
- **Request table** (`components/network_transaction_list.dart`):
  - Columns: Status, Method, Name (path over host), Type, Size, Time and Waterfall. Columns
    drop as the pane narrows. Every header sorts: ascending, then descending, then capture order.
  - Rows highlight on hover, and their cells explain themselves in tooltips. ↑/↓/PgUp/PgDn move
    the selection, and Esc closes it.
  - Right-click offers copy (URL, cURL, headers, response body) and "Show only / Hide …"
    entries. Those add a term to the query rather than setting hidden state, so they can be
    seen and edited there.
- **Detail** (`components/network_transaction_detail.dart`). It sits beside the list when the
  pane is at least 720 dp wide, with a draggable divider; on narrower panes it replaces the list.
  - Tabs: Headers, Payload, Response and Timing. The last tab picked sticks while you step
    through rows.
  - Header sections fold, and their rows have copy and "has header" menus.
- **Bodies** (`components/network_body_view.dart`) use `re_editor`, Reqable's read-only code
  view, highlighted with `re_highlight`:
  - fold markers for `{}`/`[]`, and line numbers;
  - a find bar (⌘F/Ctrl+F) with case and regex toggles;
  - pretty-printed or as-sent JSON and form bodies, and a wrap toggle;
  - image previews, and a hex dump for any other binary body.

Copy as cURL follows Inspektor's `Curl.kt` layout (long options, one per line) and quotes values
for the shell; `Curl.kt`'s `\'` escape inside single quotes does not work in a shell.

Two things to keep in mind when changing it:
- **The list keeps one place in the widget tree.** Opening an exchange beside it, or over it,
  must not remount it. Remounting reset the scroll position and orphaned an open row menu.
- **re_editor highlights and folds in a background isolate.** Widget tests see the text with
  neither applied, so assert on `CodeEditor.controller.text`, not on colors.

## 4. Eagly ↔ Inspektor protocol, original draft (now v2)

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
> - `store.id` is kept in a file beside the database (§4.9);
> - protocol 2 added authentication (§4.3), and Eagly speaks only 2.

### 4.1 Principles

- **Platform sockets only.** It must be implementable in Kotlin/JVM, Kotlin/Native and Dart with
  nothing but platform sockets. `inspektor-core` has no Ktor dependency and shouldn't gain one for
  this.
- **The server runs in the app and the client in Eagly.** That is the only direction that works
  over USB on both platforms: iOS has no device→host route without a jailbreak.
- **Only the developer's tools get in** (§4.3): by peer uid on Android, by a token from the
  device log on iOS.
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

### 4.3 Trust model (protocol 2)

Whoever is let in can read every transaction and create or delete overrides. So the server makes
sure the client is the developer's tool:

- **Android: the kernel names the peer.** An abstract socket has no file permissions, and before
  Android 9 any app could connect to another app's. The server reads `SO_PEERCRED` and accepts
  only uid 2000 (shell, which is how `adb forward` connections arrive), 0 (adbd as root) and its
  own uid. Its `hello` says `"auth": "none"`, and Eagly goes straight on.
- **iOS (and desktop): a token from the device log.** A loopback port names no peer, since every
  iOS app can reach it.
  - The server makes a random token each time it starts (32 hex digits).
  - It writes the token only to the device log, which other apps can't read and a paired Mac can:
    `Inspektor: remote inspection listening on 127.0.0.1:38470, token <token>`.
  - It writes that line when it starts and again for every connection it accepts.
  - Its `hello` says `"auth": "token"`. The client's first request must be
    `{"method": "auth", "params": {"token": …}}`. Anything else, or a wrong token, gets
    `unauthorized` and a closed connection.
- **How Eagly finds the token** (`InspektorTokenListener`):
  - iOS's syslog relay carries only live lines. So the watcher starts a syslog stream of its own
    before it opens the tunnel, waits for the first line to arrive, then connects.
  - The server's repeated line for that connection is the one it catches. It matches the line by
    port, and by the pid in `hello`.
  - The stream stops once the source is ready or has failed.

What else bounds it:

- **Production releases have no server.** They ship the no-op artifacts, which contain no
  transport code. `InspektorRemote.start()` also refuses a build that isn't a development build
  (not debuggable on Android, not development-signed on iOS) unless that build's manifest or
  Info.plist opts in.
- **It is reachable only on the device.**
  - The iOS listener binds `127.0.0.1`, and the Android listener is an abstract Unix socket, so
    the network can't reach either. That is unlike Metro, which listens on every interface.
  - It isn't HTTP, so a web page in a browser can't talk to it usefully. That is the attack
    Metro's `Origin` check exists for.

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
2. **Any HTTP or WebSocket endpoint added later needs the same token,** like the Dart VM
   service's.

### 4.4 Framing

Each frame is a 4-byte big-endian unsigned length followed by that many bytes of UTF-8 JSON, one
object per frame. A frame is at most 16 MiB; larger bodies are read in ranges with `body.get`.

When either side receives a frame longer than 16 MiB, or one that isn't a JSON object, it closes
the connection without replying. For the server this is a security rule (§4.3). For Eagly it means
a broken peer fails fast instead of being buffered.

### 4.5 Handshake

The server speaks first:

```json
{"type": "hello", "protocol": 2, "auth": "token",
 "sdk":   {"name": "inspektor", "version": "0.9.0", "runtime": "kotlin",
           "adapters": ["okhttp", "ktor"], "overrides": true},
 "app":   {"id": "com.example.app", "name": "Example", "version": "1.4.0 (51)",
           "pid": 12345, "process": "com.example.app"},
 "store": {"id": "7c0e2f4a-…", "persistent": true, "oldestId": "1201"}}
```

With `"auth": "none"`, the client can send requests as soon as `hello` arrives. With
`"auth": "token"`, its first request must be `auth` (§4.3).

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
Eagly has no override editor yet. The one planned for phase 3 works against that schema and is
hidden when `hello.sdk.overrides` is false ([plan](../plan/NETWORK_INSPECTOR.md#6-phased-plan)).

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
- **iOS apps stop accepting connections when suspended in the background.** Today Eagly shows the
  source as ended, then reconnects and backfills from the last id once the app comes back (§8).
  A *paused* state that lasts until the pid disappears is
  [not built yet](../plan/NETWORK_INSPECTOR.md#phases-0-to-2-what-is-still-open).

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

What later phases need from Inspektor (I-2 to I-4, and the Dart implementation) is in
[the plan](../plan/NETWORK_INSPECTOR.md#5-what-eagly-needs-from-inspektor-later).

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

## 6. Phases that have landed

Where a phase depends on an Inspektor milestone (I-n from §5), it says so. What these phases
still leave open, and phases 3 to 5, are in [the plan](../plan/NETWORK_INSPECTOR.md#6-phased-plan).

### Phase 0: agree the protocol — mostly done

- ~~Move §4 into the Inspektor repo, and settle the iOS port range, the socket names and how the
  remote server is switched on.~~
  - The spec is Inspektor's `docs/REMOTE_PROTOCOL.md`, on `feature/remote-inspection`, with the
    Kotlin server that implements it.
  - Eagly's `InspektorSource` was run end to end against that server: hello, backfill, a live
    event, a failed request, and `body.get`.

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

### Phase 2: Inspektor over the wire (needs I-1) — Android and iOS done

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

**iOS landed** (2026-10-20), behind `IosNetworkService` in `services/ios/`. It is Rust only
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
- **On hardware:** the device test passed on an iPhone 16 (iOS 27.0) against a React Native app
  (§5). It found the app, loaded a body, and continued the list across a relaunch with no
  repeats. Every forward it opened was closed afterwards.
- **The first run found a crash in Inspektor.** The iOS log line was `NSLog("%@", message)`.
  Kotlin/Native passes a `String` vararg as a C string, so the app trapped as soon as the server
  listened. The line is now its own escaped format. Since protocol 2, Eagly reads this line for
  the connection token (§4.3, `InspektorTokenListener`).

## 7. Risks

In [the plan](../plan/NETWORK_INSPECTOR.md#7-risks).

## 8. Spikes and checks

The spikes and their procedures are in [the plan](../plan/NETWORK_INSPECTOR.md#8-spikes-and-checks).
Results that shaped what is built:

- **A usbmux probe of a closed port fails fast.** On macOS over USB (2026-10-20), iPhone 16 on
  iOS 27.0, all 8 ports probed in parallel, one open, take a median of 1 to 2 ms and at most
  7 ms per poll, from Dart through the bridge. That is why iOS discovery probes the whole range
  every 2 s while the pane is open.
- **A backgrounded iOS app's listener is not reachable.** With the phone locked, a probe of the
  app's port is refused at once. Eagly shows the source as ended, then live again once the app
  comes back.

## 9. Open questions

In [the plan](../plan/NETWORK_INSPECTOR.md#9-open-questions).
