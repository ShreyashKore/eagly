# Sentry triage (2026-10-25)

A snapshot of the [`gyanoba/flutter`](https://gyanoba.sentry.io/issues/?project=flutter&query=is%3Aunresolved)
project, to work through once the current feature lands. 68 unresolved issues over 90 days
collapse into about 15 real problems; most of the rest are the same bug grouped apart by a
different render object id or stack shape. Open the linked issue for stacks and events.

Delete a row (or the section) in the commit that fixes it, as with `KNOWN_ISSUES.md`.

## Priority 1: App hangs (macOS main thread blocked ≥ 2 s)

| Group | Issues | Events | Users | Env | Read |
| --- | --- | ---: | ---: | --- | --- |
| **H1** Release hang in Dart code on the main thread | [FLUTTER-5V](https://gyanoba.sentry.io/issues/FLUTTER-5V) (main) | 4233 | 10 | production | The one that matters. See below. |
| **H2** Debug-build hang in the Dart JIT | [FLUTTER-2](https://gyanoba.sentry.io/issues/FLUTTER-2) | 918 | 1 | debug | Noise: the stack is `DRT_TypeCheck` → `TypeTestingStubGenerator`, i.e. the debug VM compiling a type test during a pointer event. A developer machine. |
| Long tail, probably H1 split by a different top frame | [FLUTTER-66](https://gyanoba.sentry.io/issues/FLUTTER-66), [-8](https://gyanoba.sentry.io/issues/FLUTTER-8), [-6N](https://gyanoba.sentry.io/issues/FLUTTER-6N), [-63](https://gyanoba.sentry.io/issues/FLUTTER-63), [-9](https://gyanoba.sentry.io/issues/FLUTTER-9), [-6P](https://gyanoba.sentry.io/issues/FLUTTER-6P), [-6A](https://gyanoba.sentry.io/issues/FLUTTER-6A), [-7A](https://gyanoba.sentry.io/issues/FLUTTER-7A), [-76](https://gyanoba.sentry.io/issues/FLUTTER-76), [-6X](https://gyanoba.sentry.io/issues/FLUTTER-6X), [-6T](https://gyanoba.sentry.io/issues/FLUTTER-6T), [-6S](https://gyanoba.sentry.io/issues/FLUTTER-6S), [-6H](https://gyanoba.sentry.io/issues/FLUTTER-6H), [-6B](https://gyanoba.sentry.io/issues/FLUTTER-6B) | ~140 | — | mixed | Not opened. Re-check after H1's symbols are fixed; they should regroup. |
| Window manager call on the main thread | [FLUTTER-5D](https://gyanoba.sentry.io/issues/FLUTTER-5D) | 2 | 1 | — | Culprit `WindowManager.unmaximize`. Low volume. |

### H1: what the stack says (and doesn't)

From the latest event (1.6.0+53, macOS 26.6, Mac14,7):

- Main thread: `NSApplication run` → `FlutterRunLoop.perform` → engine frames → a run of
  `<redacted>` frames. The engine frames are symbolised as
  `InternalFlutterGpu_Texture_InitializeFromImage` / `TraceScope`; that is the nearest
  exported symbol in `FlutterMacOS`, not a real texture upload.
- There is **no `io.flutter.ui` thread**: the Flutter build runs Dart on the platform (main)
  thread. So any long synchronous Dart work (building a big list, parsing, sorting, sync
  file I/O, a synchronous FFI call into Rust) is reported as an app hang.
- `app_memory` was ~805 MB with 75 MB free on a 16 GB machine, so GC pressure from large
  in-memory log/network buffers is a suspect.
- The bottom frames are unsymbolised, so the actual Dart function is unknown.

### H1: next steps

1. **Get symbols.** The cause: nothing ever ran `sentry_dart_plugin`, so Sentry has no
   dSYMs or PDBs for any release, and the hang's Dart AOT frames come through as
   `<redacted>`. The release workflow now runs it after packaging (*Upload debug symbols to
   Sentry*). The `SENTRY_AUTH_TOKEN` repository secret was added on
   2026-10-25. **Left to do:** after the next tagged release, confirm the files in Sentry under *Settings → Debug Files*, then
   reopen the newest FLUTTER-5V event. Releases up to 1.6.1 stay unsymbolised.
2. ~~**Stop debug builds reporting.**~~ Done: `lib/main.dart` now starts Sentry only in
   release builds, and tracing, profiling, logs and replay are off. That removes H2 and
   most of the layout noise below.
3. With symbols in hand, take the top Dart frame across H1 events (`search_issue_events`
   on FLUTTER-5V, grouped by top in-app frame) and fix the busiest path: move it off the
   main isolate (`Isolate.run` / Rust async) or chunk it across frames.

## Priority 2: Real crashes and errors (production code paths)

| Group | Issues | Events | Users | Where | Notes |
| --- | --- | ---: | ---: | --- | --- |
| **C1** `super_sliver_list` index out of range | [FLUTTER-12](https://gyanoba.sentry.io/issues/FLUTTER-12), [FLUTTER-15](https://gyanoba.sentry.io/issues/FLUTTER-15) | 18 | 6 | `RenderSuperSliverList.getOffsetToReveal`, `ExtentList.[]` | **Fixed on `fix/sentry-setup`.** `_LogViewerState.didUpdateWidget` → `_scrollToMatch` called `animateToItem` before the new logs were laid out, so the list still held the old count (64 rows, index 76). It now waits a frame and drops the scroll if the index still isn't there. |
| **C2** Log viewer measures a row before layout | [FLUTTER-24](https://gyanoba.sentry.io/issues/FLUTTER-24), [FLUTTER-5H](https://gyanoba.sentry.io/issues/FLUTTER-5H) | 33 | 3 | `log_viewer.dart` `_LogViewerState._measureRowRect` | **Already fixed** in 213e7b0 (v1.5.4, a `hasSize` guard). Close once no event arrives from 1.5.4 or later. |
| **C3** Selection null-check in `SelectableRegion` | [FLUTTER-E](https://gyanoba.sentry.io/issues/FLUTTER-E), [-53](https://gyanoba.sentry.io/issues/FLUTTER-53), [-5Q](https://gyanoba.sentry.io/issues/FLUTTER-5Q), [-4A](https://gyanoba.sentry.io/issues/FLUTTER-4A), [-6](https://gyanoba.sentry.io/issues/FLUTTER-6) | 10 | ~3 | `selectable_region.dart` | Flutter framework bug, same family as C4 and L3: the `SelectionArea` around the lazily built log list (`log_viewer.dart`) sorts and clears selectables while rows are built, disposed or not yet laid out. No in-app frame, so no safe local fix without running the app; re-check after a Flutter upgrade, or give each row its own selection container. Seer rates FLUTTER-E "high" actionability. |
| **C4** Concurrent modification of a list | [FLUTTER-25](https://gyanoba.sentry.io/issues/FLUTTER-25), [-75](https://gyanoba.sentry.io/issues/FLUTTER-75), [-3T](https://gyanoba.sentry.io/issues/FLUTTER-3T), [-18](https://gyanoba.sentry.io/issues/FLUTTER-18) | 5 | 1 | `ListIterator.moveNext` | Same framework bug as C3: `SelectableRegionState.clearSelection` → `handleClearSelection` iterates selectables that change underneath it. No in-app frame. Fix with C3. |
| **C5** Native crashes (macOS) | [FLUTTER-74](https://gyanoba.sentry.io/issues/FLUTTER-74), [-5Y](https://gyanoba.sentry.io/issues/FLUTTER-5Y), [-1C](https://gyanoba.sentry.io/issues/FLUTTER-1C) | 5 | ~3 | `impeller::Canvas::SetupRenderPass`, `main` | FLUTTER-74 is the Impeller bug already in `KNOWN_ISSUES.md`. FLUTTER-5Y and -1C crash in `main` with no usable frames; wait for symbols from the next release. |
| **C6** Native crashes (Windows) | [FLUTTER-79](https://gyanoba.sentry.io/issues/FLUTTER-79), [-77](https://gyanoba.sentry.io/issues/FLUTTER-77), [-4W](https://gyanoba.sentry.io/issues/FLUTTER-4W) | 3 | 1 each | `CFileOpenSave`, heap, SRW lock | No in-app frames (file dialog teardown, heap, lock). One event each; wait for PDBs from the next release. |
| **C7** File manager filter returns null | [FLUTTER-7C](https://gyanoba.sentry.io/issues/FLUTTER-7C) | 1 | 1 | `FileManagerController.filterText` | **Not a bug:** a `String` field initialised to `''` can only read as `null` after a hot reload adds the field to a live object. One developer, debug build. |
| **C8** iOS errors surfaced as unhandled | [FLUTTER-6W](https://gyanoba.sentry.io/issues/FLUTTER-6W), [-6J](https://gyanoba.sentry.io/issues/FLUTTER-6J), [-70](https://gyanoba.sentry.io/issues/FLUTTER-70), [-78](https://gyanoba.sentry.io/issues/FLUTTER-78) | 16 | ~3 | Rust `IosError` via FRB | No in-app frame: the error comes back through FRB's async decoder, so the caller is lost. Checked: `interfaceOrientation`, `canControlApps`, the Inspektor port probe and tunnel, and the syslog and input sessions all catch or don't return this error. Next step: read the breadcrumbs on a FLUTTER-6W event in Sentry to find the action just before it. |
| **C9** Environment / OS errors | [FLUTTER-M](https://gyanoba.sentry.io/issues/FLUTTER-M), [-5K](https://gyanoba.sentry.io/issues/FLUTTER-5K), [-4Q](https://gyanoba.sentry.io/issues/FLUTTER-4Q), [-6V](https://gyanoba.sentry.io/issues/FLUTTER-6V), [-17](https://gyanoba.sentry.io/issues/FLUTTER-17) | 22 | ~5 | socket reset, clipboard busy (Windows), file picker, Google Fonts fetch | **Fixed on `fix/sentry-setup`:** Android mirror clipboard reads and writes catch the Windows "Unable to open clipboard" error (FLUTTER-5K, -4Q); the capture-folder and Android SDK pickers skip a folder that no longer exists (FLUTTER-6V); the scrcpy control socket observes its `done` future, the likely source of the unhandled "Connection reset by peer" (FLUTTER-M). **Left:** bundle the fonts instead of fetching them (FLUTTER-17): Inter 400/500/600/700 and JetBrains Mono 400 add about 1.4 MB to the app, about 0.7 MB compressed in the installer. |

## Priority 3: Layout / framework assertions (later)

L1, L2 and L4 are `assert`s, which only fire in debug builds, so they came from developer
machines. Gating Sentry on release (H1 step 2) clears them from the dashboard. L3 turned
out to be the selection bug (C3), which also hits release builds.

| Group | Issues | Events | Notes |
| --- | --- | ---: | --- |
| **L1** `ListTile` with no `Material` ancestor | [FLUTTER-6Z](https://gyanoba.sentry.io/issues/FLUTTER-6Z), [-7F](https://gyanoba.sentry.io/issues/FLUTTER-7F), [-60](https://gyanoba.sentry.io/issues/FLUTTER-60), [-62](https://gyanoba.sentry.io/issues/FLUTTER-62), [-7G](https://gyanoba.sentry.io/issues/FLUTTER-7G), [-6Y](https://gyanoba.sentry.io/issues/FLUTTER-6Y), [-72](https://gyanoba.sentry.io/issues/FLUTTER-72), [-7E](https://gyanoba.sentry.io/issues/FLUTTER-7E), [-71](https://gyanoba.sentry.io/issues/FLUTTER-71), [-7D](https://gyanoba.sentry.io/issues/FLUTTER-7D), [-7B](https://gyanoba.sentry.io/issues/FLUTTER-7B) | ~800 | **Fixed on `fix/sentry-setup`.** The event names `ListTile(dense: true, onTap: …)` over a `ColoredBox`, which matches the crash report list; it now builds on a transparent `Material`. All 11 issues are that one tile, split by stack. |
| **L2** Scrollbar controller not attached | [FLUTTER-4Z](https://gyanoba.sentry.io/issues/FLUTTER-4Z), [-4Y](https://gyanoba.sentry.io/issues/FLUTTER-4Y), [-51](https://gyanoba.sentry.io/issues/FLUTTER-51), [-50](https://gyanoba.sentry.io/issues/FLUTTER-50), [-73](https://gyanoba.sentry.io/issues/FLUTTER-73) | 45 | **Fixed on `fix/sentry-setup`.** The device home page's `Scrollbar` had no controller and fell back to a primary controller that desktop doesn't attach; it and its scroll view now share one. |
| **L3** `RenderBox` not laid out (`RenderParagraph`) | [FLUTTER-B](https://gyanoba.sentry.io/issues/FLUTTER-B), [-5J](https://gyanoba.sentry.io/issues/FLUTTER-5J) | 8 | Not layout: the stack is `SelectableRegion` sorting selectables by bounding box before one is laid out, in release builds too. Same family as C3; fix with it. |
| **L4** `debugNeedsLayout` / follower layer | [FLUTTER-6M](https://gyanoba.sentry.io/issues/FLUTTER-6M), [-6Q](https://gyanoba.sentry.io/issues/FLUTTER-6Q), [-6R](https://gyanoba.sentry.io/issues/FLUTTER-6R), [-6K](https://gyanoba.sentry.io/issues/FLUTTER-6K) | 32 | Debug-only assertions, last seen 27 days ago. Resolve in Sentry; it reopens if it recurs. |

## Housekeeping

- Done with the gating change: `sendDefaultPii` is off, so events no longer carry user IP
  addresses (Sentry stops showing a city per user), and the web-only
  `upload_source_maps` is off in `pubspec.yaml`.
- Users are now counted by an install ID: a random 128-bit ID made on first launch and
  kept in preferences (`PreferencesService.installId`), set as the Sentry user. Before,
  Windows and Linux users were counted by IP and macOS ones by a native device ID, and with
  IPs off Windows and Linux would have counted none. Every install gets a new ID with the
  release that ships this, so user counts restart there. Reinstalling or clearing
  preferences also makes a new one.
- Baseline before the change (errors only, so a floor, not a total): about 28 distinct
  users sent a production error in the 90 days to 2026-10-25 (macOS 14, Windows 13,
  Linux 1), mostly from China and India. Sentry has no session data for these releases.
- Not changed: app hangs still report at Sentry's 2 s default and count toward the
  errors quota (FLUTTER-5V alone sent about 4,200 in 45 days). If that quota runs short,
  raise `options.appHangTimeoutInterval` or sample hangs in `beforeSend`.
- After gating debug builds, **merge** each group's issues in Sentry (select → *Merge*) so
  the next triage starts from the real count.
- Resolve the stale ones (last seen ≥ 26 days ago: FLUTTER-66, -6K, -6M group, -63) once
  the release after this one ships; they will reopen as regressions if they recur.
