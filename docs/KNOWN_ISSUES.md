# Known issues

Bugs found and deliberately left for a later branch. Each entry gives the cause and a
suggested fix. Delete an entry in the commit that fixes it. iOS Rust backend issues are
tracked separately, in docs/IOS_RUST_MIGRATION.md → *Open issues*.

## From the idevice 0.1.68 bump (`feat/idevice-0.1.68`, 2026-10-25)

### An orphaned `idevicesyslog` silences an iPhone's logs for everyone

`ToolProcessRunner.terminateAllProcesses` only runs on a graceful quit, so a Debug build stopped
from the IDE or `flutter run` leaves its `idevicesyslog` children running, reparented to
launchd. While one holds an iPhone's `os_trace_relay`, the phone sends no log records to any
other client: Eagly's Rust log stream, a fresh `idevicesyslog` and the `syslog_thread_ids` device
test all connected and then got nothing. Two such orphans, five days old, were found on an
iPhone on iOS 27.0; killing them brought its logs back at once.

**Fix:** record the PIDs of long-running children in a file under the app's support
directory and kill any still alive on the next launch, or have each child exit when the app
does (spawn it behind a small wrapper that watches the parent PID).

## From the iPhone screen mirror (`feat/ios-screen-mirror`, 2026-10-21)

### macOS crashes in Impeller while a mirror streams and the window changes

A Flutter engine bug: when the window's size changes and changes back, the macOS
back-buffer cache can return a surface of the wrong size, and Impeller dereferences a null
texture in `impeller::Canvas::SetupRenderPass` on the raster thread (EXC_BAD_ACCESS at 0x0,
through `EmbedderExternalViewEmbedder::SubmitFlutterView`). Window drags, resizes, full
screen, Space and display changes and coming to the front trigger it, and a video texture on
screen makes it reliable, because every frame redraws the window. It took Eagly down
seconds into an iPhone mirror. The fix,
[flutter/flutter#192522](https://github.com/flutter/flutter/pull/192522), is not merged and is
not in 3.47.7. The Android mirror's texture is exposed the same way.

`IosScreenCapturePlugin.swift` holds its redraws back while the window or screen is changing
(`WindowTransitionGuard`), which lowers the odds without removing them.

**Fix:** move to a Flutter release with #192522. Until then, `FLTEnableImpeller` = `false` in
`macos/Runner/Info.plist` (Skia) avoids it, at the cost of Impeller app-wide. If it stays on,
give `ScrcpyVideoPlugin.swift` the same guard.

## From the `release/1.5.4` review (2026-10-18)

### Every new session pulls every visible app's APK again

`AppsController._requestFreshIcon` skips a fetch only when `_iconFetchedSignature` already
holds the app's signature (version + recency). That map lives on the controller, and
`AppIconCache` stores icons and labels without it. So reopening the Apps pane after a
reconnect, a device reload or an app restart queues a full `adb pull` for every tile on
screen, even though the cached icon on disk is current. That can be tens of APKs and hundreds
of MB, sent over the adb connection that logcat streams on.

**Fix:** save the signature next to the cached icon in `AppIconCache`, and skip the fetch when
it matches.

### The interruption error row has no subject

When auto-recovery gives up, `LogController._enterInterruptedState` uses its message twice:
as the "Live logging stopped" banner's body and as an error row in the log. The messages were
shortened to rely on the banner's title, so the row (and any exported log) now reads "It could
not be resumed automatically. Restart logging or open a new tab." or "The stream dropped
while paused. Resume to reconnect, or open a new tab." Nothing in the row says what "it" is.

**Fix:** give the row its own text that names live logging, such as "Live logging stopped and
could not be resumed automatically…", or prefix the message when appending the entry.

### A Mirror pane behind another tab keeps streaming

With tab groups in the workspace, `paneBuilder` builds every open pane, so a Mirror pane
grouped behind another tab stays mounted offstage. `MirrorController` keeps the scrcpy session
running and updates its texture every frame for a view nobody can see. That costs CPU, GPU
and USB bandwidth. Before tab groups, an open Mirror pane was always visible.

**Fix:** pause the mirror (or stop decoding) while its pane isn't the front tab, and resume
when it comes back to the front.
