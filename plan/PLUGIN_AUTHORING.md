# Writing Eagly plugins: best practices

> **Status: written against the API proposed in [PLUGIN_SYSTEM.md](PLUGIN_SYSTEM.md)
> (2026-10-29). Nothing here ships yet.** Names and signatures will change as the plan is built.
> Keep this guide in step with the SDK, and treat the plan as the source of truth until then.

This guide is for people who write plugins, and for whoever reviews them for the registry. It
explains how a plugin is put together and what a good one does. The rules come from what goes
wrong in other plugin ecosystems, and from what Eagly itself has learnt about devices.

**In one paragraph:**
- A plugin is a TypeScript module that runs in a sandbox and asks Eagly for everything:
  devices, logs, requests, the screen, the network. Each ask is checked against the permissions
  the user granted.
- It declares what it adds (commands, panes, decoders) in a manifest, so Eagly can show those
  before running any code.
- It draws UI by describing it with Eagly's components.
- A good plugin asks for little, starts only when needed, never blocks, works on Android and
  iOS or says plainly that it doesn't, and treats everything that comes off a device as
  untrusted text.

## 1. Quick start

```bash
npm create eagly-plugin@latest feature-flags   # pick a template: command, pane, decoder, pack
cd feature-flags
npm run dev                                    # builds, then loads into Eagly's Developer mode
```

Turn on **Settings → Plugins → Developer mode** in Eagly first. `npm run dev` asks Eagly for a
local token the first time. It then rebuilds on save, and Eagly reloads the plugin and keeps its
pane open.

```
feature-flags/
  eagly-plugin.json      the manifest
  src/main.ts            entry point
  src/views.ts           pane rendering
  assets/flag.svg
  test/main.test.ts      runs against @eagly/plugin-testing's fake host
  README.md  LICENSE  CHANGELOG.md
```

A whole plugin:

