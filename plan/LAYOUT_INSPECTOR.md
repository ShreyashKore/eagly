# Layout Inspector: plan

> **Status: not built.** Phases 1 and 2 (Android) have landed and are described in
> [docs/LAYOUT_INSPECTOR.md](../docs/LAYOUT_INSPECTOR.md), with the Android research (§2) they
> rest on. This file holds Flutter, iOS, an Inspektor `layout` module, the UX sketch, phases 3
> and 4 and the open points. Section numbers follow the docs file, so §0 to §2 references
> point there. iOS was only probed on an iPhone 16 running iOS 27. Claims that were not
> confirmed on hardware are marked *unverified*.

## Summary

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

**Recommended order:** (1) an Android snapshot inspector over the mirror, plus the layout-bounds
toggle (built as its own Layout pane, with the toggle in Utilities; the overlay on the mirror is
still to do);
(2) a long-lived on-device helper for live refresh (built); (3) Flutter through the VM service;
(4) iOS, through user-supplied WDA or an Inspektor module.

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
| 1 (rest) | The overlay on the Mirror pane, with a pick mode there (§8, *Polish*) | None | – |
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
