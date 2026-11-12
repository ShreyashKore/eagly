# Companion mobile app: scope

> **Status: exploration, 2026-10-30, with shape E added on 2026-11-05. Nothing is built and nothing
> is decided.** Facts about this repo come from reading the code on `docs/mcp-server-plan`. §7
> (shape E) was checked against the Dart SDK source, the Inspektor repo and the sources it lists;
> nothing in it was tried on a device. The rest of this document comes from earlier knowledge and
> was **not** checked against primary sources; each claim a decision depends on is marked
> *unverified*.

**Question.** What could an Eagly app on a phone do, how much of the desktop code could it reuse,
and how would it complement desktop Eagly instead of competing with it?

## TL;DR

There are five shapes. They are not alternatives: they combine, and they share most of their code.

| Shape | What the phone does | Android | iOS | Reuse | Risk |
|---|---|---|---|---|---|
| **A. Remote for desktop Eagly** | Talks to a running desktop Eagly over the LAN and shows what it sees | yes | yes | high | low |
| **B. Android on its own** | B1 inspects the phone itself; B2 drives *another* Android device over USB OTG or Wi-Fi | yes | — | medium | medium |
| **C. iPhone on its own** | Inspects the iPhone itself through the `idevice` crate over a loopback VPN, using a pairing record from desktop Eagly | — | spike | medium (Rust) | high (App Store) |
| **D. Offline viewer** | Opens exported logs, HAR files and crash reports from the share sheet | yes | yes | very high | none |
| **E. VPN capture** | A local VPN decrypts HTTP(S) on the phone and serves it to Eagly as if it were an Inspektor app | limited decryption | broad decryption, gated by App Store rules | Network pane unchanged; new Rust core | medium to high |

- **Recommendation: build A + D first.** It is one app on both platforms, it is mostly UI over
  code that already exists, and it is the part that *complements* the desktop app rather than
  duplicating it: the desktop keeps the cable, the bundled tools and the heavy panes; the phone
  becomes a remote, a notifier and a bug-report button that you can carry next to the device under
  test.
- **Then B1 on Android** (the phone reads its own logs, runs the Utilities catalog, sees
  Inspektor traffic) through a one-time `pm grant` from desktop Eagly, or through Shizuku.
- **B2 and C are spikes**, not commitments: B2 needs an in-app adb client, C rides an App Store
  grey area.
- **E is worth a spike, and it reverses part of an earlier decision** (§7). It was dropped because
  a VPN only fed a desktop proxy nobody built. If the phone decrypts the traffic itself and speaks
  Inspektor's protocol, that reason goes away. Its value is uneven: on a stock Android phone it
  decrypts little without the app's cooperation, while iOS trusts a user-installed CA everywhere
  except in pinned apps.
- **Step 0 for any of them is extracting a pure-Dart core package.** The models, parsers, filters,
  HAR and Inspektor codecs are already almost free of `dart:io` (§2); the device access is not.

## 1. What a companion is for

The desktop app assumes the developer sits at the computer with the phone on a cable. The
situations where that breaks are the ones a phone app is good at:

1. **Testing away from the desk.** A tester walks around with the phone under test (field test,
   network change, a second person reproducing the bug). Desktop Eagly keeps capturing over Wi-Fi
   ADB or the iPhone Wi-Fi tunnel; the companion shows the logs and the requests as they happen and
   has a **"Something went wrong"** button that tells the desktop to snapshot the last few minutes.
2. **Being told instead of watching.** A crash, an ANR, a `FATAL EXCEPTION`, a 5xx from the API,
   or a saved log filter that matches: a notification on the phone while the desktop is in another
   room or the screen is locked.
3. **A device lab.** One desktop with many phones attached; the companion lists them, their state,
   their logs, and can screenshot or restart one.
4. **No laptop at all** (Android only): reading the phone's own logs, running a `dumpsys`, seeing
   the traffic of an app that ships Inspektor.
5. **Reading a file someone sent.** A log export, a HAR or an `.ips` crash report arrives in chat or
   mail; open it on the phone with the same filter bar as the desktop.

What the companion should **not** do: be a worse desktop. The workspace (fl_panel), the terminal,
the file manager and the emulator manager stay desktop-only. Inspektor already shows an app's own
traffic on the phone, so the companion must offer something Inspektor's in-app UI cannot (every
app at once, desktop history, export, alerts), not a copy of it.

## 2. What can be reused