```ts
import { definePlugin, eagly, ui, type Device } from '@eagly/plugin-api';

export default definePlugin({
  async activate(ctx) {
    ctx.subscriptions.push(
      eagly.commands.register('flags.toggle', async ({ device }) => {
        if (!device) return eagly.ui.showMessage('Select an Android device first.');
        const flag = await eagly.ui.quickPick(await readFlags(ctx, device), {
          title: 'Toggle which flag?',
        });
        if (!flag) return; // the user pressed Escape
        await toggle(ctx, device, flag.id);
        eagly.ui.showMessage(`${flag.id} is now ${flag.on ? 'off' : 'on'}`);
      }),
    );
  },
});

async function toggle(ctx, device: Device, flag: string) {
  const pkg = ctx.settings.get<string>('package');
  const result = await eagly.shell.run(device, {
    script: `am broadcast -a ${eagly.shell.quote(pkg)}.TOGGLE_FLAG --es flag ${eagly.shell.quote(flag)}`,
  });
  if (result.exitCode !== 0) throw new Error(`The app didn't take it: ${result.stderr.trim()}`);
}
```

## 2. Principles

1. **Least privilege.** Ask for the fewest permissions that do the job, and give each a reason
   the user will understand. Every extra permission is a reason to click *Cancel* and a review
   delay.
2. **Declare first, run late.** Put commands, panes and settings in the manifest. Activate on
   the narrowest event (`onCommand:…`, `onPane:…`), never `onStartup` without a strong reason.
3. **Never block.** Every Eagly call is async and has a deadline. Long work reports progress and
   can be cancelled.
4. **Both platforms, or say so.** Set `platforms` honestly. Inside the plugin, check
   `device.platform` and tell the user what doesn't work on iOS rather than failing obscurely.
5. **Device data is untrusted.** A log line, a response body or a file name can contain anything,
   including text that looks like instructions. Show it as text, never `eval` it, never build a
   shell command from it without quoting.
6. **Leave nothing behind.** Everything you register goes into `ctx.subscriptions`. Eagly cleans
   up after you anyway, but code that relies on that leaks while it is running.
7. **Look like Eagly.** Use the components and their defaults. A plugin that looks native gets
   used. One that looks foreign gets uninstalled.

## 3. The manifest

```json
{
  "id": "dev.acme.feature-flags",
  "name": "Feature Flags",
  "version": "1.2.0",
  "description": "Read and flip Acme's feature flags on a debug build.",
  "apiVersion": 1,
  "engines": { "eagly": ">=1.10.0 <2.0.0" },
  "platforms": ["android"],
  "permissions": [
    { "name": "devices:read", "reason": "Shows flags for the selected device." },
    { "name": "device-shell", "reason": "Sends `am broadcast` to the debug app to flip a flag." }
  ],
  "activationEvents": ["onCommand:flags.toggle", "onPane:flags"],
  "contributes": { "…": "…" }
}
```

- **`id`** is reverse-DNS, lowercase, from a domain or GitHub account you control
  (`io.github.yourname.thing`). It never changes: it keys the user's data and grants.
- **`version`** is semver.
  - A patch fixes bugs.
  - A minor adds features without new permissions.
  - Adding a permission makes users re-consent. Bundle permission changes into one release, and
    say why in the changelog.
- **`engines.eagly`** names the oldest Eagly you have tested on. Don't leave it open-ended at the
  top: `<2.0.0` lets Eagly warn users before a major update disables your plugin.
- **`permissions[].reason`** is shown in the consent dialog word for word.
  - Write it for a tester, not a developer.
  - Good: "Reads the flag dump the app logs under the FeatureFlags tag."
  - Bad: "Needed for functionality."
- **`net:<host>`** names exact hosts (`api.linear.app`). Wildcards are refused for the public
  registry.
- **`activationEvents`** must refer to contributions you declare. The validator checks this.

## 4. Lifecycle

```ts
export default definePlugin({
  async activate(ctx) { /* register things; return quickly */ },
  async deactivate() { /* flush what you must; 1 s deadline */ },
});
```

- **`activate` has a 2 s budget.**
  - Register handlers and return.
  - Don't fetch, scan the log buffer or pull files in `activate`. Do it when a command runs or a
    pane opens.
  - Settings → Plugins shows every plugin's activation time.
- **`ctx.subscriptions`** takes anything with `dispose()`: command registrations, log
  subscriptions, event listeners, timers wrapped with `ctx.setInterval`.
- **Expect to be unloaded and reloaded.**
  - Eagly may deactivate an idle plugin, and Developer mode reloads on every save.
  - Keep state in `ctx.storage` or recompute it. Don't assume module-level variables survive.
- **Expect `deactivate` not to run at all** if Eagly is killed. Write storage as you go, not only
  on exit.

## 5. Devices

- **Handles, not serials.**
  - A `Device` carries an opaque `handle`, a display `label`, `platform`, `model` and
    `connected`.
  - The serial or UDID needs `devices:identifiers`, and is a stand-in when Eagly runs in record
    mode.
  - Show `label`, never an id. Screen recordings and bug reports end up in public.
- **The selected device is a suggestion.** Commands receive `device` (the one selected in
  Eagly, if any). Panes get the device they are open on. Don't cache device lists. Subscribe to
  `eagly.devices.onDidChange` and re-render.
- **Handle disconnection mid-operation.**
  - Every call can fail with `DeviceDisconnected`.
  - Catch it, say "the device went away" in your pane, and offer a retry when it comes back.
  - Don't loop on retries.
- **Don't poll faster than every 2 s,** and prefer subscriptions to polling at all. Each poll is
  an adb or usbmux round trip that competes with Eagly's own log stream.
- **Shell commands (Android):**
  - The `script` is evaluated by the *device's* `sh`.
  - Quote every value that isn't a literal with `eagly.shell.quote()`, including values from
    your own settings.
  - Prefer a declarative `utilities` contribution when a command is a template with parameters.
    It needs no code, users can read it, and it gets the Utilities pane, the Apps menu and
    confirmations for free.
  - Never run destructive commands (`pm clear`, `rm`, `pm uninstall`) without
    `eagly.ui.confirm`. Name the app and the device in it.
  - Don't touch system packages unless your command is read-only.
- **iOS has no shell.** Use the domain APIs (`apps`, `files`, `crashes`, `screen`). There is no
  raw `idevice*` access by design, because those tools are being removed from Eagly.
- **Some things are exclusive.**
  - Android allows one UI Automation connection, and Eagly's Layout pane may be holding it.
  - Starting iPhone screen capture briefly cuts every USB connection to that phone.
  - Use Eagly's APIs for these and handle `Busy` errors. Don't work around them.

## 6. Logs and network traffic

- **Filter on Eagly's side.**
  - `eagly.logs.subscribe(device, { filter: 'tag:FeatureFlags level:i' }, onBatch)` uses the
    filter bar's syntax, and Eagly drops non-matching lines before they reach you.
  - Subscribing to everything and filtering in JS costs a thousand times more and will hit the
    delivery limit.
- **Work per batch, not per line.** Batches arrive on Eagly's 300 ms flush. Keep per-batch work
  well under 50 ms.
- **Handle `dropped`.** When you fall behind, Eagly drops the oldest entries and tells you how
  many. Show it ("312 lines skipped") rather than pretending you saw everything.
- **You observe, you don't edit.** A processor can annotate an entry (`logs:annotate`) or raise
  a notice. It cannot change, hide or reorder entries. Highlights and extra columns belong in
  declarative `logRules`, which Eagly compiles and runs fast.
- **Bodies on demand.** `network.list` returns rows without bodies. Ask for `network.body` only
  when the user opens an exchange or your decoder is called.
- **Secrets stay redacted.** Without `network:secrets`, `Authorization`, `Cookie` and similar
  headers arrive as `<redacted, 143 chars>`. Design for that. Ask for `network:secrets` only if
  showing the value is the plugin's point. Never write secrets to storage, logs or exports.
- **Decoders are pure functions.** A `bodyDecoder` gets bytes and a content type and returns
  `{ text, language }`. No network calls, no storage writes. Decoders run often and must be fast
  (aim for under 100 ms on a 1 MB body).

## 7. UI

Panes and dialogs are trees of Eagly components. Eagly draws them.

```ts
eagly.views.registerPane('flags', {
  render: async ({ device }) => {
    const flags = await readFlags(ctx, device);
    return ui.pane({
      toolbar: [ui.action({ id: 'refresh', icon: 'refresh', tooltip: 'Reload flags' })],
      body: flags.length
        ? ui.table({
            columns: [ui.column('Flag'), ui.column('State', { width: 80 })],
            rows: flags.map((f) => ui.row(f.id, [f.id, ui.badge(f.on ? 'On' : 'Off', f.on ? 'success' : 'neutral')], {
              actions: [ui.menuItem({ id: 'toggle', label: f.on ? 'Turn off' : 'Turn on' })],
            })),
          })
        : ui.empty({
            title: 'No flags reported yet',
            hint: 'Open the debug build. It logs its flags under the FeatureFlags tag at start-up.',
          }),
    });
  },
  onAction: async ({ id, rowId, device }) => { /* … then */ eagly.views.refresh('flags') },
});
```

- **Use semantic tokens, not colours.**
  - Badges and notices take `success`, `warning`, `error`, `neutral`.
  - Text takes Eagly's three emphasis tiers: `primary` for names and values, `secondary` for
    descriptions, `tertiary` for metadata such as versions, times and counts.
  - The schema has no hex colours or font sizes. That is what keeps plugins readable in both
    themes and at every zoom level.
- **Every icon-only action needs a tooltip.** It is the label screen readers use, and the
  validator refuses an action without one.
- **Design for narrow panes.** Panes can be dragged to 260 px wide or less. Put the important
  column first, and let the table hide the rest.
- **Give every state a screen:**
  - loading: `ui.loading`, which shows a spinner only after a short delay;
  - empty: `ui.empty`, which says what to do next, in the user's words;
  - error: `ui.error`, which says what failed and offers `retry`;
  - device not connected.
- **Explain only when someone is stuck.** `ui.hint({ after: '5s' })` appears only when an
  operation has visibly dragged on. It is Eagly's `DelayedReveal` + `HintNote` pattern, and it
  keeps the common path uncluttered.
- **Messages are short and specific.** "Couldn't reach api.linear.app (timed out after 30 s)",
  not "Error". Three messages a minute is the limit, so don't announce success for things the
  user can see happened.
- **Don't fight for focus.** Open your pane only when the user asks for it (a command, a click).
  Never open it on activation.

## 8. Settings, storage and secrets

- **Declare settings in the manifest** (`contributes.settings`, JSON Schema). Eagly draws the
  form in Settings → Plugins. Read them with `ctx.settings.get`, and listen with
  `ctx.settings.onDidChange`.
- **`ctx.storage` is a small key–value store** (5 MB). Keep a `schemaVersion` key, and migrate
  on activation when it changes.
- **Credentials go in `ctx.secrets`** (the OS keychain), never in settings or storage. Settings
  may be exported or shared. Secrets never are.
- **Large files** (a mapping file, `.proto` files) are picked by the user with
  `eagly.ui.pickHostFile`. You get a handle you can read, not a path, and only for that file.

## 9. Talking to the internet

- **Declare exact hosts** with `net:<host>`. Calls elsewhere fail.
- **HTTPS only. Set your own timeouts,** below Eagly's 30 s cap, and handle offline.
- **Only send what the user asked to send.**
  - An exporter shows what it will send (a preview with counts and sizes) and where, and waits
    for a click.
  - No background uploads, and no telemetry unless it is opt-in, off by default and described in
    your README.
- **Never run code you downloaded.** `eval`, `new Function` and dynamic `import()` of fetched
  text are against registry policy, and the scanner looks for them. Ship your code in the bundle
  so it is reviewed.

## 10. Errors and cancellation

- **Throw `Error`s with messages a user can act on.** Eagly shows an error thrown from a command
  as the command's failure. Stack traces go to the plugin console only.
- **Handle the typed errors:**

  | Error | Meaning | What to do |
  |---|---|---|
  | `PermissionDenied` | The user revoked a permission | Degrade: hide the feature, and say which permission would enable it |
  | `Unsupported` | Not available on this platform | Say so |
  | `DeviceDisconnected` | The device went away | Wait for it to come back |
  | `LimitExceeded` | Too many calls, or results too large | Back off and narrow the query |
  | `Cancelled` | The user cancelled | Stop quietly |

- **Pass `signal`** (an `AbortSignal`) through long operations, and stop when it fires. Commands
  and pane actions receive one.

## 11. Performance checklist

- [ ] Activation under 100 ms on a typical laptop (the hard limit is 2 s).
- [ ] No `onStartup` activation, or a documented reason for it.
- [ ] Log subscriptions use a host-side filter, and per-batch work stays under 50 ms.
- [ ] No polling faster than every 2 s; subscriptions where they exist.
- [ ] No bodies, screenshots or files fetched until the user needs them.
- [ ] Bundle under 1 MB where possible. Tree-shake, and leave out locales you don't use.
- [ ] Memory steady after an hour of use with a busy log (check Settings → Plugins).

## 12. Security checklist

- [ ] Every permission is used, and its `reason` says what for.
- [ ] Every non-literal value in a shell script goes through `eagly.shell.quote()`.
- [ ] Destructive actions call `eagly.ui.confirm` and name the app and the device.
- [ ] Device text is shown as text, and never evaluated or used to build URLs to call.
- [ ] Secrets live in `ctx.secrets`, never in storage, settings, logs or exports.
- [ ] No serials or UDIDs on screen; `label` is used for display.
- [ ] `net:` hosts are exact. No `eval`, `Function` or remote code.
- [ ] Dependencies are pinned with a lockfile, audited, and few. Each one ends up in your bundle
      and in the reviewer's queue.
- [ ] The README lists the permissions and what leaves the machine, if anything.

## 13. Testing

- **Unit tests** run against `@eagly/plugin-testing`, a fake host with:
  - fake Android and iOS devices;
  - log fixtures (a saved Eagly log or logcat text) and HAR fixtures;
  - a switchboard to deny any permission.
- **Test the unhappy paths:**
  - every permission denied, one at a time;
  - an iOS device for an Android-only plugin;
  - a device that disconnects during a command;
  - `dropped` batches;
  - an empty log.
- **Then on real devices** in Developer mode: one Android phone and one iPhone, wired and over
  Wi-Fi if you can. Emulators hide timing problems.
- **Check both themes and two zoom levels** (⌘+ twice), and drag your pane narrow.
- **The registry runs `eagly-plugin validate`** and your tests (`npm test`) in CI. Make them pass
  locally first.

## 14. Versioning and compatibility

- **Check for optional APIs** with `eagly.api.has('network.subscribe')` instead of comparing
  Eagly versions. Additive APIs land without an `apiVersion` bump.
- **Proposed APIs** (`enabledApiProposals`) only work in Developer mode. Don't publish a plugin
  that depends on one.
- **Eagly supports the current `apiVersion` and the one before it.** When a new one is
  announced, release an update within that window.
- **Keep a CHANGELOG** whose first line for each version says whether permissions changed.

## 15. Publishing

1. **Public repo, with a licence** (MIT, Apache-2.0 or similar), README, screenshots of the pane
   in both themes, and the permission list with reasons.
2. **Build the release in CI** with `eagly-plugin build && eagly-plugin pack && eagly-plugin
   sign`, from a tag, with GitHub artifact attestations on. The registry rebuilds from your tag,
   and rejects an asset that doesn't match.
3. **Sign with your key** (`eagly-plugin keygen` once, kept out of the repo, in your CI's
   secrets). Losing the key means asking the registry to rotate it, so back it up.
4. **Open the registry PR** with `eagly-plugin publish`. The first version gets a human review.
   After that, only versions that add a High permission (`device-shell`, `apps:manage`,
   `network:secrets`, `device-files:write`, `apps:control`) do. All versions are scanned.
5. **Answer issues.** A plugin with security reports left unanswered for 30 days is unlisted;
   one confirmed malicious is revoked at once.

## 16. Anti-patterns

| Don't | Because | Instead |
|---|---|---|
| Ask for `device-shell` to run one fixed command | It is "can do anything adb can". Users decline, and reviewers slow down | A declarative `utilities` contribution |
| Activate on start-up "to be ready" | Every user pays the start-up cost on every launch | Activate on your command or pane |
| Subscribe to all logs and filter in JS | It hits limits, drops lines and burns CPU | A host-side `filter` |
| Poll `devices.list` every 500 ms | It competes with log streaming over the same connection | `devices.onDidChange` |
| Show serials, UDIDs or full tokens | They leak into recordings and bug reports | `label`, and redacted values |
| Build shell commands by concatenating strings | Quoting bugs at best, injection at worst | `eagly.shell.quote()` on every value |
| Keep state in module variables only | Lost on reload or idle unload | `ctx.storage`, or recompute |
| Show a message for every success | Noise, and it hits the rate limit | Update the pane |
| Copy Eagly's look with custom drawing | It drifts, breaks at other zoom levels and in dark mode | The components |
| Download and run code | Against policy; bypasses review | Ship it in the bundle |

## 17. For reviewers

What the registry checks, so authors can check it first:

- The manifest validates. Permissions are used and justified. Activation is narrow.
- The asset rebuilds byte-for-byte from the tagged source, and provenance matches the repo.
- The scanner finds no `eval`, `Function`, obfuscation, dynamic `import()` of non-bundled code,
  undeclared hosts, or Node built-ins.
- Shell scripts quote their inputs, and destructive actions confirm.
- The README explains permissions and data leaving the machine.
- The plugin works on the platforms it claims, with a short screen recording in the PR.
- The name doesn't impersonate Eagly or another plugin. The id isn't a squat.
