# The device workspace: arranging feature panes

How the feature panes of a device (Logs, Mirror, Crash Reports, Files, Apps, Utilities,
Terminal) are laid out, moved, grouped and remembered. **Read this before changing the
workspace, a pane header, or adding a pane.**

The priorities, in order: **nothing a pane holds is ever lost to a layout change** (scroll
position, a half-typed command, a running mirror), then **discoverable for people who have
never used an IDE**, then IDE-style freedom for people who have.

## What the user gets

- **The rail stays the way in.** Clicking a rail item opens its pane — where it was last
  time, or along the right edge — or closes it if it is already in view. A pane hidden
  behind another tab is brought to the front instead of closed.
- **Panes are rearranged by their header, like windows by their title bar.** Every pane
  header starts with a grip (⠿) once a second pane is open. Dragging the grip — or the
  title, or the empty part of the header — picks the pane up:
  - drop on the **edge of another pane** → placed left of / right of / above / below it;
  - drop in the **middle of another pane** → the two become **tabs** in one area;
  - drop on the **edge of the whole workspace** → spans that edge;
  - a shaded preview shows where it will land, and a label at the pointer says it in words
    ("Place below Logs", "Group as tabs with Files"). **Escape** cancels.
- **Clicking the grip** (or right-clicking it) opens the same moves as a menu — *Move to ▸
  Left side / Right side / Top / Bottom*, *Group as tabs with ▸ …*, *Reset layout* — for
  anyone who doesn't drag.
- **Tabs.** In a tab group the tab strip is the title bar: each chip drags its pane out, closes
  it (×, or middle-click), and has a right-click menu (close, split, reset). The pane's own
  header then shows only its actions, and disappears if it has none.
- **Dividers** between panes resize them; right-click a divider for *Equal sizes* / *Swap*.
- **Reset layout** (grip menu, any fl_panel right-click menu, or *Reset Pane Layout* in the
  command palette) lines the open panes up side by side in rail order and forgets every
  remembered placement.
- **Placement is remembered** — per pane, shared by every device, and across restarts.

## The pieces