Measured by which files import `dart:io`, `Process`, `window_manager`, `desktop_drop` or
`fl_panel` (372 Dart files in `lib/`, 54 import `dart:io`, 20 start processes):

| Layer | Where | Portable? | Notes |
|---|---|---|---|
| Device model | `lib/data/` | **yes** (0 of 3 files coupled) | `Device`, `DeviceConnectionState`, `presentId` |
| Log model, filters, query syntax | `features/logs/data/` | **yes** (1 of 7) | `LogEntry`, `LogLevel`, `LogFilters.parse`, `FilterCondition` |
| Log parsers | `features/logs/services/log_parsers/` | **yes** | `logcat_parser` is clean; `ios_syslog_parser` imports `dart:io` and needs a look. The `-v long` and record rules of docs/LOG_STREAMING.md carry over unchanged |
| Network model, HAR, Inspektor codec | `features/network/data/`, `services/inspektor/` | **mostly** | `inspektor_frame_codec`, `inspektor_messages` are pure; `inspektor_endpoint` / `inspektor_source` assume `adb forward` / usbmux and need a transport seam |
| Crash reports | `features/crash_reports/data/` | mostly | parsing is portable; fetching is not |
| Layout inspector parsing | `features/layout_inspector/` | mostly (1 of 10) | `uiautomator dump` XML → tree is pure (`xml` package) |
| Utilities catalog | `features/utilities/data/utility_catalog.dart` | **as data** | the Android builders produce `adb shell` scripts for the *device's* `sh` — exactly what a shell-uid process on the phone runs (§4) |
| Shared widgets | `presentation/components/` | **yes** (1 of 33) | `CodeView` (`re_editor` works on mobile), `HintNote`, snack bars, `EaglyTheme` tokens and the text-emphasis tiers. Desktop affordances (hover, right-click, `AnchoredPopover`) need touch alternatives |
| Controllers | `session/`, `*_controller.dart` | **no, not as is** | `LogController` & co. are bound to `DeviceSessionRepository`. The seam already exists: `startLogStream()` yields `LogEntry`s, so a "remote log source" can feed the same controller |
| Tool wrappers | `services/tools/*` | **no** | `Process` + bundled CLIs under `platform-tools/<os>/` |
| scrcpy | `features/flutter_scrcpy/` | **partly** | the control protocol and `ScrcpyKeyboardTranslator` are pure Dart; `ScrcpyClient` pushes and forwards through `Process.run(adb, …)` and decodes through the native `flutter_scrcpy/video` channel (VideoToolbox / FFmpeg) — a phone would decode with MediaCodec / VideoToolbox behind the same channel name |
| MCP read layer | `features/mcp/tools/` | **yes, as the API** | `McpToolContext` already resolves devices, budgets output and redacts headers. plan/PLUGIN_SYSTEM.md plans to extract it into a façade for plugins and agents; the companion would be its third consumer |
| Rust | `rust/` (`idevice` 0.1.68, `tcp`, `remote_pairing`, `rsd`, `syslog_relay`, `crashreportcopymobile`, `installation_proxy`, `afc`) | probably | cross-compiling for `aarch64-linux-android` and `aarch64-apple-ios` with the `ring` backend is *unverified*; needed only for shape C |

**Packaging.** A Flutter pub workspace: `packages/eagly_core` (pure Dart: models, parsers,
filters, HAR, Inspektor codec, utility catalog), `packages/eagly_ui` (theme, `CodeView`, log row),
the desktop app as it is, and `apps/companion`. The mirror refactor on
`refactor/device-mirror-package` (`packages/device_mirror`) is precedent for the move. A second
`main_companion.dart` inside the desktop package would be faster to start but drags the desktop
plugins and the `Process` code into the mobile build, and the two would keep tangling.

## 3. Shape A: a remote for desktop Eagly

### Transport

- **A companion API on the desktop**, built on the same read layer as the MCP server. MCP itself is
  request/response with long-polls (`wait_for_log`); the companion needs a push stream, so the API
  adds a WebSocket (or SSE) over the hooks the MCP work already added: `LogController.appendedLogs`
  and the Network watcher.
- **Off by default, LAN-only, paired by QR.** The MCP server binds `127.0.0.1` on purpose
  (docs/MCP_SERVER.md §3.3); a LAN listener is a new attack surface and needs its own switch.
  Pairing: desktop shows a QR code (`qr_flutter` is already a dependency, used for Wireless ADB)
  carrying host, port, the fingerprint of a self-signed certificate and a one-time token. The phone
  pins the certificate; each paired phone gets its own revocable token, stored the way
  `McpTokenStore` stores the MCP one.
