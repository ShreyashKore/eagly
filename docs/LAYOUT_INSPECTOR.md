# Layout Inspector

> **Status: phases 1 and 2 have landed on Android (§0).** This file describes what is built.
> Flutter, iOS, an Inspektor `layout` module, the rest of the UX sketch and the open points
> are in [plan/LAYOUT_INSPECTOR.md](../plan/LAYOUT_INSPECTOR.md). Written on 2026-10-25.
> Android numbers were measured on API 34 and API 36 emulators against the launcher and a React
> Native release build. Claims that were not confirmed on hardware are marked *unverified*.

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
- **Cheap win, independent of all of this:** a *Show layout bounds* toggle for Android in
  Utilities. Verified on the emulator (§2.5).

## 0. What is built (phases 1 and 2)

The **Layout** pane (`lib/features/layout_inspector/`, Android only) shows the
screen as a tree beside the screenshot it was read from. Hover the screenshot to outline the node
under the pointer, click to select it; the tree, the details panel and **Copy as** (resource id,
text, XPath, UiAutomator, Espresso, Compose `testTag`, Maestro) follow the selection. **Live**
recaptures when the UI reports a change; an endless animation, video or spinner reports none, so
Live doesn't follow it (see
[the plan](../plan/LAYOUT_INSPECTOR.md#8-open-points-where-to-pick-up)). **Show layout bounds**
is in Utilities → Screen & Input.

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

**Not done yet:** see [the plan](../plan/LAYOUT_INSPECTOR.md#8-open-points-where-to-pick-up).
Development is paused after phase 2; that list is the one to start from.

## 1. What already exists in Eagly

| Piece | Where | Relevance |
|---|---|---|
| Android mirror | `features/flutter_scrcpy/src/scrcpy_view.dart` | Normalized pointer mapping (`onTouch(action, nx, ny)`), an `overlay` slot at the picture's size wrapped in `IgnorePointer`, and the device aspect ratio. |
| iPhone mirror | `features/mirror/components/ios_mirror_surface.dart` | Uses the same `ScrcpyView`, so one overlay serves both platforms. |
| Bundled `adb` | `platform-tools/<os>/`, `AdbTool` | Every Android route below is an `adb shell` / `exec-out` call. |
| `scrcpy-server` push and `app_process` launch | `features/flutter_scrcpy/src/scrcpy_client.dart` | The same mechanism would run an inspector helper (§2.3). |
| Inspektor socket via `adb forward` / usbmux | `features/network/`, `rust/src/api/ios_network.rs` | The transport an SDK route would reuse ([plan §4](../plan/LAYOUT_INSPECTOR.md#4-ios)). |
| Log streams | `features/logs/` | Carry the Flutter VM service URL ([plan §3](../plan/LAYOUT_INSPECTOR.md#3-flutter-android-and-ios-debug-and-profile-builds)). |
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
([NETWORK_INSPECTOR_DROPPED_ROUTES.md](../plan/NETWORK_INSPECTOR_DROPPED_ROUTES.md)). Revisit only if
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

## 7. Phases

| Phase | Scope | Install | Effort (rough) |
|---|---|---|---|
| 1 | **Done (§0)**, except the overlay on the Mirror pane: §2.1 + §2.2 merge, pick on the screenshot, properties, copy selector. *Show layout bounds* in Utilities. | None | Medium |
| 2 | **Done (§0):** the §2.3 helper, live tree, all windows, no idle failures | A pushed dex (like scrcpy-server) | Medium |

Phases 3 (Flutter) and 4 (iOS, an Inspektor module) are in
[the plan](../plan/LAYOUT_INSPECTOR.md#7-phases).
