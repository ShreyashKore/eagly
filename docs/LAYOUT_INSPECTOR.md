# Layout Inspector

> **Status: phases 1 and 2 have landed on Android (§0); phases 3–4 are still plans.** Written on
> 2026-10-25. Android numbers were measured on API 34 and API 36 emulators against the launcher
> and a React Native release build. iOS was only probed on an iPhone 16 running iOS 27. Claims
> that were not confirmed on hardware are marked *unverified*.

**Goal.** Point at something on the mirrored screen and see what it is: its place in the UI tree,
its class, id, text, bounds and state. Then copy a selector for it. The model is
`uiautomatorviewer` and Appium Inspector, built into the mirror pane Eagly already has, rather than
a full clone of Android Studio's Layout Inspector or Flutter DevTools.

## TL;DR

- **Android works today with nothing installed, in any app, debuggable or not.** Two dumps
  complement each other:
  - `uiautomator dump` gives the accessibility tree. It has text, content descriptions, React
    Native `testID`s, Compose semantics and absolute bounds. It takes **~2.2 s**.
  - `dumpsys activity top` gives the real `View` tree. It has class names, resource ids,
    visibility flags and parent-relative bounds, but no text. It takes **~0.13 s**.
- **The mirror is already shaped for an overlay.** `ScrcpyView` maps pointers to a normalized 0..1
  rect and takes an `overlay` widget at the picture's size. An element's bounds divided by the
  screen size draw straight onto it, and a pick mode only has to swap `onTouch`.
- **iOS has no route that needs nothing installed.** The full tree with frames comes from
  XCTest, through WebDriverAgent (WDA). The `idevice` crate can launch and drive WDA from 0.1.68
  (Eagly pins 0.1.65, and a bump is in progress on `feat/idevice-0.1.68`). The user must still
  build WDA and sign it with their own team. Apple's accessibility-audit service needs no
  install, but it carries no frames and no hierarchy.
- **For your own apps, an in-process SDK beats every external route**, and Inspektor already has
  the socket. A `layout.*` method set is an additive protocol change. It would give UIKit and
  Compose trees with real names, and would work in UAT builds. Whether a network library should
  grow a layout module is the user's call (§5).
- **Flutter debug and profile builds** can use the Dart VM service's `ext.flutter.inspector.*`
  extensions. Eagly already streams the log line that announces the VM service URL.
- **Cheap win, independent of all of this:** a *Show layout bounds* toggle for Android in
  Utilities. Verified on the emulator (§2.5).

**Recommended order:** (1) an Android snapshot inspector over the mirror, plus the layout-bounds
toggle; (2) a long-lived on-device helper for live refresh; (3) Flutter through the VM service;
(4) iOS, through user-supplied WDA or an Inspektor module.

## 0. What is built (phases 1 and 2)

The **Layout** pane (`lib/features/layout_inspector/`, Android only) shows the
screen as a tree beside the screenshot it was read from. Hover the screenshot to outline the node
under the pointer, click to select it; the tree, the details panel and **Copy as** (resource id,
text, XPath, UiAutomator, Espresso, Compose `testTag`, Maestro) follow the selection. **Live**
recaptures whenever the UI changes. **Show layout bounds** is in Utilities → Screen & Input.

| Piece | Where |
|---|---|
| The helper (Java, run with `app_process`) | `inspector_helper/src/dev/eagly/inspector/`, built by `scripts/build_inspector_helper.sh` into the committed asset `assets/inspector/eagly-inspector.jar` (~8 KB) |
| Its Dart client | `services/inspector_helper.dart` (`InspectorHelper`) |
| adb calls | `AdbTool.dumpUiHierarchy` / `dumpTopActivity` / `pushFile` / `startAppProcess`; `DeviceSessionRepository.captureLayoutWithUiAutomator` / `dumpViewHierarchy` / `startInspectorHelper` |
| Model and parsers | `data/layout_snapshot.dart`, `data/layout_parsers.dart` (uiautomator XML, helper JSON), `data/view_hierarchy.dart` (`dumpsys activity top` and the join), `data/layout_selectors.dart` |
| Controller and view | `layout_inspector_controller.dart`, `layout_inspector_feature_view.dart`, `components/` |