- **Discovery** after pairing: an mDNS service (`_eagly._tcp`); the Rust side already links
  `mdns-sd`.
- **Read and write are separate grants**, mirroring the MCP server's read-only / write split.
- **Off-LAN access** (relay, tunnel, cloud) is deferred: it needs a server, accounts and a threat
  model this project doesn't have.

### Features, in priority order

1. Device list and status (connected, wireless, unauthorized), with the desktop's labels.
2. **Live logs** per device, with the same filter syntax (`tag:Auth level:e -message~:^x`) —
   `LogFilters.parse` is reused, the pills become a phone-sized sheet. Filtering could run on the
   desktop (send the query, stream matches) to save battery and bandwidth.
3. **Network**: request list and detail (headers, bodies, timing) from Inspektor-enabled apps,
   header redaction on by default, *Copy as cURL* / HAR export to the share sheet.
4. Crash reports (iOS today; Android tombstones / dropbox would be new on the desktop too).
5. **Screenshot**, start/stop screen recording; the result saved on the desktop and a copy sent
   to the phone.
6. **Bug-report bundle**: one tap asks the desktop for the last *N* minutes of logs, a HAR, a
   screenshot and device info, zipped (`archive` is a dependency) and shared from the phone.
7. **Notifications** for rules: crash, ANR, a log filter, an HTTP status. See the limit below.
8. Write actions (behind the write grant): run a Utilities command, open / force-stop / clear an
   app, install an APK or IPA picked on the phone (uploaded to the desktop, installed through the
   existing `installAppFromPath`, conflicts reported through `AppInstallResult.conflict`).
9. **Mirror relay** (Android first): the desktop already receives scrcpy's H.264 access units, so
   it can forward them to the phone and the phone's platform decoder draws them; touches go back
   as scrcpy control messages. The iPhone mirror on macOS arrives as decoded `CVPixelBuffer`s and
   would need re-encoding, so it comes later.

### The notification limit

Without a push server, notifications only work while the companion holds its socket. On Android a
foreground service can keep it (with a persistent notification). On iOS the socket dies soon after
the app leaves the foreground; background push needs APNs, which needs a server that holds a
device token. So on iOS, "alerts" means *while the app is open* unless a relay is built. This is
the biggest limit of shape A and worth deciding early.

## 4. Shape B: Android on its own

### B1. The phone inspects itself

| Capability | How | Reuse |
|---|---|---|
| All apps' logs | `READ_LOGS`, granted once with `adb shell pm grant <companion> android.permission.READ_LOGS` — desktop Eagly can do that in one tap while the phone is on the cable — or through Shizuku. Android 13+ asks the user to allow log access per session *unverified* | `logcat -v long` + `LogcatParser` unchanged; `LogBuffer`, filters, log row |
| Shell commands (Utilities: `pm`, `am`, `dumpsys`, `settings`, `wm`) | A process with the shell uid: Shizuku, or wireless debugging to `localhost` (the LADB pattern), which needs ADB's TLS pairing implemented in the app | the Utilities catalog's Android builders, as is |
| Inspektor traffic of every app on the phone | Inspektor's Android server accepts only uid 2000, 0 and the app's own uid (docs/NETWORK_INSPECTOR.md §4.3). A Shizuku-hosted helper runs as uid 2000 and passes; without one, Inspektor would need a companion trust mode (an allowlisted signing certificate), which is a change in the other project and weakens its guarantee | frame codec, messages, network UI |
| Layout tree | `uiautomator dump` under the shell uid; or an AccessibilityService, which gives a live tree but meets Play's accessibility-API policy *unverified* | `uiautomator` XML parser, tree view |
| Crashes / ANRs | `dumpsys dropbox` under the shell uid | crash viewer |
| Screen | not needed — it *is* the phone | — |

Without a shell-uid helper B1 shrinks to the companion's own logs, which is not worth an app; so
B1 is really "Eagly for Shizuku users, plus a desktop-assisted one-time grant for everyone else".

### B2. The phone drives another Android device

