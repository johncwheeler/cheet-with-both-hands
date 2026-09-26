# Multiple cheet windows, workspaces and stashing

Date: 2026-09-26 · Status: approved design, awaiting spec review

## Goal

Let people keep several cheets on screen at once, arrange them, save and recall those
arrangements as workspaces, and flick every cheet window out of the way with one hotkey.

Success looks like: put Git and Vim side by side with hotkeys, save that as "Coding", recall it
in one step, and stash everything while you work, then bring it back.

## Scope

In scope:

1. Multiple cheet windows, each a full copy of today's overlay (filter, scrolling, keyboard
   shortcuts, layout editing, per-window undo).
2. Replace-by-default hotkeys, with Shift for "open alongside".
3. Manual arranging plus a tile command.
4. Saved workspaces: a named set of cheet windows and their frames.
5. Stashing: slide every visible window almost off its screen, and back.

Out of scope: the same cheet in two windows; snapping windows to screen halves; restoring open
windows across app relaunches (workspaces cover that deliberately); sharing workspaces between
Macs other than through Export/Import Library.

## Behavior

### Windows

- **One window per cheet.** A cheet is never open in two windows. Anything that would duplicate
  it brings its existing window forward instead.
- **The active window** is the cheet window most recently focused or opened. Plain hotkeys,
  ⌘[ / ⌘], ⇧← / ⇧→, Esc and ⌘W act on it (the in-window keys act on the window that has focus).
- **New windows** open at the cheet's remembered frame when "Remember a separate position for
  each cheet" is on. Otherwise the first window uses today's preset frame, and later ones open
  offset (+28pt right, −28pt down) from the active window, clamped to its screen.

### Hotkeys, picker, menu bar, URL scheme

"Replace" puts cheet X where the active window is. "Alongside" adds X in a new window. A cheet
hotkey with Shift added is the alongside variant (see Hotkey resolution).

Smart trigger mode (the default), for a press of X's hotkey:

| Situation | On press | Tap (release before hold threshold) | Hold (release after) |
|---|---|---|---|
| X's window visible | Close X's window, as today | nothing more | nothing more |
| No cheet window visible | Open X (at its frame) | keep | close X (peek) |
| Other windows visible, plain | Open X in a new window at the active window's frame, on top | close the previous active window (X replaced it) | close X; previous window is untouched |
| Other windows visible, Shift | Open X in a new window (new-window placement) | keep | close X (peek) |

- Toggle trigger mode: always behaves like "tap". Hold trigger mode: always behaves like "hold".
- Deciding at release is what lets tap-to-replace and hold-to-peek share one press. Replacement
  keeps the slot's frame: X's window takes the active window's frame, not X's remembered one.
- **Picker:** Return replaces, ⇧Return / ⇧-click opens alongside.
- **Menu bar:** each cheet item has a Shift alternate item, "Open *X* Alongside".
- **URL scheme:** `show/<n or title>?alongside=1` opens alongside; `show` and `toggle` replace.
- **Hiding all** closes every cheet window and remembers the set in memory (each window's cheet,
  frame and filter, plus which was active). Every "hide all" path records it: the toggle-last
  hotkey, the menu bar's Hide item, and clicking outside.
