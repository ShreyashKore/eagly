# MCP server

> **Status: phase 1 is built (2026-10-25), not yet released or tried in the app UI.** §0 says
> what was built and where it departs from the plan; the rest is the plan written on 2026-10-22,
> kept as the reasoning behind it. Where they disagree, §0 wins. Facts about the MCP spec and the
> Dart packages were checked against primary sources on those dates ([References](#references)).
> Claims that still need checking are marked *unverified*.

**Goal.** Let a coding agent (Claude Code, Cursor, VS Code and others) see what Eagly sees about
a running app: the device list, its logs, iOS crash reports, the HTTP traffic Inspektor captures,
and the screen. An agent that can build and install an app today can't see it run. Eagly already
holds that runtime state, parsed and buffered, on Android and iOS alike, so it can close the loop.

## 0. What is built

Code is in `lib/features/mcp/`; tests are `test/mcp_protocol_test.dart`,
`test/mcp_http_server_test.dart`, `test/mcp_tools_test.dart` and `test/mcp_token_store_test.dart`.

| File | What it does |
|---|---|
| `mcp_protocol.dart` | JSON-RPC over Streamable HTTP, stateless and dual-era: a request whose `_meta` carries a protocol version is served as 2026-07-28 (`server/discover`, header checks, `resultType`); `initialize` and anything without `_meta` is served as 2025-11-25 back to 2025-03-26. Pure: headers and body in, status and body out. |
| `mcp_http_server.dart` | `dart:io` `HttpServer` on `127.0.0.1`, and the checks of §3.3: Host, Origin, JSON content type, POST only, optional bearer token, 1 MB body cap. |
| `mcp_server_controller.dart` | Lifecycle, preferences, the Settings state, the server `instructions`, the app-log line per call. Created in `HomeScreen`'s state. |
| `mcp_token_store.dart` | The bearer token, in its own owner-only file rather than in preferences (§3.3). |
| `tools/*.dart` | The tools, grouped by feature. `McpToolContext` resolves the `device` argument and holds the Network watcher open. |
| `components/mcp_settings_section.dart` | **Settings → MCP server**. |

**Tools (10):** `list_devices`, `list_apps`, `query_logs`, `wait_for_log`,
`list_network_requests`, `get_network_request`, `wait_for_network_request`,
`list_crash_reports`, `get_crash_report`, `take_screenshot`. `get_device_info` is not built yet:
`DeviceInfo` has no JSON form to return.

**Hooks added to existing controllers:** `LogController.appendedLogs` (each flush's new entries),
`packageForPid`, `isRetentionFilterActive`, `isActivated`; `NetworkController.holdWatching()` and
`capacity`.

**Decisions that differ from the plan below:**

1. **A hand-written server, not `mcp_dart`.** A tools-only, stateless server is about 300 lines,
   and the 2026-07-28 rules (`server/discover`, the `Mcp-Method`/`Mcp-Name` checks, version
   errors) were easier to get exactly right in code we own than to check in a library whose
   server API isn't documented on pub.dev. No new dependency.
2. **The bearer token is optional, off by default** (Settings → *Require an access token*). Host,
   Origin and the JSON content-type check already stop every request a web page can make; the
   token only adds protection from *other accounts* on the same machine. Without it, the URL is
   the whole config, the same on every machine, so a project can check in a `.mcp.json` as
   Flocon's users do. Turn it on for shared machines.
3. **The default device is the one selected in Eagly**, then the only connected one (Flocon does
   the same). The plan only defaulted when one device was connected.
4. **Port 9311 by default.** A taken port shows in Settings and is retried every 10 s, often
   another Eagly that is still quitting. No other port is picked silently.
5. **No header chip yet.** Settings shows *Listening on … · last client: Claude Code*, and every
   call goes to the app log.
6. **Waits return plain JSON**, with no SSE progress. `wait_*` cap at 120 s.

**Compared with Flocon** ([openflocon/Flocon](https://github.com/openflocon/Flocon), Kotlin,
`FloconDesktop/mcp/`): both embed a stateless Streamable HTTP server on loopback with tools
grouped per feature, server `instructions`, and a default target taken from the UI. Flocon is
always on with no authentication or Origin check, and its data comes from an SDK inside the app,
so it can also mock calls, read databases and open deeplinks. Eagly's comes from the device
(logcat, syslog, crash files, the screen), so it works on apps without an SDK. Only network
capture needs Inspektor.

**Verified:** the unit tests; Claude Code 2.1.310 connected to the server (it then could not run
a model, because the account has CLI access turned off); every tool and both eras driven over
HTTP with curl against fake devices. **Not yet:** the Settings section in the running app, a
real phone, a full agent session.

## TL;DR

- **Eagly is the server, and a model is never called from Eagly.** The agent the user already
  runs connects to Eagly. Eagly needs no API keys or billing, and it never sends device data to a
  cloud model itself.
- **Streamable HTTP on `127.0.0.1`, inside the running app.** Phase 1 has no headless mode and no
  stdio bridge. [`mcp_dart`](https://pub.dev/packages/mcp_dart) is the library to spike first,
  because [`dart_mcp`](https://pub.dev/packages/dart_mcp) has no HTTP server transport yet (§2.2).
- **Off by default, with a bearer token, and Origin and Host checks.** Any browser tab can
  reach a localhost port, so this server does *not* inherit the Inspektor protocol's
  no-authentication decision (§3.1).
- **Phase 1 is read-only.** No tool changes the device, an app, or the user's layout or
  selection. Tools may start capture that Eagly would start anyway: log streaming, or watching
  for Inspektor apps.
- **Eleven tools**, each a thin wrapper over a controller that already exists (§5). The work that
  takes design is elsewhere: bounding output for an agent's context, and two small lifecycle
  hooks so tools can wait for a log line or keep the Network watcher running without its pane (§4).

## 1. What it is for

The use cases that set the phase-1 scope:

1. **A closed debugging loop.** The agent edits code, builds and installs (with its own tools),
   then waits for a log line, reads the failing request's response body, and checks a screenshot.
2. **Crash triage.** The agent pulls an iOS crash report and the logs from just before it, then
   searches the codebase.
3. **Checking the API contract.** The agent compares the recorded responses with an OpenAPI spec or
   the app's models.
4. **Bug reports.** The agent gathers a screenshot, a filtered log excerpt and the failing
   exchanges into an issue.

Phase 2 adds actions: launching an app, input, the UI tree, Inspektor overrides for mocking, and
emulators. It is sketched in §6 so phase 1 doesn't box it in.

## 2. Transport

### 2.1 Streamable HTTP inside the GUI process

- **One endpoint, `POST http://127.0.0.1:<port>/mcp`**, served by the running Eagly app. When
  Eagly quits, the server goes with it and the agent sees connection refused. The tools are only
  useful with Eagly's state anyway: an activated log tab, an attached Inspektor app.
- **Spec target: 2026-07-28, with a fallback to the initialize flow** for clients still on
  2025-11-25 and earlier. The 2026-07-28 revision makes Streamable HTTP simpler, and that suits
  an in-process server:
  - There are no protocol sessions and no `Mcp-Session-Id`. GET and DELETE on the endpoint
    return 405.
  - Every POST carries `MCP-Protocol-Version`, `Mcp-Method` and, for `tools/call`, `Mcp-Name`. The
    server rejects a mismatch with the body.
  - A response is either `application/json` or a `text/event-stream` for that request alone.
    Progress notifications can ride on it, which is what `wait_for_log` uses (§5.2).
  - Server-initiated change notifications go through `subscriptions/listen`. Phase 1 doesn't
    need them (open question 5).
- **Connecting:** Settings shows the exact command, for example:

  ```bash
  claude mcp add --transport http eagly http://127.0.0.1:<port>/mcp --header "Authorization: Bearer <token>"
  ```

  It also shows a JSON snippet for clients configured by file (Cursor, VS Code).
- **Port:** a fixed default that the user can override, so the client config survives restarts.
  If the port is taken, Eagly says so in Settings and doesn't silently pick another one (open
  question 2).

### 2.2 Library

| | `mcp_dart` 2.4.3 | `dart_mcp` 0.5.2 |
|---|---|---|
| Publisher | leehack.com (verified), MIT | labs.dart.dev (Dart team), BSD-3 |
| Status | Not marked experimental | "Still experimental and likely to evolve quickly" |
| Server transports | stdio, **Streamable HTTP** on the Dart VM and desktop | stdio only. Streamable HTTP is "unsupported at this time" |
| Protocol | Prefers 2026-07-28 and falls back to the initialize flow down to 2024-11-05 | Up to 2025-11 |
| Security helpers | DNS-rebinding (Host and Origin) protection, authenticator hooks | None. "Aimed at local use" |

**Recommendation: spike `mcp_dart`.** Check five things: that its HTTP server can run on
`dart:io`'s `HttpServer` inside a Flutter desktop app, that it lets us bind to a chosen port, that
the bearer-token hook works, that progress notifications on a request's SSE stream work, and
that it builds on all three desktop platforms. If the spike fails, the fallback is a hand-written
JSON-RPC handler over `HttpServer`. Phase 1 uses tools only, so that's a few hundred lines, and
`dart_mcp`'s types could still be borrowed.

### 2.3 Not in phase 1

- **A stdio bridge** (`eagly mcp` as a small CLI that forwards stdio to the HTTP port), for
  clients that only speak stdio. The clients that matter most accept HTTP (open question 3).
- **Headless mode** (the server without a window, for CI). The controllers are built around a
  window and `HomePage`'s state. Revisit this only if someone asks.

## 3. Security model

### 3.1 Why this differs from Inspektor's socket

The Inspektor protocol has no authentication by design (NETWORK_INSPECTOR.md §4.3). Its socket
lives *on the device*, it is reached only through `adb forward` or usbmux, and it exists only in
development builds. This server is an HTTP port *on the developer's desktop*, and every web page
open in their browser can try to reach it. The two decisions don't conflict, and the reasoning
behind one doesn't carry over to the other.

### 3.2 Threats

| Threat | Example | Control |
|---|---|---|
| A web page in the user's browser | A page sends `fetch('http://127.0.0.1:<port>/mcp', …)`, or uses DNS rebinding to look same-origin | Origin and Host checks, plus the bearer token |
| Another machine on the network | Something on café Wi-Fi scans for the port | Bind to loopback only |
| Another local user account | A shared Mac or a lab machine | Bearer token; the token file is readable only by its owner |
| Prompt injection through device data | A log line or response body says "ignore previous instructions and…" | Phase 1 is read-only; device text is labelled as untrusted (§3.4) |
| Secrets reaching a cloud model | `Authorization` headers, session cookies, tokens printed to the log | The user turns the server on and picks the agent; sensitive headers are redacted by default (§3.4) |
| A careless agent | It asks for 100k log lines and fills its context | Output budgets (§5.1) |

Other processes running as the same user are **out of scope**. They can already run the bundled
`adb`, read Eagly's files and read the token, so no local control stops them.

### 3.3 Controls

- **Off by default.** Settings gets an **MCP server** section with an on/off switch, the port,
  the token (copy and regenerate), the connect commands, and the redaction setting.
- **Bind to `127.0.0.1` only.** There's no setting for another address in phase 1. IPv6 `::1`
  is open question 2.
- **Check the Host header.** It must be `127.0.0.1:<port>` or `localhost:<port>`, or the server
  returns 403. This stops DNS rebinding even when a request carries no Origin.
- **Check the Origin header.** The spec requires it ("MUST"). A request *with* an Origin header is
  rejected with 403 unless the origin is loopback on Eagly's own port. Agents send none.
- **Bearer token** (built as optional and off by default; see §0). 256 random bits, made on the
  first launch that has the MCP code, and compared in constant time. It is kept in its own file,
  `<app support>/mcp_token`, readable only by its owner (0600 on macOS and Linux, set before the
  token is written; on Windows the per-user app support folder is private already). Not in
  Eagly's preferences: on Linux shared_preferences writes its JSON file 0644, so another account
  could read it under a 0755 home. A token an older build kept in preferences moves into the file
  and leaves preferences. The
  spec only says servers "SHOULD" authenticate. The plan was to require it because a browser can't send this header to another origin without
  a CORS preflight, and the server answers no preflight. Regenerating the token breaks every
  configured client, and that's intended.
- **No CORS headers at all.** The server answers no preflight (`OPTIONS`) request, and sends no
  `Access-Control-Allow-*` header.
- **The server shows its state in the app.** A chip in the header reads *MCP · Claude Code*,
  using the client's `clientInfo`, while a client is connected. Each tool call is written to
  Eagly's app log (`features/app_log/`) with the tool name, the device and the duration, but not
  the results.
- **Nothing reaches Sentry.** Tool arguments and results hold device data. Breadcrumbs record
  only "MCP tool `query_logs` called".

### 3.4 Data handling

- **Device text is data.** Each tool's description says its results contain text from the app
  under test, which may hold instructions that must not be followed. That doesn't stop prompt
  injection; it only labels the risk. Read-only tools limit what an injected instruction can do.
  Phase 2's actions are where this starts to bite (§6).
- **Sensitive headers are redacted by default** in `get_network_request`: `Authorization`,
  `Proxy-Authorization`, `Cookie`, `Set-Cookie`, and any header whose name contains `token`,
  `secret` or `api-key`. The value becomes `<redacted, 143 chars>`. A Settings switch turns this
  off (open question 6).
- **Bodies are fetched only on request**, and capped (§5.1). Lists never include bodies.
- **Tool annotations are hints.** Every phase-1 tool declares `readOnlyHint: true` and
  `openWorldHint: false`. The spec says clients must not trust annotations from servers they
  don't trust, so these only help clients that already trust Eagly. The server enforces
  read-only itself: phase 1 registers no tool that writes.

## 4. How tools reach the controllers

### 4.1 Ownership

- **A new feature, `lib/features/mcp/`.** `McpServerController` (a `ChangeNotifier`) owns the
  `HttpServer`, the tool registry and the connection state the header chip shows. It is created
  in `HomePage`'s state next to `DeviceSessionManager` and is given the manager by constructor,
  the same way the rest of the app is wired (no DI framework).
- **Each tool is one file** with a schema, a handler and an output budget, and it works only
  through `DeviceSessionManager` → `DeviceSessionController` → the feature controllers. A tool
  never runs an `AdbTool` or a `services/ios/*` call directly. That keeps the agent's view the
  same as the user's, and the existing connect and disconnect hooks still apply.
- **Device ids are `Device.id`**: the adb serial or the iOS UDID. Left out, `device` means the
  device selected in Eagly, else the only connected one (§0).

### 4.2 What "read-only" allows

A phase-1 tool **may**:
- call `DeviceSessionController.activate()` for a device the user hasn't opened yet. That
  starts log capture in the first live tab, exactly as opening the tab would, but it doesn't
  select the tab.
- pull crash reports into Eagly's temporary folder.
- take a screenshot.
- keep the Inspektor watcher running (§4.4).

A phase-1 tool **must not**:
- change the device or an app;
- open, close or move a pane, switch the selected device or log tab, or change the user's
  filters;
- write outside Eagly's temporary folder.

### 4.3 Logs: what the buffer holds

- A tool reads `LogController.logs` from the device's **first live tab** and applies its *own*
  `LogFilters` (parsed with `LogFilters.parse`, matched with `matchesLogFilters`). The user's
  filter pills don't affect what the agent sees through the filter.
- **They do affect what was kept.** Once the `LogBuffer` is full, its retention filter evicts the
  lines that *don't* match the user's active filter first. So with a narrow filter active, older
  lines the agent asks for may already be gone. `query_logs` reports `oldestRetainedId` and
  `retentionFilterActive` so the agent can tell (open question 7).
- The buffer holds 100,000 lines by default (`PreferencesService.defaultLogLinesLimit`).
- **Cursors are `LogEntry.id`**, which is monotonic within one Eagly run
  (`LogEntryIdGenerator`), and resets when Eagly restarts. A response includes a
  `captureEpoch` (the time the app started) so an agent holding an old cursor gets a clear error,
  not wrong results.
- Special entries (`started`, `paused`, `error`, …) are left out unless asked for. Their state is
  reported as `capture: {running, paused, interrupted, recovering}`, taken from
  `LogController.isRunning`, `isPaused`, `liveLoggingInterrupted` and `isRecovering`.
- **New hook for `wait_for_log`:** `LogController` gets a broadcast stream of the entries each
  300 ms flush appends. Without it, a waiter would have to poll the buffer and diff it.

### 4.4 Network: the watcher lives with the pane

`NetworkController._syncWatching` polls for Inspektor apps only while the Network pane is open.
Opening the pane from a tool would change the user's layout, which §4.2 rules out. Instead:

- **A new hook: `NetworkController.holdWatching()`**, which returns a release handle and keeps
  the watcher running while any hold is open. The MCP server takes one per device as soon as a
  network tool touches that device, and releases it when the client goes quiet or the server
  stops. The watcher runs when the pane is open *or* a hold is.
- Connections already made outlive a closed pane, as they do today.
- **Cursors:** `NetworkEntry.key` (`source` and `id`), plus the store's order. The store is capped
  at 5,000 entries and an update keeps an exchange in place, so `list_network_requests` pages by
  position in the store and reports evictions, as `query_logs` does.
- **New hook for `wait_for_network_request`:** a stream of changed keys, next to the existing
  `_scheduleNotify`.

### 4.5 Threading and cost

Everything runs on the UI isolate, as the controllers do. A `query_logs` call over a full
buffer scans newest-first and stops at `limit`, so it costs less than the UI's own refilter. Image
downscaling for screenshots uses `dart:ui`'s codec with a target width, which decodes off the UI
thread.

## 5. Phase-1 tools

### 5.1 Common rules

- **Results:** `structuredContent` matching each tool's `outputSchema`, plus the same JSON as a
  text block for older clients. `take_screenshot` returns an image block.
- **Errors:** a tool error uses `isError: true` with a message the agent can act on, for example
  "No device given and 2 are connected: …" or "Network inspection needs an app with Inspektor's
  remote inspection turned on; see docs/NETWORK_PANE.md".
- **Output budgets:** each tool has a default and a maximum `limit`. Each text field is capped
  (a log message at 4 KB, a body at 64 KB by default and 1 MB at most), and so is the whole
  response (512 KB). Whatever is cut is reported (`truncated: true`, `omittedCount`), never cut
  silently.
- **Filters reuse Eagly's syntax.** Log filters are the filter bar's typed syntax (`tag:Auth
  level:w -message~:^heartbeat`), and network queries are the Network pane's query language.
  The tool descriptions spell out the grammar, so the agent and the user write the same thing.

### 5.2 Tools

| Tool | Parameters | Returns | Backed by |
|---|---|---|---|
| `list_devices` | — | `id`, `platform`, display name, model, `connectionState`, and per-device capabilities: `canMirror`, `canReadCrashReports`, `canInspectNetwork` | `DeviceSessionManager.devices` / `sessions`, `DeviceSessionController.can*` |
| `get_device_info` | `device` | Identity, software, display, battery, storage, connectivity, developer state | `DeviceHomeController.deviceInfo` (`service.fetchDeviceInfo()`) |
| `list_apps` | `device`, `includeSystem` (default false), `query` | Package or bundle id, name, `versionName`, `versionCode`, `isSystemApp` | `AppsController.ensureLoaded()` and its app list |
| `query_logs` | `device`, `filter`, `level` (default `w`), `sinceId`, `beforeId`, `limit` (default 200, max 2,000), `includeSpecial` | Entries (`id`, `timestamp`, `level`, `tag`, `pid`, `tid`, `package`, `message`), `nextCursor`, `oldestRetainedId`, `retentionFilterActive`, `capture` | `LogSessionManager.tabs.first`, `LogController.logs`, `LogFilters.parse`, `matchesLogFilters` |
| `wait_for_log` | `device`, `filter`, `sinceId` (default: now), `timeoutSeconds` (default 30, max 120) | The first matching entry and the few before it, or `timedOut: true` with the current cursor | The new `LogController` appended stream (§4.3); progress notifications while waiting |
| `list_crash_reports` | `device`, `process`, `since` | `fileName`, `processName`, `timestamp`, `sizeBytes`, newest first | `CrashReportController.ensureLoaded()` / `refresh()`, `reports`. iOS only (`canReadCrashReports`) |
| `get_crash_report` | `device`, `fileName`, `maxBytes` (default 256 KB) | The report text | `readTextLenient(File(report.filePath))`, as `CrashReportController.select` reads it, without touching the selection |
| `list_network_requests` | `device`, `query`, `statusClasses`, `types`, `cursor`, `limit` (default 100, max 1,000) | Rows (`key`, method, URL, status, `state`, duration, sizes, `adapter`, `overridden`), the attached apps, `nextCursor`, `evicted` | `NetworkController.entries` and `sources`, `NetworkFilter`, `holdWatching()` |
| `get_network_request` | `device`, `source`, `id`, `bodies` (`none`/`request`/`response`/`both`, default `response`), `maxBodyBytes` | Request and response headers (redacted, §3.4), timings, `error`, override info with original values, and bodies as UTF-8 text, or size and content type when a body is binary | The `NetworkEntry` by key, `NetworkController.loadBody(key, part)`, `NetworkBody.text` |
| `wait_for_network_request` | `device`, `query`, `timeoutSeconds` (default 30, max 120) | The first new matching row, or `timedOut: true` | The new changed-keys stream (§4.4) |
| `take_screenshot` | `device`, `maxEdge` (default 1,280 px) | A PNG image block, plus its size and orientation | `DeviceSessionRepository.captureScreenshot()`: `screencap` on Android, CoreDevice on iOS. Downscaled with `dart:ui` |

Notes on individual tools:

- **`take_screenshot` on iOS** takes 0.6–1.5 s and returns a PNG of about 7 MB at full size
  (IOS_SCREEN_MIRROR.md), hence the downscaling. It needs the same CoreDevice services the mirror
  pane uses (*unverified* whether that works on a phone that has never had the mirror opened).
- **Android crashes** are in logcat, not in files. Until open question 4 is settled, the
  description of `list_crash_reports` points the agent to `query_logs` with
  `tag:AndroidRuntime level:e`.
- **HAR export** is left out. The agent can build what it needs from `get_network_request`, and
  a 5,000-entry HAR breaks any response cap (open question 9).

## 6. Phase 2 (for scope only)

These are actions, so each needs its own design and the read-only guarantee goes away:
- launch, force-stop, clear data and install (`AppsController`);
- tap, swipe and type (`MirrorController` over the scrcpy control socket and iOS HID);
- the UI tree (`uiautomator dump`);
- Inspektor overrides for mocking (NETWORK_INSPECTOR.md phase 3);
- emulators (`EmulatorManagerController`);
- the utilities catalog.

What phase 1 should leave room for:
- **A second switch, "Allow agents to control devices"**, off even when the server is on. Tools
  that write are registered only while it's on, and declare `destructiveHint` honestly.
- **Asking the user in the app** before a destructive action (uninstall, clear data, deleting
  files). MCP's elicitation now goes through `InputRequiredResult` in 2026-07-28. Whether clients
  show it well is *unverified*, so Eagly's own dialog is the safer default.

## 7. Work list

1. Spike `mcp_dart` (§2.2).
2. `lib/features/mcp/`: the server, Host, Origin and token checks, the tool registry, the
   budgets, and a redaction helper.
3. `LogController`: an appended-entries stream.
4. `NetworkController`: `holdWatching()` and a changed-keys stream.
5. The eleven tools.
6. Settings section, header chip, and preference keys for enabled, port, token and redaction.
7. Tests:
   - each tool against a fake session (`DeviceSessionManager` already takes a
     `serviceFactory`);
   - HTTP tests that a bad Host, a foreign Origin, a missing or wrong token and an `OPTIONS`
     request are all refused;
   - budget and truncation tests;
   - one device test that connects a real MCP client (Claude Code) to a running app.
8. A paragraph in AGENTS.md under *Domain notes*, pointing here.

## 8. Open questions

1. **The library.** `mcp_dart` or a hand-written handler, depending on the spike. Do we also need
   to accept 2025-03-26 clients that send no `MCP-Protocol-Version` header?
2. **Port and address.** Which fixed default port? Should we also listen on `::1`? Some clients
   resolve `localhost` to IPv6 first.
3. **A stdio bridge.** Is any client we care about stdio-only? If so, should it be a bundled
   Dart executable, or should we document a generic HTTP-to-stdio proxy?
4. **Android crashes.** Should `list_crash_reports` cover Android by reading `adb logcat -b crash
   -d` (cheap, and buffered on the device) or by scanning the log buffer for `FATAL EXCEPTION`?
   The first also covers crashes from before Eagly was opened.
5. **Resources and subscriptions.** Would exposing the live log as a resource with
   `subscriptions/listen` help agents, or would the `wait_*` tools cover the real need? Few
   clients surface resource subscriptions well today.
6. **The redaction default.** Redacting by default protects tokens, but breaks "why is this
   request unauthorised?". Should redaction keep a hash or a prefix of the value so two requests
   can be compared?
7. **Retention.** Should the MCP server keep its own small ring buffer of recent warnings and
   errors, unaffected by the user's filter? That makes `query_logs` predictable at the cost of
   memory.
8. **How many tools.** Should the waits be separate tools or a `wait` parameter on the list
   tools? Fewer tools are easier for an agent to choose between. Separate tools are easier to
   describe.
9. **HAR export.** Should it write a HAR file to the capture folder and return the path? That's
   useful when the agent runs on the same machine, but it writes a file the user didn't ask for.
10. **Imported logs and HAR files.** Should the tools also see the device-less "Imported Logs"
    workspace, and HAR files opened in the Network pane? It's cheap, and makes "analyse this log
    file" work.
11. **Several clients at once.** Two agents connected at the same time share the same holds and
    cursors. Is a per-client hold count enough, or do they need more separation?
12. **Record mode.** `--record-mode` replaces serials and UDIDs with stand-ins. Should the server
    refuse to start in record mode, or report the stand-ins?

## References

- MCP spec 2026-07-28: [Streamable HTTP transport](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)
  (Origin validation, loopback binding, removing sessions, protocol headers) and
  [Tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools) (structured
  output, image content, annotations).
- [`mcp_dart` on pub.dev](https://pub.dev/packages/mcp_dart) and
  [`dart_mcp` on pub.dev](https://pub.dev/packages/dart_mcp): versions and transport support as
  of 2026-10-22.
- In this repo: [NETWORK_INSPECTOR.md](NETWORK_INSPECTOR.md) §4.3 (Inspektor's trust model),
  [LOG_STREAMING.md](LOG_STREAMING.md), [IOS_SCREEN_MIRROR.md](IOS_SCREEN_MIRROR.md),
  [NETWORK_PANE.md](NETWORK_PANE.md).