The phone becomes the host: USB OTG through Android's USB host API, or adb over Wi-Fi. That needs
an **adb client inside the app** (the `CNXN`/`OPEN`/`WRTE`/`OKAY`/`CLSE` protocol, RSA auth, and for
Android 11+ wireless debugging the TLS + SPAKE2 pairing) instead of the bundled `adb` binary. With
it, scrcpy works phone-to-phone: push the bundled `scrcpy-server`, open its sockets, reuse the Dart
control protocol and keyboard translator, decode with MediaCodec. Prior art exists on Play
(Bugjaeger for adb over OTG, Easycontrol for scrcpy-style control) *unverified*. It is the largest
piece of new work in this document, and it overlaps desktop Eagly's job; keep it a spike unless
"no laptop" turns out to matter.

## 5. Shape C: the iPhone on its own

An iOS app cannot read the system log or any other app's data. The known way round is the one
SideStore and StikDebug use *unverified*: the app holds a **pairing record** made by a computer and
talks to lockdownd on its own phone through a loopback VPN (NetworkExtension), using the same
`idevice` crate Eagly links. That would give the companion, on the iPhone itself:

- `syslog_relay` → the phone's log, through the same record parser as desktop iOS logs;
- `crashreportcopymobile` → crash reports;
- `installation_proxy`, `springboardservices` → the app list and icons (`rust/src/api/ios.rs`);
- the Inspektor token from the device log, so it could connect to an Inspektor app's loopback port
  like the desktop does (docs/NETWORK_INSPECTOR.md §4.3).

Desktop Eagly's part is handing over the pairing record (it already pairs, over USB and over the
Wi-Fi tunnel). That record is full trust of the phone, so the hand-over needs the same QR + pinned
TLS channel as shape A, and an explicit warning.

Risks: App Store review of a VPN-entitled app that talks to lockdownd is uncertain *unverified*,
which may mean TestFlight or AltStore-style distribution; services behind the developer disk
image (screen, HID, app control) need Developer Mode and may not be reachable on-device at all;
pairing records are invalidated when the user resets trust. Worth a one-week spike: build the Rust
crate for iOS, open the tunnel, read syslog. If it fails, iOS gets A + D only, which is still
useful.

## 6. Shape D: offline viewer

Opening files needs no device and no desktop: a log export (the desktop's imported-logs workspace
format, `log_file_service.dart`), a HAR (`har_source.dart`), an iOS `.ips` crash report (from
Settings → Privacy → Analytics Data, shared to the app). The parsers, filters and `CodeView` are
the desktop's. It costs little beyond the core extraction and makes the app useful on day one,
before pairing with anything.

## 7. Shape E: VPN capture

**The idea.** The companion runs a local VPN. Every connection from the chosen apps enters it, a
man-in-the-middle engine on the phone decrypts what it can, and the finished request and response
records go to desktop Eagly.

### What changes from the dropped route