| Piece | File |
|---|---|
| Docking tree, edits, solver, drop resolution, drag session, JSON | the [`fl_panel`](https://pub.dev/packages/fl_panel) package (`PanelController`, `LayoutTree`, `PanelHost`) |
| Which panes exist, their sizes; open/close/arrange verbs; remembered placement | `lib/session/workspace_layout.dart` (`WorkspacePane`, `WorkspaceLayout`, `WorkspaceLayoutMemory`, `WorkspaceArrangement`) |
| Pane open/close/toggle as the rest of the app sees it | `DeviceSessionController.openPane` / `closePane` / `togglePane` (and the `openLogs` … wrappers) |
| The widget: `PanelHost`, header drags, drag label, menus | `lib/features/home_screen/components/workspace_view.dart` |
| How the chrome looks (strip only for real groups, no panel header, divider) | `lib/features/home_screen/components/workspace_chrome.dart` |
| What a pane header gets from the workspace (`PaneGrip`, `PaneDragArea`) | `lib/presentation/components/workspace_pane_scope.dart` |
| Which widget each pane is | `_Workspace` in `lib/features/home_screen/components/device_screen_content.dart` |
| Remembered placement on disk | `PreferencesService.workspaceLayout` (key `workspaceLayout`) |

### Why fl_panel

It was chosen over `docking` (the older, more popular package) because:

- `docking` wraps every item in its own tab bar, which would sit on top of our pane headers
  (two title rows per pane), and pins `tabbed_view`/`multi_split_view` two major versions
  behind;
- fl_panel draws content **flat**: every tab is a keyed `Positioned` child of one `Stack`, so
  a moved pane is never reparented and keeps its state with no `GlobalKey`s;
- its chrome is replaceable (`PanelChrome`), its model is pure Dart and immutable (every edit
  is a function you can test without widgets), and it has no dependencies beyond Flutter.

It is young (1.x, released 2026). Everything Eagly-specific sits in the files above, behind
`WorkspaceLayout`'s small API; if fl_panel ever has to go, that is the seam to cut along.

## How it fits together

```
DeviceSessionController ── openPane / closePane / togglePane ──┐
        │ listens (open set only)                              ▼
        └──────────────────────────────── WorkspaceLayout ── show / hide / moveToEdge / stackWith / reset
                                              │ owns                 │ reads/writes
                                              ▼                      ▼
                                   fl_panel PanelController   WorkspaceLayoutMemory ── PreferencesService
                                              │ listens
                                              ▼
WorkspaceView ── PanelHost(chrome: WorkspaceChrome) ── one Positioned per pane ── WorkspacePaneScope ── feature view
                                                                                         └── header: PaneGrip, PaneDragArea
```

- **The tree is the source of truth for which panes are open.** There are no `_logsOpen`-style
  flags any more; `isLogsOpen` asks the layout. A pane's tab id is its `WorkspacePane.name`.
- **Two kinds of change, two listeners.** `WorkspaceLayout` notifies only when the *set* of
  open panes changes; the session listens to that (so a tab's × reaches it, and closing the
  last pane falls back to Home). Divider drags, tab switches and moves only notify
  `layout.panels`, which `PanelHost` listens to directly — the rail and the rest of the device
  screen never rebuild for them.
- **The session's own edits notify once.** `openPane`/`closePane` wrap the layout edit in
  `_editLayout`, which mutes the layout listener for the duration, then notify themselves.

### Pane headers are the title bars

fl_panel normally draws a header above each single panel and drags the panel by it. Our
panes already have a header (title, actions, close), so `WorkspaceChrome` makes fl_panel's
header zero-height and the pane's own header does the job:

- The workspace wraps each pane in a `WorkspacePaneScope` carrying `isTabbed`, `canMove` and
  a `PaneControls` object (one per pane, stable for the life of the view).
- A header puts `const PaneGrip()` first and, optionally, wraps its title area in
  `PaneDragArea`. Both read the scope and draw nothing / do nothing without one — outside a
  workspace (tests, the imported-logs screen) a header looks exactly as it always did.
- `WorkspacePaneScope.showsOwnTitle` / `showsOwnClose` are false while the pane is tabbed
  (the chip has them); `showsGrip` is false then too (the chip is the handle).
- The drag a header starts can't use fl_panel's internal callbacks (they are only handed to
  chrome), so `WorkspaceView` drives it through the controller's public drag verbs —
  `beginDrag`, `updateDrag(hit, layout)`, `commitDrag` — solving the layout and hit-testing
  the way `PanelHost` does. Strips carry a `WorkspaceStripSlot` so a header drag over a strip
  joins that group.
- The drag only starts after 6 px of movement (`_PaneDragRecognizer`); a mouse pan would
  otherwise win after 2 px and a slightly shaky click on the grip would never open its menu.

### Remembered placement

`WorkspaceLayoutMemory` holds one fl_panel tree — the *arrangement* — containing every pane
the user has placed, open or closed, where each last stood. After every settled change (a
drop, an open or close, a released divider) the live tree is folded into it
(`WorkspaceArrangement.merge`): live panes as they are, closed ones put back relative to
them.

To reopen pane P, the arrangement is **cut down to the panes open now plus P**
(`WorkspaceArrangement.project`), and P's place in that smaller tree is replayed on the live
tree (`placeAsIn`):

- P shared a tab group → it joins the group of the first group-mate that is open;
- P sat beside a neighbour subtree → it splits beside the smallest live subtree holding all
  of that neighbour's panes, on the same side, at the **same share** of the two;
- P never stood beside anything open → it goes along the right edge at its preferred width.

Cutting down first is what guarantees the neighbours are panes that are open now, and it
makes placement survive rearranging the others in between (see the tests). Each session
keeps its own copy after first use, so two devices open at once can't reshuffle each other;
the shared memory (and preferences) take whichever was written last.

## Adding a pane

1. Add a value to `WorkspacePane` (label, preferred width, minimum width). Its `name` is its
   id in saved layouts — renaming it later just orphans the saved placement.
2. Build it in the `switch` in `_Workspace` (`device_screen_content.dart`), passing
   `onClose: () => session.closePane(pane)` (or a `close…` wrapper).
3. Give it an icon in `WorkspacePaneIcon` (`workspace_view.dart`) — used on tab chips and the
   drag label — matching its rail icon.
4. Side effects of opening it (load data, start a stream) go in the `switch` in
   `DeviceSessionController.openPane`. Add `open…`/`close…`/`toggle…` wrappers if callers
   want them, and a rail button / command-palette entry like the others.
5. Its header must be a title bar: use `FeatureViewHeader` (done), or put `const PaneGrip()`
   first in a custom toolbar, wrap an empty stretch in `PaneDragArea`, and hide its close
   button unless `WorkspacePaneScope.showsOwnClose(context)`. The *pane headers* group in
   `test/workspace_view_test.dart` shows how to test that.

## Guarantees and the tests that hold them

| # | Guarantee | Test |
|---|---|---|
| 1 | A moved or regrouped pane keeps its state; a pane behind another tab stays mounted. | `workspace_view_test` "…groups them as tabs, and the moved pane keeps its state" |
| 2 | Drops land where the preview and label say (edge → split, middle → tabs). | `workspace_view_test` "dropping a pane on the lower edge…", "…groups them as tabs…" |
| 3 | Escape cancels a drag; a click with a small wobble is still a click. | `workspace_view_test` "Escape abandons a drag", "a short wobble…" |
| 4 | Everything a drag does is also in the grip menu / chip menu. | `workspace_view_test` "the grip menu moves a pane without dragging" |
| 5 | A reopened pane comes back where it was, at its old share — also after its neighbours moved, after a restart, and on another device. | `workspace_layout_test` "a closed pane reopens…", "…even when they moved", "…shared by every workspace…", "…survives a restart…" |
| 6 | An unreadable stored layout never stops a pane opening. | `workspace_layout_test` "an unreadable stored placement is ignored" |
| 7 | The session hears about open/close only, once per change; closing the last pane from a tab falls back to Home; a hidden tab's rail click reveals it. | `workspace_layout_test` "listeners hear…", "DeviceSessionController panes" group |
| 8 | Every pane header (shared header, Logs toolbar, Files toolbar) has the grip and defers to the tab chip; real panes drag by their title. | `workspace_view_test` "pane headers" group |

## Gotchas

- **Never wrap pane content in a `GlobalKey` to "keep state across moves".** fl_panel never
  reparents content; a `GlobalKey` adds nothing and makes a duplicate-key crash possible.
- **Minimum sizes are hard floors.** `WorkspacePane.minWidth`/`minHeight` are honoured by the
  solver unless the window can't fit every floor at once; then everything scales down and
  the dividers between panes at their floor stop moving. Keep floors modest.
- **`WorkspaceView` must fill its constraints.** Its outer `Stack` uses
  `StackFit.expand`; with a loose height and only the (hidden) drag label as a
  non-positioned child it sized itself to zero height once, and no pane could be clicked.
- **Tests that mount `DeviceScreenContent`** also mount Device Home, which polls a
  *connected* device with real processes; use a disconnected device (Utilities and Terminal
  still work) or the test ends with pending timers.

## Not done yet

- **Maximise** a pane (fl_panel has no verb for it; a double-click on the header is the
  natural trigger).
- **Floating / detached windows** (fl_panel's file format reserves the slot; multi-window
  needs a second engine).
- **Opening the workspace with last session's panes** — only placement is remembered; which
  panes are open is not.