- **Toggle last hotkey (⌃⌥⌘\`):** when any cheet windows are visible, hides them all; otherwise
  reopens the remembered set (or the last cheet if there's no set).
- **Ghost mode** applies to every window. **Hide when clicking outside** hides all windows when
  the click lands outside every cheet window.

### Inside a window

- ⌘[ / ⌘] and ⇧← / ⇧→ switch that window's cheet, skipping cheets open in other windows.
- Esc clears the filter, then closes that window. ⌘W closes that window.
- Everything else (filtering, scrolling, ⌘E layout editing, text size, copy on click) works per
  window exactly as today. Layout-editing undo history belongs to the window.

### Tiling

- Commands: "Tile Cheet Windows" in the menu bar and in each window's header menu, ⌥⌘T in any
  cheet window, and an optional global hotkey (unassigned by default; Settings › Hotkeys ›
  Global actions).
- Tiles the visible, unstashed cheet windows onto the active window's screen, inside its visible
  frame inset by the layout margin setting, with a 12pt gap.
- Up to 3 windows: side-by-side columns. 4 or more: a grid with `columns = ceil(sqrt(n))`,
  `rows = ceil(n / columns)`; the last row's windows share its width.
- Order is preserved: windows are sorted by their current frame (top row first, then left to
  right), so tiling tidies rather than shuffles.
- If a column would be narrower than the window minimum width (360pt), use fewer columns and
  more rows.
- Frames animate (0.25s). The results count as user arrangement: they're remembered like a drag,
  and saved into workspaces.

### Stashing

- Global action "Stash cheet windows", default **⌃⌥⌘H**, configurable. Pressing it again brings
  the windows back.
- Each visible window slides (0.25s) toward the nearest edge of its screen's visible frame, among
  edges that don't border another display. It moves until only a **20pt sliver** stays inside
  the visible frame, so slivers never sit under the menu bar or Dock. Distance to an edge is
  measured from the window's frame to that edge; ties prefer left/right over top/bottom.
- Clicking any sliver brings all windows back, like the hotkey. Each returns to its exact frame.
- While stashed: windows don't take keyboard focus; layout editing, if active, ends first;
  filter text and scroll positions are kept; stashed frames are never saved as remembered
  frames; saving a workspace uses the real (home) frames.
- Opening a cheet by tap, Shift-alongside, the toggle-last hotkey, or a workspace recall brings
  everything back first, then applies the normal rule. A hold-to-peek shows its cheet over the
  stash and leaves the stash alone.
- If a display disappears while stashed, windows come back with their frames clamped onto a
  screen that still exists (the screen containing the mouse).

### Workspaces

- **Save:** "Save Workspace…" in the menu bar, each window's header menu, and ⌥⌘S in a cheet
  window. A small naming window suggests the open cheets' titles joined with " + " (e.g. "Git +
  Vim"); saving a name that already exists asks whether to replace it.
- **Update:** after recalling workspace W and changing the windows, the menus also offer
  **Update "W"**, which overwrites W's windows with the current ones.
- **Recall:** closes the other cheet windows, restores W's windows and frames (unstashing first),
  and focuses W's active window. Available from:
  - the picker: workspaces listed above cheets, searchable by name;
  - the menu bar: a Workspaces submenu (recall items with their hotkeys, Save Workspace…,
    Update "W", Manage Workspaces…);
  - per-workspace global hotkeys;
  - the URL scheme: `cheetwithbothhands://workspace/<name or 1-based number>`.
- **Manage:** a new Settings › Workspaces pane lists workspaces (drag to reorder) with rename,
  hotkey recorder (with conflict badges), Recall and Delete.
- Windows whose cheet no longer exists are skipped on recall. Deleting a cheet removes it from
  every workspace; a workspace left with no windows stays (it can be updated or deleted).

## Architecture

`OverlayController` (824 lines, one panel) splits into a manager and per-window controllers. The
geometry and decision logic moves into `CheetCore` as pure, unit-tested functions.

### CheetCore (pure, tested)

| Unit | Purpose |
|---|---|
| `Workspace`, `WorkspaceWindow` (Models) | A named, ordered (back to front) list of windows, each with `cheetID`, `frame: NormalizedRect`, `displayID: String?` (CGDisplay UUID string), plus an optional `hotkey: KeyCombo`. The last window is the active one. Resilient decoding like other models. |
| `PressDecision` (Support) | Given the trigger mode, whether X is open, whether other windows are visible, whether the press was Shift, and (at release) the hold duration: what to do on press and on release. Encodes the table above. |
| `TileLayout` (Support) | Given window frames, a container rect, gap and minimum width: the tiled frames, in preserved order. |
| `StashGeometry` (Support) | Given a window frame, its screen's visible frame, all screens' frames and the sliver width: the chosen edge and stashed frame. |
| `HotkeyResolver` (extended) | New actions `.showCheetAlongside(UUID)`, `.recallWorkspace(UUID)`, `.stashWindows`, `.tileWindows`; resolves Shift variants and workspace hotkeys with the priority order below. |
| `LibraryStore` (extended) | Library file `version: 2` with `workspaces: [Workspace]` beside `cheets`. Version-1 files load with no workspaces; export/import and the launch backup include workspaces. |
| `HotkeySettings` (extended) | `stash: KeyCombo? = ⌃⌥⌘H`, `tile: KeyCombo? = nil`, `shiftForAlongside = true`. |

### App target

| Unit | Purpose |
|---|---|
| `CheetWindowController` | One cheet window: its `OverlayPanel`, `OverlayState`, `LayoutEditState`, search index, keyboard handling, scrolling, layout editing and undo. Mostly moved from `OverlayController`. Reports focus, close and frame changes to the manager. |
| `CheetWindowManager` | Owns the window controllers. Hotkey press/release (via `PressDecision`), the active window, placement of new windows, toggle-last set, tiling (via `TileLayout`), stashing (via `StashGeometry`) and workspace save/recall. Replaces `AppController.overlay`, keeping its entry points (`show`, `toggle`, `hide`, `toggleLast`, `hotkeyPressed/Released`, `showToast`, `editLayout`) so most callers don't change. |
| `AppModel` (extended) | `workspaces` array with debounced saving like `cheets`; deleting a cheet prunes it from workspaces. |
| Picker | Workspace rows above cheet rows; ⇧Return / ⇧-click for alongside. |
| Status menu | Shift alternate items; Tile, Stash; Workspaces submenu. |
| Settings | Hotkeys pane: Stash and Tile recorders, a Shift-for-alongside toggle and per-cheet "alongside" status. New Workspaces pane. |
| `WorkspaceNamingWindow` | Small window for Save Workspace…, with the duplicate-name confirmation. |
| URL commands | `alongside=1` and `workspace/…`. |
| Debug snapshots | Drives open-alongside ×3, tile, stash, unstash, save and recall; prints frames and captures windows. |

### Hotkey resolution

Priority when combos collide, highest first:

1. global actions: picker, toggle last, stash, tile, ghost mode
2. workspace hotkeys
3. custom cheet hotkeys
4. automatic number hotkeys
5. Shift "alongside" variants: for each cheet's effective combo that doesn't already include
   Shift, the same combo plus Shift

Losers are reported as conflicts, shown by the existing badges. A cheet whose combo already
includes Shift gets no alongside variant; the Hotkeys pane says so.

### Frames and remembered positions

- `ViewState.globalFrame` and per-cheet frames keep their meaning for where new windows open.
- A window's frame is saved (debounced) after the user moves, resizes or tiles it, never while
  stashed or animating.
- Workspace frames are normalized to the display's visible frame, with the display's UUID. On
  recall a window goes to that display if connected, otherwise to the screen with the mouse.

## Error handling and edge cases

- Recalling a workspace whose windows all reference deleted cheets: show a toast "Nothing to
  recall in W" (a beep when no cheet window is open to show it) and leave the current windows
  alone.
- A workspace or cheet hotkey that the system refuses (taken by another app): reported through
  the existing `hotkeyFailures` badges.
- Unreadable `workspaces` in `library.json` decode to an empty list without losing the cheets
  (resilient decoding), and the launch backup still holds the original file.
- Tiling with more windows than fit at minimum size: rows grow; windows are never narrower than
  360pt, but with very many windows on a small screen (roughly ten or more) rows can be shorter
  than the panel's 220pt minimum. Tiling doesn't enforce the minimum height.
- Stash with every edge shared (a window on a middle display of three stacked both ways): fall
  back to the nearest edge anyway.

## Testing

TDD for the CheetCore units:

- `PressDecision`: every row of the behavior table, in each trigger mode.
- `TileLayout`: 1–3 columns, 4 and 5 as grids, order preserved, fewer columns when narrower than
  the minimum, margins and gap respected.
- `StashGeometry`: nearest edge for each side, skip shared edges between two side-by-side
  displays, sliver exactly 20pt inside the visible frame, tie-break, all-edges-shared fallback.
- `HotkeyResolver`: workspace priority, Shift variants generated and skipped, conflicts
  reported.
- Workspaces: Codable round trip, version-1 library loads, pruning deleted cheets.

App-level: the debug snapshot run drives the real windows (above) and prints frames. Keyboard
paths (⇧Return in the picker, ⌥⌘T, ⌥⌘S, Esc closing one window) go through the same posted-event
helper the snapshot run already uses for scrolling.

## Build order

1. CheetCore models and pure functions, test-first.
2. Split `OverlayController` into `CheetWindowController` + `CheetWindowManager` with one window
   and no behavior change (the snapshot run still passes).
3. Multiple windows: replace/alongside, active window, placement, toggle last.
4. Tiling. 5. Stashing. 6. Workspaces (model, save, recall, picker, menu, settings, URL).
7. Docs: README and the welcome cheet.
