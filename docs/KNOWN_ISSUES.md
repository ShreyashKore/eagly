# Known issues

Bugs found and deliberately left for a later branch. Each entry gives the cause and a
suggested fix. Delete an entry in the commit that fixes it. iOS Rust backend issues are
tracked separately, in docs/IOS_RUST_MIGRATION.md → *Open issues*.

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