[NETWORK_INSPECTOR_DROPPED_ROUTES.md](NETWORK_INSPECTOR_DROPPED_ROUTES.md#vpn-companion-app) dropped
a VPN app on 2026-10-18. That design was a dumb pipe into a desktop proxy, and it was judged for
Android alone. Going through its reasons:

| Reason it was dropped | Now |
|---|---|
| It only feeds the desktop proxy, which is deferred | **Gone** if the phone is the proxy |
| It doesn't fix Flutter's CA trust on unrooted Android | **Still true**, and confirmed in the Dart source below. It does not apply to iOS |
| Consent dialog; one VPN at a time | **Still true.** The dialog is first-use only, but `VpnService` says "There can be only one VPN connection running at the same time". This one matters: UAT servers often sit behind a corporate VPN, and those testers can't use shape E |
| Another APK to build and ship | **Weaker** once a companion app exists, and Eagly can `adb install` it the way it bundles `scrcpy-server` |
| Cheaper options cover the same cases | **Partly.** Neither emulator `-http-proxy` nor the Wi-Fi proxy setting works on cellular, or for a Flutter app on a real iPhone |

### Decrypting on the phone, not the desktop

| | Dumb pipe to a desktop proxy | **MITM on the phone (recommended)** |
|---|---|---|
| Where the traffic exits | The desktop's network, so a cellular test isn't one | The phone's real network |
| If the desktop goes away | The phone loses connectivity, or capture stops | Capture goes on; Eagly backfills on reconnect |
| Desktop work | Build the proxy (phase 5) and a SOCKS front end | None for Android (next section) |
| iPhone link | Needs a tunnel from the extension to the desktop | Records only, over the existing usbmux forward |
| Phone work | Small | Large, but one Rust core serves both platforms |

### It can pose as an Inspektor server

Eagly's Network pane needs no new source for this. On Android:

- `parseInspektorSockets` accepts `@inspektor_<digits>_<lowercase>`, so a socket per captured app,
  such as `@inspektor_10234_vpn`, is discovered and forwarded by the existing watcher. Each app then
  appears as its own source, because `hello.app.id` is per connection and transactions are filed by
  `inspektorStoreKey`.
- `ConnectivityManager.getConnectionOwnerUid` (API 29+) names the app behind a connection, and only
  the active `VpnService` may call it.
- The protocol's required transaction fields are just `id`, `method` and `url`. `adapter`,
  `timings`, `tlsVersion` and body states already exist and fit a proxy. Clients ignore unknown
  fields, so an additive `opaque: true` could mark a connection that wasn't decrypted.
- Overrides come almost free: `FixedResponse` is what a MITM does best, so **mocking would work for
  apps that don't ship Inspektor**. `hello` advertises it with `sdk.overrides`.

On iOS the same holds with less: one port for the whole device, since a packet tunnel can't name
the app, and the token written to the device log as Inspektor does. Whether a Network Extension
can serve a loopback port that usbmux reaches is *unverified*.

Two limits: Eagly's watcher polls for endpoints with the phone attached, so a remote link needs
shape A's transport; and the server must keep the peer checks, because it holds *other* apps'
traffic, which is more than Inspektor ever exposes.

### What it can decrypt

Routing is the easy half. A VPN catches everything, including `dart:io`, which ignores the system
proxy. Decryption depends on whether the app trusts our CA. On a stock phone with the CA installed
as a user CA:

| Traffic | Android | iOS |
|---|---|---|
| Your app, with `<certificates src="user"/>` in its network security config | decrypted, third-party SDKs and WebViews included | decrypted |
| Your app, with no such config | metadata only | decrypted |
| Other apps, not pinned | metadata only | decrypted |
| `WKWebView` | — | decrypted, which covers the deferred "iOS WebView inspection" |
| Flutter (`dart:io`) | metadata only | **expected to decrypt, not yet tried on hardware** |
| Pinned apps | metadata only | metadata only |
| HTTP/3 | block UDP 443 so clients fall back to TCP | same |
| Rooted phone or `adb root` emulator | system CA: everything not pinned | — |

- **Android.** Since API 24 apps ignore user CAs unless their config opts in, and since Android 11
  an app can't even prompt for a CA install: the user must go through Settings.
- **Flutter on Android.** `security_context_linux.cc` loads only
  `/apex/com.android.conscrypt/cacerts`, else `/system/etc/security/cacerts`, and user CAs live in
  neither. Note that NETWORK_INSPECTOR_DROPPED_ROUTES.md names only the second path.
- **Flutter on iOS.** Dart defines `DART_HOST_OS_MACOS` on iOS too, so `security_context_macos.cc`
  applies there: it evaluates through `SecTrust` and leaves the system anchors on by default.
  Whether that takes in a root enabled in Certificate Trust Settings is the assumption to test.
  If so, the VPN solves routing and SecTrust solves trust, with no code change to the app.
- **Metadata** means host (from SNI or DNS), port, timing and byte counts, with the app's name on
  Android. It needs no CA and works on pinned apps too, so it is a useful tier by itself: *what
  does this app talk to?*
- **On iOS with a cable, metadata needs no VPN at all.** `pcapd` gives each packet's `pid` and
  `comm`, and `idevice` has it behind a feature Eagly doesn't enable yet; it is phase 4c of
  plan/NETWORK_INSPECTOR.md.

### Where it beats Inspektor, and where it doesn't

Inspektor stays the first answer for your own apps: no CA, no VPN, works with pinning, and in UAT
builds behind a corporate VPN. Shape E earns its place in the gaps:

1. **Third-party SDK traffic in your own app.** Inspektor sees only the clients it was added to;
   `InspektorUrlProtocol` captures a session only once it is listed in that session's
   `protocolClasses`. Analytics and ad SDKs make their own.
2. **Apps with no SDK**, and testers who can't change the build (iOS).
3. **Flutter on iOS without Inspektor**, and iOS WebViews.
4. **Cellular testing.** No Wi-Fi proxy can follow the phone onto mobile data.

If an Android team can edit the app to add the `user` CA line, it can usually add Inspektor, which
is why the Android case is the weaker one.

### How it would be built

- **Rust core shared by both platforms:** a userspace TCP/IP stack, then a MITM engine, then the
  Inspektor server. `tun2proxy` (MIT) or `ipstack` (Apache-2.0) for the first and `hudsucker`
  (MIT/Apache-2.0, already the choice in Appendix B of plan/NETWORK_INSPECTOR.md) for the second.
  All are permissive, unlike HTTP Toolkit's AGPL app and PCAPdroid's GPL. ProxyPin (Apache-2.0) is
  the reference to read. Attribution needs a hook *before* the proxy hop, because `tun2proxy` hides
  the original connection.
- **Thin native shells:** Kotlin `VpnService`, Swift `NEPacketTunnelProvider`. Flutter stays in the
  main app; the iOS extension's memory limit rules it out there. That limit is undocumented, and
  reported at 50 MiB as recently as iOS 26, so bodies must stream to disk. Apple says not to rely on
  the figure.
- **Pinned hosts must keep working.** When a client rejects our certificate, mark that host
  passthrough, so one failed connection is the only cost.
- **It must not capture itself:** `addDisallowedApplication` on Android. iOS should exclude a
  provider's own sockets from its tunnel *unverified*.
- **One tunnel on iOS.** Shape C needs a loopback VPN too. Only one can run, so C and E would have
  to share an extension.

### Safety

This is the most sensitive thing Eagly would ever do. The defaults have to say so:

- **Metadata by default; decrypt only hosts the user lists.** Banking and mail stay untouched.
  Android can also route only chosen apps (`addAllowedApplication`). iOS can't: per-app VPN needs
  MDM, so the host list is the only scoping there.
- **A CA per install, generated on the phone,** whose key never leaves it. Proxyman also generates
  its own root per device rather than sharing one.
- **Remind the user to remove the CA.** Stopping capture can't do it, and a trusted CA left on a
  daily phone outlasts the session.
- **Peer checks on the server** (`SO_PEERCRED`, token), and Inspektor's header redaction on by
  default.

### Distribution

- **Keep it a separate build flavor,** so a store rejection can't take shapes A and D with it.
- **Android:** Play limits `VpnService` to listed categories, none of which names a developer tool.
  "Network-related tools" is nearest, and the page describes tunnels to a remote server, so a local
  tunnel's fit is unclear. It also requires a declaration form and a demo video. `adb install` from
  Eagly avoids all of it.
- **iOS:** guideline 5.4 says VPN apps must come from developers enrolled as an organization. Whether
  an on-device tunnel counts is unsettled: an August 2026 forum thread asks exactly this and has no
  answer from Apple. Proxyman ships this design on the App Store. Plan on needing an organization
  account.
- **Android 17:** an app targeting API 37 needs `ACCESS_LOCAL_NETWORK` for LAN access. The USB path
  doesn't touch the LAN; how captured apps' own LAN traffic behaves through a VPN is *unverified*.

### First steps

1. **No code, an hour:** run Proxyman for iOS against a Flutter app on a real iPhone. If it decrypts
   with no code change, the strongest case for shape E is real. If not, E is much weaker.
2. **Android spike, about a week:** `VpnService` + Rust core + one `@inspektor_<uid>_vpn` socket, an
   app that opts in to user CAs, traffic in an unmodified Eagly. This proves the plumbing, the
   attribution and the performance. iOS follows only if step 1 passed and distribution is settled.

Sources: [`VpnService`](https://developer.android.com/reference/android/net/VpnService),
[Play: VpnService policy](https://support.google.com/googleplay/android-developer/answer/12564964),
[Android local network permission](https://developer.android.com/privacy-and-security/local-network-permission),
[Android 11 CA install](https://httptoolkit.com/blog/android-11-trust-ca-certificates/),
[`getConnectionOwnerUid` change](https://gerrit.omnirom.org/plugins/gitiles/android_packages_modules_Connectivity/+/0bd4bba07ae1751558dbcdf449862eafe3df1a67%5E%21),
[Dart `security_context_linux.cc`](https://github.com/dart-lang/sdk/blob/main/runtime/bin/security_context_linux.cc),
[`security_context_macos.cc`](https://github.com/dart-lang/sdk/blob/main/runtime/bin/security_context_macos.cc),
[Dart `globals.h`](https://github.com/dart-lang/sdk/blob/main/runtime/platform/globals.h),
[Network extension memory limit](https://developer.apple.com/forums/thread/73148),
[Packet tunnel metadata](https://developer.apple.com/forums/thread/113826),
[Guideline 5.4 thread](https://developer.apple.com/forums/thread/844103),
[Proxyman for iOS](https://proxyman.com/docs/proxyman-ios/vpn-and-proxyman-certificate).

## 8. Feature matrix

| Feature | A (phone ↔ desktop) | B1 Android self | B2 Android → other | C iPhone self | D offline | E VPN capture |
|---|---|---|---|---|---|---|
| Device list / status | yes | itself | yes | itself | — | — |
| Live logs + filters | yes | yes (grant / Shizuku) | yes | yes (spike) | files | — |
| Network (Inspektor) | yes | Shizuku or Inspektor change | yes (adb forward) | yes (token from log) | HAR | apps without Inspektor (§7) |
| Crash reports | yes | yes (shell uid) | yes | yes | `.ips` | — |
| Screenshot / record | yes | own screen (MediaProjection) | yes | no | — | — |
| Mirror + control | relay, Android first | — | yes (scrcpy) | — | — | — |
| Utilities catalog | yes (write grant) | yes (shell uid) | yes | partly | — | — |
| Install app | yes (upload) | yes (shell `pm install`) | yes | no | — | — |
| Layout inspector | yes (Android) | yes | yes | no | — | — |
| Bug-report bundle | yes | yes | yes | yes | — | adds traffic from apps without Inspektor |
| Background alerts | Android yes, iOS needs a relay | yes | yes | no | — | — |
| Files, terminal, emulators | no (desktop) | — | — | — | — | — |

## 9. Suggested order

| Phase | Work | Size |
|---|---|---|
| 0 | Extract `eagly_core` (models, parsers, filters, HAR, Inspektor codec, utility catalog) into a workspace package; the desktop keeps passing its tests. Give `LogController` and `NetworkController` a source interface instead of the repository | M |
| 1 | Companion app shell (phone layout, theme) + **D** offline viewer | M |
| 2 | Desktop companion API (LAN switch, QR pairing, pinned TLS, read stream) + **A** read features 1–5 | L |
| 3 | **A** write grant: Utilities, app actions, install, bug bundle; Android foreground-service alerts | M |
| 4 | **B1** on Android: one-tap `READ_LOGS` grant from desktop, Shizuku support, local logcat | M |
| 5 | Mirror relay (Android) | M |
| spike | **C** iPhone self-tunnel; **B2** in-app adb client | S each to learn, L to ship |
| spike | **E** VPN capture: the iPhone check, then the Android plumbing (§7, First steps). Independent of phases 0–5, since it needs only Eagly's existing Network pane | S to learn, L to ship |

## 10. Decisions that are yours

1. **Monorepo or separate repo** for the companion (§2 assumes a pub workspace in this repo).
2. **Is a LAN listener acceptable** at all, given the MCP server's localhost-only stance?
3. **Distribution**: Play / App Store, or GitHub releases and TestFlight only? It decides C.
4. **Does Inspektor grow a companion trust mode** (B1 without Shizuku, C without log tokens)?
5. **Background alerts on iOS**: accept foreground-only, or run a push relay?
6. **Name**: "Eagly" on the phone, or a separate name for the companion.
7. **Is seeing other apps' traffic in scope?** docs/NETWORK_INSPECTOR.md treats that as a stretch
   goal, and shape E on iOS mainly delivers it.
8. **An organization Apple Developer enrollment** for shape E on the App Store, or Android and
   self-signed iOS builds only.

## Claims to verify before deciding

- A root enabled in Certificate Trust Settings passes `dart:io`'s `SecTrust` check on a real iPhone
  (§7, First steps).
- A Network Extension can serve a loopback port that usbmux reaches.
- The `tun2proxy` or `ipstack` + `hudsucker` stack fits the iOS extension's memory limit.

- Android 13+ log-access consent dialog for apps holding `READ_LOGS`, and how often it asks.
- Shizuku's process uid and whether Inspektor's peer check sees 2000.
- Play policy on AccessibilityService use by a developer tool.
- SideStore / StikDebug's mechanism (pairing record + loopback VPN + `idevice`), and whether a
  comparable app has passed App Store review.
- `idevice` with `ring` cross-compiling for Android and iOS targets.
- Bugjaeger / Easycontrol as prior art for adb over OTG and phone-to-phone scrcpy.
