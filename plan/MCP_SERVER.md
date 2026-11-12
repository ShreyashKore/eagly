# MCP server: plan

> **Status: not built.** Phase 1 is built and described in
> [docs/MCP_SERVER.md](../docs/MCP_SERVER.md). This file holds phase 2, what is left of phase 1's
> work list, and the open questions. Section numbers follow the docs file, so §0 to §5
> references point there.

## 6. Phase 2 (for scope only)

These are actions, so each needs its own design and the read-only guarantee goes away:
- launch, force-stop, clear data and install (`AppsController`);
- tap, swipe and type (`MirrorController` over the scrcpy control socket and iOS HID);
- the UI tree (`uiautomator dump`);
- Inspektor overrides for mocking ([plan/NETWORK_INSPECTOR.md](NETWORK_INSPECTOR.md#phase-3-overrides-and-richer-detail-needs-i-2-i-3-parts-as-they-land));
- emulators (`EmulatorManagerController`);
- the utilities catalog.

What phase 1 should leave room for:
- **A second switch, "Allow agents to control devices"**, off even when the server is on. Tools
  that write are registered only while it's on, and declare `destructiveHint` honestly.
- **Asking the user in the app** before a destructive action (uninstall, clear data, deleting
  files). MCP's elicitation now goes through `InputRequiredResult` in 2026-07-28. Whether clients
  show it well is *unverified*, so Eagly's own dialog is the safer default.

## 7. Work list

What is left of phase 1's work list. Spiking `mcp_dart` was settled by writing the server by
hand (decision 1 in [docs §0](../docs/MCP_SERVER.md#0-what-is-built)); the server and its checks,
`LogController.appendedLogs`, `NetworkController.holdWatching()`, the Settings section, the
preference keys, the unit and HTTP tests, and the AGENTS.md paragraph are built. The planned
changed-keys stream on `NetworkController` wasn't needed: `wait_for_network_request` listens to
the controller instead.

1. `get_device_info`, the eleventh tool: `DeviceInfo` has no JSON form to return yet.
2. The header chip: it reads *MCP · Claude Code*, from the client's `clientInfo`, while a
   client is connected. Settings shows the state for now (decision 5 in docs §0).
3. Tests: one device test that connects a real MCP client (Claude Code) to a running app. So far
   Claude Code connected to the server but could not run a model; the Settings section in the
   running app, a real phone and a full agent session are not tried yet.

## 8. Open questions

Numbered as the docs file cites them; settled ones are kept as one line so the numbers hold.

1. *Settled:* the server is hand-written, and requests without `_meta` are served back to
   2025-03-26 (docs §0).
2. **Address.** The default port is 9311 (docs §0). Should we also listen on `::1`? Some clients
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
8. *Settled:* the waits are separate tools (`wait_for_log`, `wait_for_network_request`).
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

- In this repo: [docs/MCP_SERVER.md](../docs/MCP_SERVER.md) (phase 1: transport, security model,
  tools) and [plan/NETWORK_INSPECTOR.md](NETWORK_INSPECTOR.md) (phase 3, overrides).