**How a capture runs.** `LayoutInspectorController.capture()` uses the helper when it starts
(~0.2 s with a screenshot, every window) and `uiautomator dump` + `screencap` when it can't
(~2–3 s, the active window), saying so in a notice. Either way `dumpsys activity top` runs
alongside and `ViewHierarchy.annotate` joins the real View classes in (§2.2). Captures never
overlap: one asked for while another runs is folded into a single follow-up.

**The helper's protocol** is JSON lines over the `adb shell` process's stdin/stdout. It says
`{"event":"hello","protocol":1,"sdk":36}` once it can see windows, answers
`{"id","method":"snapshot"|"watch"|"ping","params"}` with `{"id","result"}` or `{"id","error"}`,
and while watching sends `{"event":"changed"}`, coalesced over 120 ms of quiet. Closing stdin ends
it. A failed connect is `{"event":"error","code":"busy"|"connect","message"}`.

**Rules most easily broken:**

- **Android allows one UI Automation connection at a time.** While the helper runs, `uiautomator
  dump`, a UI test, Appium and Maestro are refused (they get `Killed`), and the other way round
  (`busy`). So the controller keeps the helper only while **Live** is on and for
  `helperLinger` (20 s) after a capture, and lets it go at once when the pane closes or the
  device drops. A `busy` failure is an error, not a fallback: `uiautomator` would be refused too.
- **Prepare the main looper.** On Android 16 the accessibility client posts to the main looper,
  which a bare `app_process` lacks; without `Looper.prepareMainLooper()` it crashes on connect.
  The main thread runs that looper and stdin is read on its own thread.
- **Report connect failures yourself.** An uncaught exception in an `app_process` program goes to
  logcat, not stderr, and the process is killed: the host only sees `Killed`. `Main.fail`
  prints the `error` event first.
- **Wait for windows before hello.** Right after `setServiceInfo` the window list is empty for a
  moment; `awaitWindows` waits up to 2 s.
- **No lambdas in the helper.** `android.jar` has no `LambdaMetafactory` to compile against.
- The jar is committed so building Eagly needs no Android SDK. Rebuild it with the script after
  changing the Java, and commit both.

**Tests:** `test/layout_inspector_data_test.dart` (parsers, hit testing, the join, selectors),
`test/inspector_helper_test.dart` (protocol), `test/layout_inspector_controller_test.dart`
(routes, the helper's lifetime, live, selection), `test/layout_inspector_feature_view_test.dart`.
Against a device: `EAGLY_TEST_ANDROID_SERIAL=<serial> fvm flutter test
test/device/layout_inspector_device_test.dart` (passes on API 30 and 36; swipes the home screen once).

**Not done yet:** see [§8](#8-open-points-where-to-pick-up). Development is paused after
phase 2; §8 is the list to start from.

## 1. What already exists in Eagly

| Piece | Where | Relevance |
|---|---|---|
| Android mirror | `features/flutter_scrcpy/src/scrcpy_view.dart` | Normalized pointer mapping (`onTouch(action, nx, ny)`), an `overlay` slot at the picture's size wrapped in `IgnorePointer`, and the device aspect ratio. |
| iPhone mirror | `features/mirror/components/ios_mirror_surface.dart` | Uses the same `ScrcpyView`, so one overlay serves both platforms. |
| Bundled `adb` | `platform-tools/<os>/`, `AdbTool` | Every Android route below is an `adb shell` / `exec-out` call. |
| `scrcpy-server` push and `app_process` launch | `features/flutter_scrcpy/src/scrcpy_client.dart` | The same mechanism would run an inspector helper (§2.3). |
| Inspektor socket via `adb forward` / usbmux | `features/network/`, `rust/src/api/ios_network.rs` | The transport an SDK route would reuse (§4). |
| Log streams | `features/logs/` | Carry the Flutter VM service URL (§3). |
| Utilities catalog | `features/utilities/data/utility_catalog.dart` | Has `show_touches` already; layout bounds would sit next to it. |

## 2. Android

### 2.1 `uiautomator dump`: the accessibility tree

```bash
adb exec-out uiautomator dump /dev/tty      # XML on stdout, no temp file
```

- **Works in any app**, the launcher included. It needs no debuggable build and no install.
- **Returns per node:** `class`, `package`, `resource-id`, `text`, `content-desc`, the
  checkable/checked/clickable/enabled/focusable/focused/scrollable/long-clickable/password/selected
  flags, and **absolute** `bounds="[l,t][r,b]"` in device pixels. The root carries
  `rotation`.
- **Sees through frameworks.** A React Native release build exposed its `testID`s as
  `resource-id` (`noInternetRetryButton`) and its strings as `text`. Compose nodes appear from the
  semantics tree, with `testTag` as `resource-id` when the app sets `testTagsAsResourceId`.
- **Measured cost (×2 runs): 2.0–2.5 s.** About 1.1 s of that is starting the `uiautomator`
  JVM: `adb shell uiautomator` with no arguments takes 1.12 s. The rest is waiting for idle and
  walking the tree. `--compressed` made no difference (2.21 s).
- **Known failure:** on a screen that never goes idle, such as an endless animation or a video,
  it fails with `ERROR: could not get idle state`. *Not reproduced here*; it is widely reported.
- It sees only what accessibility sees. Views marked `importantForAccessibility=no` and purely
  decorative children are missing, and custom-drawn widgets appear as one node.

### 2.2 `dumpsys activity top`: the View tree

```bash
adb exec-out dumpsys activity top
```

- **Works in any app.** It ran against the launcher and against a release (non-debuggable)
  build. The dump comes from the app's own `Activity.dump()`.
- **Measured cost: 0.11–0.13 s**, about 17× faster than `uiautomator`.
- **Each line is `View.toString()`:**
  `android.widget.FrameLayout{76e6 V.E...... ........ 0,0-1080,2280 #1020002 android:id/content aid=1073741826}`.
  That holds the class, the visibility (`V`/`I`/`G`), the
  focusable/enabled/draws/scrollbars/clickable flags, the pressed/selected/dirty state, the bounds
  **relative to the parent**, the resource id and the *autofill* id (`aid=`; it is not the
  accessibility id, so it can't join the two trees).
- **Limits:**
  - **No text.** Merge with §2.1 for that.
  - **Compose is one node.** The whole Compose UI shows as a single `AndroidComposeView`.
  - **Release builds are obfuscated by R8.** The React Native build showed
    `com.facebook.react.views.text.j`, and its view ids are React tags (`#26`), not resource
    names.
  - **Positions are `mLeft…mBottom` only.** Scroll offsets and translations aren't printed, so
    absolute positions built from them drift inside scrolled or animated containers
    (*inferred from the format*; not measured).
  - **It dumps the top activity of every visible task.** The capture held both the launcher and
    the app. Each section's `Local Activity` state says `mResumed=true` for the one in front;
    `ViewHierarchy.parse` picks that one.
- **Merging with §2.1:** accumulate parent-relative bounds into absolute ones, then pair nodes
  by equal bounds in depth-first order, each View used once, refusing a pair whose resource ids
  disagree. There is no shared id: the helper can read a node's hidden source id, but `View`
  doesn't print its accessibility id. On the launcher 45 of 52 app nodes paired, all correctly
  (`GridView` → `AllAppsRecyclerView`, `TextView` → `BubbleTextView`).

### 2.3 A long-lived helper on the device (`app_process` + `UiAutomation`)

`uiautomator` is a script that runs `app_process` as the shell user, connects a `UiAutomation`
and dumps once. The 1.1 s of JVM start is paid on every snapshot. Eagly already pushes a jar and
runs it the same way for scrcpy, so a small `eagly-inspector` dex could:

- keep one `UiAutomation` connection open, removing the startup cost;
- skip or bound the idle wait, fixing the endless-animation failure;
- listen for `TYPE_WINDOW_CONTENT_CHANGED` / `TYPE_WINDOWS_CHANGED` and push trees as they change,
  which makes the inspector live instead of snapshot-and-refresh;
- walk every window (`getWindows()`): dialogs, the IME and system bars, not just the active one.

**Built and measured (§0).** `UiAutomation(Looper, IUiAutomationConnection)` still exists on API
36 (it logs "deprecated constructor"); a `Context` constructor is the fallback, untried. Starting
takes 0.2–0.3 s. Warm, the tree walk takes 1–6 ms and a snapshot with a full-size JPEG screenshot
~0.1–0.25 s, against 2.2 s for `uiautomator dump` plus 0.9 s for `screencap`. It sees more, too:
74 nodes over two windows on the API 34 launcher, where `uiautomator` saw 31.

### 2.4 Android Studio's Layout Inspector: dropped

Studio attaches a JVMTI agent (`cmd activity attach-agent`) and reads skia/compose data out of
the process. It works only for debuggable apps and is versioned with Studio. A port is the same
trade that was declined for the network inspector
([NETWORK_INSPECTOR_DROPPED_ROUTES.md](NETWORK_INSPECTOR_DROPPED_ROUTES.md)). Revisit only if
Compose recomposition counts become a goal.

### 2.5 Show layout bounds: verified

```bash
adb shell 'setprop debug.layout true; service call activity 1599295570'   # on
adb shell 'setprop debug.layout false; service call activity 1599295570'  # off
```

`1599295570` is `SYSPROPS_TRANSACTION`. It makes running apps re-read system properties, so the
change shows without restarting them. The call replies `Parcel(Error: … "Not a data message")`,
but the poke still takes effect: on the emulator the bounds were drawn over the whole screen,
and turning it off restored the screen. It is a one-entry addition to the Utilities catalog, and
it lights up in the mirror at once.

## 3. Flutter (Android and iOS), debug and profile builds

- **Discovery:** a Flutter app logs `The Dart VM service is listening on http://127.0.0.1:<port>/<token>=/`.
  Eagly already parses both platforms' logs. Forward the port with `adb forward` or usbmux (the
  same code as `ios_network.rs`), then connect with the `vm_service` package.
- **Tree:** `ext.flutter.inspector.getRootWidgetTree` (`groupName`, `isSummaryTree`,
  `withPreviews`, `fullDetails`) returns the widget tree with creation locations (file and line).
  `getLayoutExplorerNode` returns size, constraints and the parent offset.
- **Geometry gap:** no extension returns screen-absolute bounds. The options:
  - accumulate `BoxParentData` offsets, which is fragile under transforms; or
  - let the device draw the highlight. `setSelectionById` and `show` turn on the on-device
    inspector, and selecting on the device posts a `navigate` event on the `ToolEvent` stream
    plus `developer.inspect()`.
- **Extras:** the same connection gives `ext.flutter.debugPaint` (Flutter's layout bounds),
  `ext.flutter.showPerformanceOverlay`, and `inspector.screenshot` for a widget.
- **Why bother when DevTools exists:** Eagly finds the VM service from the log on its own, with no
  IDE and no `flutter attach`. It also shows the result next to the mirror and logs. Release
  builds have no VM service, so they need the SDK route (§5).

## 4. iOS

| Route | Install needed | What you get | Verdict |
|---|---|---|---|
| **XCTest / WDA** through the `idevice` crate's `xctest` + `wda` features (0.1.68) | WDA built and signed by the user's team. A free Apple ID works but expires every 7 days. | The whole XCUI tree for any app: type, identifier, label, value, frame. Also tap and type. | **The only full no-SDK route.** It needs a "bring your own WDA" setup. Snapshots of complex screens are slow (seconds, *unverified* here). |
| **Accessibility audit daemon** (`com.apple.accessibility.axAuditDaemon.remoteserver`, DTX) | Nothing | It walks focusable elements one at a time, VoiceOver-style, returning caption and spoken description. Frames come only on audit *issues*. | **Not a layout source.** It is a good base for a separate *accessibility audit* feature. It isn't in the `idevice` crate; pymobiledevice3's `accessibilityaudit.py` is the reference. |
| **Xcode's view debugger** (lldb + debugserver, loading `libViewDebuggerSupport`) | Dev-signed, debuggable app | UIKit and SwiftUI layers in 3D | **Dropped.** It needs an lldb and debugserver stack Eagly doesn't have. |
| **Inspektor module** (§5) | The SDK in the app | Real UIKit classes and frames, no obfuscation | **Best for your own apps.** |

Notes:

- No WDA was installed on the test iPhone, so nothing in the WDA row was run.
- A tunnel on iOS 17+ is needed for testmanagerd. Eagly already builds the CoreDevice tunnel for
  the mirror (`rust/src/api/ios_mirror.rs`).

## 5. In-process SDK: an Inspektor `layout` module

The socket, discovery and transport are already done for the network inspector. Inspektor's
protocol grows additively: new methods and events keep `protocol: 1`, and clients ignore what they
don't know. A layout module would add:

| Method / event | Purpose |
|---|---|
| `hello.sdk.layout: true` | The capability flag. |
| `layout.snapshot` → `{root, screen: {width, height, scale, rotation}}` | Tree nodes: `id`, `type`, `name` / `identifier`, `text`, `frame` in screen pixels, `visible`, `alpha`, `children`, and a `props` bag per framework. |
| `layout.highlight {id}` | Optionally draw on the device, for builds without a mirror. |
| `layout.changed` event | Optional live mode, throttled. |

Per runtime:

- **Android Views:** walk `WindowManagerGlobal`'s roots, or the activity's `decorView`. Use
  `getLocationOnScreen` for frames, so scroll and translation come out right (unlike §2.2).
- **Compose:** read the `SemanticsOwner` from each `AndroidComposeView`. This is the same data
  `uiautomator` sees, plus unmerged nodes. Composable *names* need `androidx.compose.ui.tooling`
  data, which debug builds keep and release builds don't.
- **UIKit:** walk `UIWindowScene` windows. Take `convert(bounds, to: nil)` × `screen.scale`, plus
  `accessibilityIdentifier`, the class name and `isHidden`/`alpha`. Kotlin/Native can do this
  through the existing `inspektor-urlsession`-style interop.
- **Flutter (Dart client):** walk the render tree from `RendererBinding`.
  `localToGlobal` gives real screen frames in every build mode. Widget names come out minified
  only with `--obfuscate`.

The trade-off is scope: Inspektor is a network library, and this makes it a general debug
bridge. That decision belongs to the user, not this doc.

## 6. Eagly UX sketch

- **An Inspector pane** (a `FeatureController` + `FeatureView`, like every other pane) with the tree
  on the left and properties on the right. It docks next to the Mirror pane in the workspace
  layout.
- **Overlay on the mirror** through `ScrcpyView.overlay`. The normalized rect is
  `bounds / screenSize`; scrcpy's downscaling doesn't matter because both sides are normalized.
  Rotation comes from the dump's `rotation`.
- **Pick mode:** a toggle that routes the mirror's clicks to hit-testing (smallest node containing
  the point) instead of `onTouch`. Hover highlights, and click selects and reveals the node in the
  tree.
- **Snapshot coherence:** a dump arriving while the screen moves draws misplaced boxes. Freeze the
  mirror frame that was showing when the dump started, and show *Snapshot · 2.2 s ago* with a
  refresh button until §2.3 makes it live.
- **Copy as:** `resource-id`, text, an XPath, and a Maestro / Espresso / UiAutomator selector. For
  QA this is the feature's most-used button.
- **Search the tree** with the shared `FindBar`.
- **Later:** expose `layout.snapshot` through the MCP server plan (branch `docs/mcp-server-plan`) so an
  agent can read the screen as structure, not pixels.

## 7. Phases

| Phase | Scope | Install | Effort (rough) |
|---|---|---|---|
| 1 | **Done (§0)**, except the overlay on the Mirror pane: §2.1 + §2.2 merge, pick on the screenshot, properties, copy selector. *Show layout bounds* in Utilities. | None | Medium |
| 2 | **Done (§0):** the §2.3 helper, live tree, all windows, no idle failures | A pushed dex (like scrcpy-server) | Medium |
| 3 | Flutter VM service: tree, on-device highlight, `debugPaint` toggle | None (debug/profile) | Medium |
| 4a | iOS through user-supplied WDA (after the 0.1.68 bump) | WDA, signed by the user | Medium–large |
| 4b | Inspektor `layout` module (Android, iOS, Flutter) | The SDK | Large, across two repos |

## 8. Open points: where to pick up

Phases 1 and 2 landed on 2026-10-25 and work stopped there by choice. In rough priority order:

**Not yet checked**

- **Hands-on in the app.** The pane was checked through widget-test renders of real captures
  (Settings on API 36, dark, light and 480 px wide) and the device test, not by clicking through
  the running macOS app. Watch for: the first capture when the pane opens, Live on a busy screen,
  and closing the pane mid-capture.
- **Windows and Linux hosts.** The helper is stopped by closing the `adb shell` process's stdin,
  which reaches the device over adb's shell protocol on macOS. If Windows' adb doesn't pass EOF
  through, `InspectorHelper.close` kills the local adb after 1 s; whether the device-side process
  then exits, so UI Automation is free again, is *unverified*. Check with
  `adb shell ps -A | grep app_process` after closing the pane.
- **Physical phones and OEM builds.** Only Google emulators (API 30, 34, 36) were tried. OEM
  skins sometimes restrict `app_process` or hidden APIs.
- **API 34 through Eagly.** API 34 ran the prototype helper, not the device test.
- **Landscape.** Rotation is read and the screenshot is in the current orientation, so it should
  line up, but no capture was made in landscape.
- **`UiAutomation(Context, …)`**, the fallback for a platform that drops the `Looper`
  constructor (`Automation.connect`), has never run. API 36 still has the `Looper` one.

**Known limits, by design for now**

- **Live goes quiet on a screen that never settles.** The helper sends `changed` after 120 ms
  without UI events, so an endless animation, video or progress spinner sends none and the tree
  stops following. A max-wait in `Main.onEvent` (send at least every ~500 ms while changes keep
  coming) would fix it; keep captures from overlapping, which the controller already does.
- **Every live capture carries a full-size JPEG** (~60–140 KB) and runs `dumpsys activity top`.
  Fine on USB; over Wi-Fi adb, consider the helper's `scale` param, or skipping `dumpsys` on live
  captures.
- **The View join is a heuristic** (§2.2). Inside scrolled containers `dumpsys` bounds drift, so
  those nodes go unpaired and show only the accessibility class. They are never paired wrongly
  on purpose: conflicting ids are refused.
- **The `uiautomator` fallback sticks** for the rest of the connection once the helper fails for
  a reason other than `busy`; reconnecting the device resets it.
- **Compose** nodes have an id only when the app sets `testTagsAsResourceId`; a bare id is
  offered as both a Compose `testTag` and a React Native `testID` selector, since the two can't
  be told apart.
- **System windows have no titles** on the emulators tried (the status bar shows as `system`).

**Next: the plan, in order** (agreed 2026-10-25)

1. **Hands-on test.** Use the pane in the running app and fix whatever turns up first.
2. **Hardening, about one session.**
   - Live max-wait in `Main.onEvent`: send `changed` at least every ~500 ms while UI events keep
     coming, so spinners, video and endless animations are followed. Rebuild the jar, and add a
     device test on an animating screen.
   - Windows and Linux hosts: confirm that closing the pane stops the device-side helper (see
     above). If it doesn't, add a device-side fallback, such as `pkill -f
     dev.eagly.inspector.Main` before a start and after a close. A leftover helper holds UI
     Automation and breaks Appium, Maestro and UI tests, so this is the riskiest open point.
   - Run the device test once on a physical phone (ideally an OEM build such as Samsung or
     Xiaomi) and once in landscape.
3. **Polish, 1–2 sessions.**
   - Draw the selection over the Mirror pane through `ScrcpyView.overlay` (normalized
     `bounds / displaySize`), with a pick mode there. The pane's own screenshot stays the source
     of truth: it is what keeps boxes and picture in step.
   - Resizable splits between screenshot, tree and details (they are fixed fractions).
   - Keyboard navigation in the tree (↑/↓/←/→), and a right-click menu: expand or collapse the
     subtree (`setSubtreeCollapsed` is there, unused), Copy as.
   - Lighter Live captures: the helper's `scale`/`quality` params, and `dumpsys` only on manual
     captures or every few live ones. This matters over Wi-Fi adb.
4. **New platforms.**
   - Phase 3, Flutter debug/profile builds through the VM service (§3), on both platforms. The
     VM service URL is already in the log stream. Medium size; its own project.
   - Phase 4, iOS (§4, §5): blocked on the open questions below.

## Open questions for the user

1. iOS: is "bring your own signed WDA" acceptable UX, or should iOS wait for the Inspektor route?
2. Should Inspektor grow a `layout` module at all (§5)?
