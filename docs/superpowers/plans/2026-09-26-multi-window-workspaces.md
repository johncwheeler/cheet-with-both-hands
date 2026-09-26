# Multiple Cheet Windows, Workspaces and Stashing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Several cheet windows on screen at once (replace by default, Shift for alongside), a tile command, saved workspaces, and a hotkey that stashes every cheet window at the screen edges.

**Architecture:** The one-window `OverlayController` splits into `CheetWindowController` (one per window, today's code) and `CheetWindowManager` (hotkeys, active window, placement, hide/toggle-last, tiling, stashing, workspaces). Decision and geometry logic lives in `CheetCore` as pure functions with Swift Testing tests; the app target wires them to AppKit.

**Tech Stack:** Swift 6 toolchain (app target in Swift 5 language mode), AppKit + SwiftUI, Carbon hotkeys, Swift Testing. Build with `make app`, test with `make test` (Command Line Tools need the Makefile's `TEST_FLAGS`; plain `swift test` fails on this Mac).

**Spec:** `docs/superpowers/specs/2026-09-26-multi-window-workspaces-design.md`

## Global Constraints

- macOS 14+ (`Package.swift` `.macOS(.v14)`); no new package dependencies.
- One window per cheet; a cheet is never open in two windows.
- New-window offset: +28pt right, −28pt down from the active window, clamped to its screen.
- Tile gap: 12pt; minimum tiled width 360pt; panel minimum size 360×220; up to 3 windows → columns, 4+ → grid with `columns = ceil(sqrt(n))`.
- Stash: 20pt sliver inside the screen's visible frame; 0.25s animation; default hotkey ⌃⌥⌘H.
- Tile animation 0.25s; tile hotkey unassigned by default.
- In-window shortcuts: ⌥⌘T tile, ⌥⌘S save workspace; picker ⇧Return / ⇧-click = alongside.
- Hotkey priority: global actions > workspace hotkeys > custom cheet > automatic number > Shift alongside variants.
- Library file `version: 2` with `workspaces` beside `cheets`; version-1 files still load.
- Workspace names compare case-insensitively; suggested name joins up to 3 cheet titles with " + ".
- Commit messages: sentence-style subject, body explaining why, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Bash SwiftPM commands in this environment need the sandbox disabled.

## Review Focus

1. **Hotkey auto-repeat while holding a combo** — must not open duplicate windows or re-trigger replace. Pinned in Task 6 (snapshot step pressing twice before releasing).
2. **A cheet deleted while it's open or saved in a workspace** — its window closes and workspaces drop it, without crashing on recall. Pinned in Task 4 (pruning test; `AppModel.delete` prunes) and Task 5 Step 5 (CheetsPane delete calls `closeWindow(showing:)`); `recall` also skips missing cheets (Task 9).
3. **Recalling a workspace saved on a display that's no longer connected** — windows land on the fallback screen, inside its visible frame. Pinned in Task 4 (`restoredFrame` tests).
4. **Tiling windows that sit on another display or partly off-screen** — they're still tiled inside the active screen's container. Pinned in Task 2 (off-container frames test).
5. **Stashing a window that already hangs past a screen edge** — distances clamp at 0 and the sliver is still exactly 20pt. Pinned in Task 3 (partially off-screen test).

---

## File Structure

CheetCore (pure, tested):
- Create `Sources/CheetCore/Support/PressDecision.swift` — tap/hold × replace/alongside decisions.
- Create `Sources/CheetCore/Support/TileLayout.swift` — tiled frames in reading order.
- Create `Sources/CheetCore/Support/StashGeometry.swift` — stash edge and frame.
- Create `Sources/CheetCore/Support/Geometry.swift` — `CGRect.clamped(to:minSize:)`.
- Create `Sources/CheetCore/Models/Workspace.swift` — `Workspace`, `WorkspaceWindow`, `ScreenInfo`, `restoredFrame`.
- Modify `Sources/CheetCore/Storage/LibraryStore.swift` — `Library`, version 2 file.
- Modify `Sources/CheetCore/Support/HotkeyResolver.swift` — new actions, workspaces, Shift variants.
- Modify `Sources/CheetCore/Models/Settings.swift` — `HotkeySettings.stash/tile/shiftForAlongside`.
- Create tests `Tests/CheetCoreTests/WindowingTests.swift`, `Tests/CheetCoreTests/WorkspaceTests.swift`; modify `SupportTests.swift`.

App target:
- Rename `Sources/CheetWithBothHands/Overlay/OverlayController.swift` → `CheetWindowController.swift` — one window.
- Create `Sources/CheetWithBothHands/Overlay/CheetWindowManager.swift` — all windows.
- Create `Sources/CheetWithBothHands/Support/NSScreen+Display.swift` — display UUID, screen lookup.
- Create `Sources/CheetWithBothHands/Settings/WorkspacesPane.swift`, `Sources/CheetWithBothHands/Settings/WorkspaceNamingView.swift`.
- Modify: `OverlayView.swift`, `AppController.swift`, `AppDelegate.swift` (URLCommands), `AppModel.swift`, `PickerController.swift`, `StatusMenuController.swift`, `SettingsView.swift`, `WindowManager.swift`, `CheetsPane.swift`, `DebugSnapshots.swift`, `README.md`, `Sources/CheetCore/Storage/SampleCheets.swift`, `Makefile`.

---

### Task 1: PressDecision (tap/hold × replace/alongside)

**Files:**
- Create: `Sources/CheetCore/Support/PressDecision.swift`
- Create: `Tests/CheetCoreTests/WindowingTests.swift`
- Modify: `Makefile` (optional test filter)

**Interfaces:**
- Consumes: `TriggerMode` (`.toggle`, `.hold`, `.smart`) from `Settings.swift`.
- Produces: `PressDecision.Situation` (`.cheetVisible`, `.noWindows`, `.othersVisible`), `PressDecision.OnPress` (`.close`, `.open`, `.openOver`), `PressDecision.OnRelease` (`.nothing`, `.closeOpened`, `.closeReplaced`), `PressDecision.onPress(_:alongside:) -> OnPress`, `PressDecision.onRelease(after:trigger:heldFor:holdThreshold:) -> OnRelease`.

- [ ] **Step 1: Let `make test` take a filter**

In `Makefile`, change the test recipe line from `@swift test $(TEST_FLAGS)` to:

```make
	@swift test $(TEST_FLAGS) $(if $(FILTER),--filter $(FILTER))
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/CheetCoreTests/WindowingTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import CheetCore

struct PressDecisionTests {
    @Test func pressDependsOnSituationAndShift() {
        #expect(PressDecision.onPress(.cheetVisible, alongside: false) == .close)
        #expect(PressDecision.onPress(.cheetVisible, alongside: true) == .close)
        #expect(PressDecision.onPress(.noWindows, alongside: false) == .open)
        #expect(PressDecision.onPress(.noWindows, alongside: true) == .open)
        #expect(PressDecision.onPress(.othersVisible, alongside: false) == .openOver)
        #expect(PressDecision.onPress(.othersVisible, alongside: true) == .open)
    }

    @Test func smartModeTapKeepsAndReplaces() {
        #expect(PressDecision.onRelease(after: .openOver, trigger: .smart, heldFor: 0.1, holdThreshold: 0.35) == .closeReplaced)
        #expect(PressDecision.onRelease(after: .open, trigger: .smart, heldFor: 0.1, holdThreshold: 0.35) == .nothing)
    }

    @Test func smartModeHoldPeeks() {
        #expect(PressDecision.onRelease(after: .openOver, trigger: .smart, heldFor: 0.5, holdThreshold: 0.35) == .closeOpened)
        #expect(PressDecision.onRelease(after: .open, trigger: .smart, heldFor: 0.35, holdThreshold: 0.35) == .closeOpened)
    }

    @Test func toggleModeAlwaysTapsAndHoldModeAlwaysPeeks() {
        #expect(PressDecision.onRelease(after: .openOver, trigger: .toggle, heldFor: 5, holdThreshold: 0.35) == .closeReplaced)
        #expect(PressDecision.onRelease(after: .open, trigger: .toggle, heldFor: 5, holdThreshold: 0.35) == .nothing)
        #expect(PressDecision.onRelease(after: .open, trigger: .hold, heldFor: 0.01, holdThreshold: 0.35) == .closeOpened)
        #expect(PressDecision.onRelease(after: .openOver, trigger: .hold, heldFor: 0.01, holdThreshold: 0.35) == .closeOpened)
    }

    @Test func closingPressNeedsNoRelease() {
        for trigger in TriggerMode.allCases {
            #expect(PressDecision.onRelease(after: .close, trigger: trigger, heldFor: 2, holdThreshold: 0.35) == .nothing)
        }
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `make test FILTER=PressDecisionTests`
Expected: build failure, "cannot find 'PressDecision' in scope".

- [ ] **Step 4: Implement**

Create `Sources/CheetCore/Support/PressDecision.swift`:

```swift
import Foundation

/// What a cheet hotkey press does when several cheet windows can be open. Decided in two halves:
/// on press (before it's known whether this is a tap or a hold) and on release.
public enum PressDecision {
    public enum Situation: Equatable, Sendable {
        /// The pressed cheet's window is visible.
        case cheetVisible
        /// No cheet windows are visible.
        case noWindows
        /// Other cheet windows are visible.
        case othersVisible
    }

    public enum OnPress: Equatable, Sendable {
        /// Close the pressed cheet's window.
        case close
        /// Open the cheet in a new window at its usual place.
        case open
        /// Open the cheet in a new window on top of the active window, at the active window's frame.
        case openOver
    }

    public enum OnRelease: Equatable, Sendable {
        case nothing
        /// A peek ended: close the window the press opened.
        case closeOpened
        /// A tap after `openOver`: close the window underneath, so the new one replaced it.
        case closeReplaced
    }

    public static func onPress(_ situation: Situation, alongside: Bool) -> OnPress {
        switch situation {
        case .cheetVisible: .close
        case .noWindows: .open
        case .othersVisible: alongside ? .open : .openOver
        }
    }

    public static func onRelease(after press: OnPress, trigger: TriggerMode, heldFor seconds: Double,
                                 holdThreshold: Double) -> OnRelease {
        guard press != .close else { return .nothing }
        let isHold = switch trigger {
        case .toggle: false
        case .hold: true
        case .smart: seconds >= holdThreshold
        }
        if isHold { return .closeOpened }
        return press == .openOver ? .closeReplaced : .nothing
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test FILTER=PressDecisionTests`
Expected: `✔ Test run with 5 tests … passed`.

- [ ] **Step 6: Commit**

```bash
git add Makefile Sources/CheetCore/Support/PressDecision.swift Tests/CheetCoreTests/WindowingTests.swift
git commit -m "Decide what cheet hotkey presses do with several windows open" -m "Pure tap/hold × replace/alongside rules for the upcoming multi-window overlay, and a FILTER option for make test." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: TileLayout

**Files:**
- Create: `Sources/CheetCore/Support/TileLayout.swift`
- Modify: `Tests/CheetCoreTests/WindowingTests.swift` (append)

**Interfaces:**
- Produces: `TileLayout.tile(_ frames: [CGRect], in container: CGRect, gap: CGFloat, minWidth: CGFloat) -> [CGRect]` — one frame per input frame, same index order, AppKit coordinates (origin bottom-left).

- [ ] **Step 1: Write the failing tests**

Append to `Tests/CheetCoreTests/WindowingTests.swift`:

```swift
struct TileLayoutTests {
    // 1010 wide with 10pt gaps divides evenly into 1, 2 and 3 columns; 610 high into 1 or 2 rows.
    let container = CGRect(x: 0, y: 0, width: 1010, height: 610)

    func frame(x: CGFloat, y: CGFloat) -> CGRect { CGRect(x: x, y: y, width: 300, height: 200) }

    @Test func oneWindowFillsTheContainer() {
        let tiled = TileLayout.tile([frame(x: 50, y: 50)], in: container, gap: 10, minWidth: 360)
        #expect(tiled == [container])
    }

    @Test func threeWindowsBecomeColumnsInLeftToRightOrder() {
        // Given right, left, middle.
        let tiled = TileLayout.tile([frame(x: 700, y: 100), frame(x: 10, y: 100), frame(x: 350, y: 100)],
                                    in: container, gap: 10, minWidth: 300)
        #expect(tiled[1] == CGRect(x: 0, y: 0, width: 330, height: 610))
        #expect(tiled[2] == CGRect(x: 340, y: 0, width: 330, height: 610))
        #expect(tiled[0] == CGRect(x: 680, y: 0, width: 330, height: 610))
    }

    @Test func fourWindowsBecomeATwoByTwoGridTopRowFirst() {
        // Top row is higher y in AppKit coordinates.
        let topLeft = frame(x: 0, y: 400), topRight = frame(x: 600, y: 400)
        let bottomLeft = frame(x: 0, y: 0), bottomRight = frame(x: 600, y: 0)
        let tiled = TileLayout.tile([bottomRight, topLeft, bottomLeft, topRight], in: container, gap: 10, minWidth: 360)
        #expect(tiled[1] == CGRect(x: 0, y: 310, width: 500, height: 300))
        #expect(tiled[3] == CGRect(x: 510, y: 310, width: 500, height: 300))
        #expect(tiled[2] == CGRect(x: 0, y: 0, width: 500, height: 300))
        #expect(tiled[0] == CGRect(x: 510, y: 0, width: 500, height: 300))
    }

    @Test func fiveWindowsShareTheLastRowsWidth() {
        let frames = (0..<5).map { frame(x: CGFloat($0) * 150, y: 300) }
        let tiled = TileLayout.tile(frames, in: container, gap: 10, minWidth: 300)
        // 3 columns: 3 on top, 2 below at half width each.
        #expect(tiled[0].width == 330)
        #expect(tiled[3] == CGRect(x: 0, y: 0, width: 500, height: 300))
        #expect(tiled[4] == CGRect(x: 510, y: 0, width: 500, height: 300))
    }

    @Test func tooNarrowForThreeColumnsUsesRows() {
        let frames = [frame(x: 0, y: 100), frame(x: 300, y: 100), frame(x: 600, y: 100)]
        let tiled = TileLayout.tile(frames, in: container, gap: 10, minWidth: 360)
        // 330-wide columns are under 360, so 2 columns × 2 rows; the third window takes the bottom row.
        #expect(tiled[0] == CGRect(x: 0, y: 310, width: 500, height: 300))
        #expect(tiled[1] == CGRect(x: 510, y: 310, width: 500, height: 300))
        #expect(tiled[2] == CGRect(x: 0, y: 0, width: 1010, height: 300))
    }

    @Test func framesOutsideTheContainerStillLandInsideIt() {
        // Windows on another display (negative x) or hanging off the top.
        let frames = [CGRect(x: -900, y: 100, width: 400, height: 300), CGRect(x: 800, y: 700, width: 400, height: 300)]
        let tiled = TileLayout.tile(frames, in: container.offsetBy(dx: 100, dy: 50), gap: 10, minWidth: 360)
        for frame in tiled { #expect(container.offsetBy(dx: 100, dy: 50).contains(frame)) }
        #expect(tiled[0].minX < tiled[1].minX)
    }

    @Test func noWindowsNoFrames() {
        #expect(TileLayout.tile([], in: container, gap: 10, minWidth: 360).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=TileLayoutTests`
Expected: build failure, "cannot find 'TileLayout' in scope".

- [ ] **Step 3: Implement**

Create `Sources/CheetCore/Support/TileLayout.swift`:

```swift
import CoreGraphics

/// Arranges windows side by side (up to three) or in a grid, keeping their reading order so tiling
/// tidies an arrangement rather than shuffling it. AppKit coordinates: origin bottom-left, y up.
public enum TileLayout {
    /// A frame for each of `frames` (same order), tiled inside `container`.
    public static func tile(_ frames: [CGRect], in container: CGRect, gap: CGFloat, minWidth: CGFloat) -> [CGRect] {
        let count = frames.count
        guard count > 0 else { return [] }
        var columns = count <= 3 ? count : Int(Double(count).squareRoot().rounded(.up))
        while columns > 1, span(container.width, into: columns, gap: gap) < minWidth { columns -= 1 }
        let rows = (count + columns - 1) / columns
        let rowHeight = span(container.height, into: rows, gap: gap)

        // Reading order: which row band each window's centre falls in (top first), then left to right.
        let band = container.height / CGFloat(rows)
        func row(_ frame: CGRect) -> Int { min(rows - 1, max(0, Int((container.maxY - frame.midY) / band))) }
        let order = frames.indices.sorted { a, b in
            let (rowA, rowB) = (row(frames[a]), row(frames[b]))
            if rowA != rowB { return rowA < rowB }
            if frames[a].midX != frames[b].midX { return frames[a].midX < frames[b].midX }
            return a < b
        }

        var result = frames
        for (position, index) in order.enumerated() {
            let row = position / columns
            let column = position % columns
            let inRow = min(columns, count - row * columns)
            let width = span(container.width, into: inRow, gap: gap)
            let x = container.minX + CGFloat(column) * (width + gap)
            let y = container.maxY - CGFloat(row + 1) * rowHeight - CGFloat(row) * gap
            result[index] = CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(.down), height: rowHeight.rounded(.down))
        }
        return result
    }

    /// Size of each of `parts` pieces of `total` with `gap` between them.
    private static func span(_ total: CGFloat, into parts: Int, gap: CGFloat) -> CGFloat {
        (total - gap * CGFloat(parts - 1)) / CGFloat(parts)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test FILTER=TileLayoutTests`
Expected: `✔ … 7 tests … passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CheetCore/Support/TileLayout.swift Tests/CheetCoreTests/WindowingTests.swift
git commit -m "Tile layout for cheet windows" -m "Columns for up to three windows, a grid beyond that, fewer columns when they'd be too narrow, and reading order preserved." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: StashGeometry

**Files:**
- Create: `Sources/CheetCore/Support/StashGeometry.swift`
- Modify: `Tests/CheetCoreTests/WindowingTests.swift` (append)

**Interfaces:**
- Produces: `StashEdge` (`.left`, `.right`, `.top`, `.bottom`), `StashGeometry.stash(_ frame: CGRect, visibleFrame: CGRect, screenFrame: CGRect, otherScreens: [CGRect], sliver: CGFloat) -> (edge: StashEdge, frame: CGRect)`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/CheetCoreTests/WindowingTests.swift`:

```swift
struct StashGeometryTests {
    // A 1440×900 screen; the visible frame loses a 25pt menu bar at the top and a 60pt Dock at the bottom.
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let visible = CGRect(x: 0, y: 60, width: 1440, height: 815)

    func stash(_ frame: CGRect, others: [CGRect] = []) -> (edge: StashEdge, frame: CGRect) {
        StashGeometry.stash(frame, visibleFrame: visible, screenFrame: screen, otherScreens: others, sliver: 20)
    }

    @Test func slidesToTheNearestSideLeavingASliver() {
        let left = stash(CGRect(x: 40, y: 300, width: 400, height: 300))
        #expect(left.edge == .left)
        #expect(left.frame == CGRect(x: -380, y: 300, width: 400, height: 300))

        let right = stash(CGRect(x: 1000, y: 300, width: 400, height: 300))
        #expect(right.edge == .right)
        #expect(right.frame.minX == 1420)
    }

    @Test func topAndBottomStayClearOfTheMenuBarAndDock() {
        let top = stash(CGRect(x: 500, y: 560, width: 400, height: 300)) // 15pt below the visible top
        #expect(top.edge == .top)
        #expect(top.frame.minY == visible.maxY - 20)

        let bottom = stash(CGRect(x: 500, y: 70, width: 400, height: 300)) // 10pt above the Dock
        #expect(bottom.edge == .bottom)
        #expect(bottom.frame.maxY == visible.minY + 20)
    }

    @Test func tiesPreferLeftAndRightOverTopAndBottom() {
        // 20pt from the left edge and 20pt from the top (maxY 855, visible top 875).
        let result = stash(CGRect(x: 20, y: 555, width: 400, height: 300))
        #expect(result.edge == .left)
    }

    @Test func skipsAnEdgeSharedWithAnotherDisplay() {
        let displayOnTheLeft = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let result = stash(CGRect(x: 30, y: 300, width: 400, height: 300), others: [displayOnTheLeft])
        #expect(result.edge != .left)
    }

    @Test func aDisplayBesideButNotAlongsideTheWindowDoesNotBlockTheEdge() {
        // The other display sits to the left but only spans y 0…200; the window is at y 300…600.
        let lowDisplay = CGRect(x: -800, y: 0, width: 800, height: 200)
        #expect(stash(CGRect(x: 30, y: 300, width: 400, height: 300), others: [lowDisplay]).edge == .left)
    }

    @Test func fallsBackToTheNearestEdgeWhenEveryEdgeIsShared() {
        let neighbours = [CGRect(x: -1440, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1440, height: 900),
                          CGRect(x: 0, y: 900, width: 1440, height: 900), CGRect(x: 0, y: -900, width: 1440, height: 900)]
        #expect(stash(CGRect(x: 30, y: 300, width: 400, height: 300), others: neighbours).edge == .left)
    }

    @Test func aWindowAlreadyHangingPastAnEdgeStillGetsExactlyASliver() {
        let result = stash(CGRect(x: -150, y: 300, width: 400, height: 300))
        #expect(result.edge == .left)
        #expect(result.frame.maxX == visible.minX + 20)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=StashGeometryTests`
Expected: build failure, "cannot find 'StashGeometry' in scope".

- [ ] **Step 3: Implement**

Create `Sources/CheetCore/Support/StashGeometry.swift`:

```swift
import CoreGraphics

public enum StashEdge: String, CaseIterable, Sendable {
    // Declaration order is the tie-break order: sides before top and bottom.
    case left, right, top, bottom
}

/// Where a cheet window goes when stashed. AppKit coordinates: origin bottom-left, y up.
public enum StashGeometry {
    /// Slides `frame` toward the nearest edge of `visibleFrame` whose screen edge doesn't border
    /// another display alongside the window, leaving `sliver` points inside the visible frame.
    /// If every edge is shared, the nearest edge wins anyway.
    public static func stash(_ frame: CGRect, visibleFrame: CGRect, screenFrame: CGRect, otherScreens: [CGRect],
                             sliver: CGFloat) -> (edge: StashEdge, frame: CGRect) {
        func distance(_ edge: StashEdge) -> CGFloat {
            switch edge {
            case .left: max(0, frame.minX - visibleFrame.minX)
            case .right: max(0, visibleFrame.maxX - frame.maxX)
            case .top: max(0, visibleFrame.maxY - frame.maxY)
            case .bottom: max(0, frame.minY - visibleFrame.minY)
            }
        }
        let open = StashEdge.allCases.filter { !isShared($0, window: frame, screen: screenFrame, others: otherScreens) }
        let candidates = open.isEmpty ? StashEdge.allCases : open
        // min(by:) keeps the first of equal minimums, so declaration order breaks ties.
        let edge = candidates.min { distance($0) < distance($1) } ?? .left

        var stashed = frame
        switch edge {
        case .left: stashed.origin.x = visibleFrame.minX + sliver - frame.width
        case .right: stashed.origin.x = visibleFrame.maxX - sliver
        case .top: stashed.origin.y = visibleFrame.maxY - sliver
        case .bottom: stashed.origin.y = visibleFrame.minY + sliver - frame.height
        }
        return (edge, stashed)
    }

    /// Whether sliding past this edge of the screen would put the window onto another display.
    static func isShared(_ edge: StashEdge, window: CGRect, screen: CGRect, others: [CGRect]) -> Bool {
        func overlaps(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> Bool { a0 < b1 && b0 < a1 }
        func touches(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= 1 }
        return others.contains { other in
            switch edge {
            case .left: touches(other.maxX, screen.minX) && overlaps(other.minY, other.maxY, window.minY, window.maxY)
            case .right: touches(other.minX, screen.maxX) && overlaps(other.minY, other.maxY, window.minY, window.maxY)
            case .top: touches(other.minY, screen.maxY) && overlaps(other.minX, other.maxX, window.minX, window.maxX)
            case .bottom: touches(other.maxY, screen.minY) && overlaps(other.minX, other.maxX, window.minX, window.maxX)
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test FILTER=StashGeometryTests`
Expected: `✔ … 7 tests … passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CheetCore/Support/StashGeometry.swift Tests/CheetCoreTests/WindowingTests.swift
git commit -m "Stash geometry for cheet windows" -m "Nearest screen edge that doesn't border another display, leaving a sliver inside the visible frame so it never sits under the menu bar or Dock." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Workspace model, library v2 and AppModel workspaces

**Files:**
- Create: `Sources/CheetCore/Support/Geometry.swift`
- Create: `Sources/CheetCore/Models/Workspace.swift`
- Modify: `Sources/CheetCore/Storage/LibraryStore.swift`
- Modify: `Sources/CheetWithBothHands/App/AppModel.swift`
- Modify: `Sources/CheetWithBothHands/App/AppController.swift` (`importLibrary`)
- Create: `Tests/CheetCoreTests/WorkspaceTests.swift`
- Modify: `Tests/CheetCoreTests/SupportTests.swift` (storage tests use the new API)

**Interfaces:**
- Consumes: `NormalizedRect` (Settings.swift), `KeyCombo`, `KeyedDecodingContainer.value(_:or:)` / `optionalValue(_:)` (SectionLayout.swift, internal to CheetCore).
- Produces:
  - `extension CGRect { public func clamped(to container: CGRect, minSize: CGSize) -> CGRect }`
  - `public struct WorkspaceWindow: Codable, Hashable, Sendable { cheetID: UUID; frame: NormalizedRect; displayID: String?; init(cheetID:frame:displayID:) }`
  - `public struct Workspace: Identifiable, Codable, Hashable, Sendable { id: UUID; name: String; windows: [WorkspaceWindow]; hotkey: KeyCombo?; createdAt: Date; updatedAt: Date; init(id:name:windows:hotkey:createdAt:updatedAt:); func pruned(keeping: Set<UUID>) -> Workspace; static func suggestedName(for titles: [String]) -> String }`
  - `public struct ScreenInfo: Equatable, Sendable { displayID: String?; visibleFrame: CGRect; init(displayID:visibleFrame:) }`
  - `WorkspaceWindow.restoredFrame(on screens: [ScreenInfo], fallback: ScreenInfo, minSize: CGSize) -> CGRect`
  - `public struct Library: Equatable, Sendable { cheets: [Cheet]; workspaces: [Workspace]; init(cheets:workspaces:) }`
  - `LibraryStore.loadLibrary() throws -> Library?`, `saveLibrary(_:) throws`, `static encodeLibrary(_ library: Library) throws -> Data`, `static decodeLibrary(from: Data) throws -> Library`. `loadCheets()` stays (read-only convenience); `saveCheets` and the old `encodeLibrary(_ cheets:)`/`decodeCheets(from:)` are removed.
  - `AppModel.workspaces: [Workspace]` (saved with the library; deleting a cheet prunes it).

- [ ] **Step 1: Write the failing tests**

Create `Tests/CheetCoreTests/WorkspaceTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import CheetCore

struct WorkspaceTests {
    let git = UUID(), vim = UUID(), tmux = UUID()

    func window(_ id: UUID, display: String? = "DISPLAY-A") -> WorkspaceWindow {
        WorkspaceWindow(cheetID: id, frame: NormalizedRect(x: 0.1, y: 0.2, width: 0.4, height: 0.5), displayID: display)
    }

    @Test func roundTripsThroughJSON() throws {
        let workspace = Workspace(name: "Coding", windows: [window(git), window(vim)],
                                  hotkey: KeyCombo(keyCode: KeyCodes.one, modifiers: [.control, .option]))
        let data = try JSONEncoder.cheet.encode(workspace)
        #expect(try JSONDecoder.cheet.decode(Workspace.self, from: data) == workspace)
    }

    @Test func decodesWithMissingOrBrokenFields() throws {
        let json = #"{"name":"Old","windows":[{"cheetID":"\#(git.uuidString)","frame":{"x":0,"y":0,"width":0.5,"height":0.5}}],"hotkey":"nonsense"}"#
        let workspace = try JSONDecoder.cheet.decode(Workspace.self, from: Data(json.utf8))
        #expect(workspace.name == "Old")
        #expect(workspace.windows.map(\.cheetID) == [git])
        #expect(workspace.windows[0].displayID == nil)
        #expect(workspace.hotkey == nil)
    }

    @Test func pruningDropsDeletedCheets() {
        let workspace = Workspace(name: "W", windows: [window(git), window(vim), window(tmux)])
        #expect(workspace.pruned(keeping: [git, tmux]).windows.map(\.cheetID) == [git, tmux])
    }

    @Test func suggestedNames() {
        #expect(Workspace.suggestedName(for: []) == "Workspace")
        #expect(Workspace.suggestedName(for: ["Git"]) == "Git")
        #expect(Workspace.suggestedName(for: ["Git", "Vim"]) == "Git + Vim")
        #expect(Workspace.suggestedName(for: ["Git", "Vim", "tmux", "Zsh", "Go"]) == "Git + Vim + tmux + 2 more")
    }

    @Test func restoresOnItsOwnDisplayWhenConnected() {
        let a = ScreenInfo(displayID: "DISPLAY-A", visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let b = ScreenInfo(displayID: "DISPLAY-B", visibleFrame: CGRect(x: 1000, y: 0, width: 2000, height: 1000))
        let frame = window(git, display: "DISPLAY-B").restoredFrame(on: [a, b], fallback: a, minSize: CGSize(width: 360, height: 220))
        #expect(frame == CGRect(x: 1200, y: 200, width: 800, height: 500))
    }

    @Test func missingDisplayFallsBackInsideTheFallbackScreen() {
        let a = ScreenInfo(displayID: "DISPLAY-A", visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let frame = window(git, display: "UNPLUGGED").restoredFrame(on: [a], fallback: a, minSize: CGSize(width: 360, height: 220))
        #expect(frame == CGRect(x: 100, y: 160, width: 400, height: 400))
        #expect(a.visibleFrame.contains(frame))
    }

    @Test func clampingKeepsARectInsideItsContainerAndAboveMinimumSize() {
        let container = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(CGRect(x: 900, y: -50, width: 300, height: 100).clamped(to: container, minSize: CGSize(width: 360, height: 220))
                == CGRect(x: 640, y: 0, width: 360, height: 220))
        #expect(CGRect(x: -10, y: 10, width: 2000, height: 100).clamped(to: container, minSize: .zero)
                == CGRect(x: 0, y: 10, width: 1000, height: 100))
    }
}

struct LibraryFileTests {
    @Test func libraryWithWorkspacesRoundTrips() throws {
        let cheet = Cheet(title: "Git", sections: [], createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                          updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let workspace = Workspace(name: "Coding", windows: [WorkspaceWindow(cheetID: cheet.id, frame: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1), displayID: nil)],
                                  createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let library = Library(cheets: [cheet], workspaces: [workspace])
        let data = try LibraryStore.encodeLibrary(library)
        #expect(String(decoding: data, as: UTF8.self).contains("\"version\" : 2"))
        #expect(try LibraryStore.decodeLibrary(from: data) == library)
    }

    @Test func versionOneFilesLoadWithNoWorkspaces() throws {
        let json = #"{"version":1,"cheets":[{"title":"Old","sections":[]}]}"#
        let library = try LibraryStore.decodeLibrary(from: Data(json.utf8))
        #expect(library.cheets.map(\.title) == ["Old"])
        #expect(library.workspaces.isEmpty)
    }

    @Test func unreadableWorkspacesDoNotLoseTheCheets() throws {
        let json = #"{"version":2,"cheets":[{"title":"Keep","sections":[]}],"workspaces":"garbage"}"#
        let library = try LibraryStore.decodeLibrary(from: Data(json.utf8))
        #expect(library.cheets.map(\.title) == ["Keep"])
        #expect(library.workspaces.isEmpty)
    }

    @Test func bareArraysAndSingleCheetsStillImport() throws {
        let single = try LibraryStore.decodeLibrary(from: Data(#"{"title":"One","sections":[]}"#.utf8))
        #expect(single.cheets.map(\.title) == ["One"])
        let array = try LibraryStore.decodeLibrary(from: Data(#"[{"title":"A","sections":[]},{"title":"B","sections":[]}]"#.utf8))
        #expect(array.cheets.map(\.title) == ["A", "B"])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test FILTER=Workspace`
Expected: build failure, "cannot find 'WorkspaceWindow' in scope".

- [ ] **Step 3: Implement geometry clamping**

Create `Sources/CheetCore/Support/Geometry.swift`:

```swift
import CoreGraphics

extension CGRect {
    /// This rect kept inside `container`: at least `minSize` (but no bigger than the container) and
    /// moved, not shrunk, to fit. Rounded to whole points.
    public func clamped(to container: CGRect, minSize: CGSize) -> CGRect {
        var r = self
        r.size.width = min(max(r.width, minSize.width), container.width)
        r.size.height = min(max(r.height, minSize.height), container.height)
        r.origin.x = min(max(r.minX, container.minX), container.maxX - r.width)
        r.origin.y = min(max(r.minY, container.minY), container.maxY - r.height)
        return r.integral
    }
}
```

- [ ] **Step 4: Implement the workspace model**

Create `Sources/CheetCore/Models/Workspace.swift`:

```swift
import CoreGraphics
import Foundation

/// One window in a saved workspace.
public struct WorkspaceWindow: Codable, Hashable, Sendable {
    public var cheetID: UUID
    /// Relative to the display's visible frame.
    public var frame: NormalizedRect
    /// The display's UUID (CGDisplayCreateUUIDFromDisplayID), stable across reboots; nil if unknown.
    public var displayID: String?

    public init(cheetID: UUID, frame: NormalizedRect, displayID: String?) {
        self.cheetID = cheetID
        self.frame = frame
        self.displayID = displayID
    }
}

/// A display, as far as restoring workspace frames is concerned.
public struct ScreenInfo: Equatable, Sendable {
    public var displayID: String?
    public var visibleFrame: CGRect

    public init(displayID: String?, visibleFrame: CGRect) {
        self.displayID = displayID
        self.visibleFrame = visibleFrame
    }
}

extension WorkspaceWindow {
    /// Where to put this window: on its own display if it's connected, otherwise on `fallback`,
    /// kept inside that screen's visible frame.
    public func restoredFrame(on screens: [ScreenInfo], fallback: ScreenInfo, minSize: CGSize) -> CGRect {
        let screen = screens.first { $0.displayID != nil && $0.displayID == displayID } ?? fallback
        return frame.denormalized(in: screen.visibleFrame).clamped(to: screen.visibleFrame, minSize: minSize)
    }
}

/// A named set of cheet windows and their frames. Windows are ordered back to front; the last one
/// is focused (the active window) when the workspace is recalled.
public struct Workspace: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var windows: [WorkspaceWindow]
    public var hotkey: KeyCombo?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, windows: [WorkspaceWindow], hotkey: KeyCombo? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.windows = windows
        self.hotkey = hotkey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The workspace without windows for cheets that no longer exist.
    public func pruned(keeping cheetIDs: Set<UUID>) -> Workspace {
        var copy = self
        copy.windows = windows.filter { cheetIDs.contains($0.cheetID) }
        return copy
    }

    /// "Git + Vim", "Git + Vim + tmux + 2 more", or "Workspace" when nothing is open.
    public static func suggestedName(for titles: [String]) -> String {
        guard !titles.isEmpty else { return "Workspace" }
        let shown = titles.prefix(3).joined(separator: " + ")
        return titles.count > 3 ? "\(shown) + \(titles.count - 3) more" : shown
    }
}

extension Workspace: Codable {
    private enum CodingKeys: String, CodingKey { case id, name, windows, hotkey, createdAt, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "Workspace")
        windows = c.value(.windows, or: [])
        hotkey = c.optionalValue(.hotkey)
        createdAt = c.value(.createdAt, or: Date())
        updatedAt = c.value(.updatedAt, or: createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(windows, forKey: .windows)
        try c.encodeIfPresent(hotkey, forKey: .hotkey)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
```

- [ ] **Step 5: Library version 2 in LibraryStore**

In `Sources/CheetCore/Storage/LibraryStore.swift`:

1. Above `public final class LibraryStore`, add:

```swift
/// Everything in library.json: the cheets (in order) and the saved workspaces.
public struct Library: Equatable, Sendable {
    public var cheets: [Cheet]
    public var workspaces: [Workspace]

    public init(cheets: [Cheet], workspaces: [Workspace] = []) {
        self.cheets = cheets
        self.workspaces = workspaces
    }
}
```

2. Replace the nested `struct LibraryFile: Codable { var version: Int = 1; var cheets: [Cheet] }` with:

```swift
    struct LibraryFile: Codable {
        var version = 2
        var cheets: [Cheet]
        var workspaces: [Workspace]

        init(_ library: Library) {
            cheets = library.cheets
            workspaces = library.workspaces
        }

        private enum CodingKeys: String, CodingKey { case version, cheets, workspaces }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = c.value(.version, or: 1)
            cheets = try c.decode([Cheet].self, forKey: .cheets) // required: this is what makes it a library file
            workspaces = c.value(.workspaces, or: []) // unreadable workspaces must not cost the cheets
        }
    }
```

3. Replace `loadCheets()` and `saveCheets(_:)` with:

```swift
    /// `nil` when no library exists yet (first launch).
    public func loadLibrary() throws -> Library? {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return nil }
        return try Self.decodeLibrary(from: Data(contentsOf: libraryURL))
    }

    /// The cheets alone (read-only convenience; saving always writes the whole library).
    public func loadCheets() throws -> [Cheet]? {
        try loadLibrary()?.cheets
    }

    public func saveLibrary(_ library: Library) throws {
        try ensureDirectory()
        try Self.encodeLibrary(library).write(to: libraryURL, options: .atomic)
    }
```

4. Replace `encodeLibrary(_ cheets:)` and `decodeCheets(from:)` with:

```swift
    public static func encodeLibrary(_ library: Library) throws -> Data {
        try JSONEncoder.cheet.encode(LibraryFile(library))
    }

    /// Accepts a library file (with or without workspaces), a bare array of cheets, or a single cheet.
    public static func decodeLibrary(from data: Data) throws -> Library {
        let data = LegacyKeys.rename(in: data, [["sheets"]: "cheets"])
        let decoder = JSONDecoder.cheet
        if let file = try? decoder.decode(LibraryFile.self, from: data) {
            return Library(cheets: file.cheets, workspaces: file.workspaces)
        }
        if let cheets = try? decoder.decode([Cheet].self, from: data) { return Library(cheets: cheets) }
        return Library(cheets: [try decoder.decode(Cheet.self, from: data)])
    }
```

- [ ] **Step 6: Update the existing storage test**

In `Tests/CheetCoreTests/SupportTests.swift`, `StorageTests.libraryAndSettingsPersist`, replace:

```swift
        try store.saveCheets(cheets)
        #expect(try store.loadCheets() == cheets)
```

with:

```swift
        try store.saveLibrary(Library(cheets: cheets))
        #expect(try store.loadLibrary() == Library(cheets: cheets))
```

And in `ImporterTests.swift` `ownCheetFormatRoundTrips` nothing changes (it uses `encodeCheet`).

- [ ] **Step 7: Run the core tests**

Run: `make test`
Expected: all tests pass, including 11 new ones in `WorkspaceTests` and `LibraryFileTests`.

- [ ] **Step 8: AppModel holds workspaces**

In `Sources/CheetWithBothHands/App/AppModel.swift`:

1. After the `cheets` property add:

```swift
    var workspaces: [Workspace] = [] {
        didSet {
            scheduleSave(.cheets) // workspaces live in library.json with the cheets
            recomputeHotkeys()
        }
    }
```

2. In `init`, replace the `var loaded: [Cheet]? = nil` … `if let loaded { … } else { … }` block with:

```swift
        var loaded: Library? = nil
        do {
            loaded = try store.loadLibrary()
        } catch {
            NSLog("Cheet with Both Hands: failed to read library: \(error)")
        }
        if let loaded {
            cheets = loaded.cheets
            workspaces = loaded.workspaces
        } else {
            cheets = SampleCheets.all()
            isFirstLaunch = !viewState.hasLaunchedBefore
            pendingSaves.insert(.cheets)
        }
```

3. In `delete(_ id:)`, after `cheets.removeAll { $0.id == id }`, add:

```swift
        let remaining = Set(cheets.map(\.id))
        if workspaces.contains(where: { $0.windows.contains { $0.cheetID == id } }) {
            workspaces = workspaces.map { $0.pruned(keeping: remaining) }
        }
```

4. In `flushSaves()`, replace `try store.saveCheets(cheets)` with `try store.saveLibrary(Library(cheets: cheets, workspaces: workspaces))`.

- [ ] **Step 9: Export/Import Library carry workspaces**

In `Sources/CheetWithBothHands/App/AppController.swift`:

1. `exportLibrary()`: replace `LibraryStore.encodeLibrary(model.cheets)` with `LibraryStore.encodeLibrary(Library(cheets: model.cheets, workspaces: model.workspaces))`.
2. `importLibrary()`: replace the body of the `do { … }` with:

```swift
            let incoming = try LibraryStore.decodeLibrary(from: Data(contentsOf: url))
            let existing = Set(model.cheets.map(\.id))
            var renamed: [UUID: UUID] = [:]
            for var cheet in incoming.cheets {
                if existing.contains(cheet.id) {
                    let fresh = UUID()
                    renamed[cheet.id] = fresh
                    cheet.id = fresh
                }
                model.add(cheet)
            }
            let known = Set(model.cheets.map(\.id))
            for var workspace in incoming.workspaces {
                workspace.id = UUID()
                workspace.hotkey = nil // don't steal combos on import
                workspace.windows = workspace.windows.map { var w = $0; w.cheetID = renamed[w.cheetID] ?? w.cheetID; return w }
                model.workspaces.append(workspace.pruned(keeping: known))
            }
            let added = incoming.cheets.count
            showAlert("Imported \(added) cheet\(added == 1 ? "" : "s")", "They've been added to the end of your library.")
```

- [ ] **Step 10: Build and test**

Run: `make test && make app`
Expected: all tests pass; `✓ Built …`.

- [ ] **Step 11: Commit**

```bash
git add Sources/CheetCore Sources/CheetWithBothHands/App/AppModel.swift Sources/CheetWithBothHands/App/AppController.swift Tests/CheetCoreTests
git commit -m "Workspace model, saved in library.json" -m "Library files move to version 2 with a workspaces list beside the cheets; version-1 files, bare arrays and single cheets still load, and unreadable workspaces never cost the cheets. Deleting a cheet removes it from workspaces; export and import carry them." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Split the overlay into CheetWindowController + CheetWindowManager (one window, no behavior change)

**Files:**
- Rename: `Sources/CheetWithBothHands/Overlay/OverlayController.swift` → `Sources/CheetWithBothHands/Overlay/CheetWindowController.swift`
- Create: `Sources/CheetWithBothHands/Overlay/CheetWindowManager.swift`
- Modify: `OverlayView.swift`, `AppController.swift`, `StatusMenuController.swift`, `CheetsPane.swift`, `DebugSnapshots.swift`

**Interfaces:**
- Produces (`CheetWindowController`, one window): `init(model: AppModel, manager: CheetWindowManager)`; `let state: OverlayState`, `let editState: LayoutEditState`; `var cheetID: UUID?`; `var isVisible: Bool`; `var window: NSWindow`; `var frame: NSRect`; `func open(cheetID: UUID?, at frame: NSRect, focus: Bool?)`; `func switchTo(cheetID: UUID)`; `func focus(_ takeFocus: Bool)`; `func close(animated: Bool = true)`; `func setFrame(_ frame: NSRect, animate: Bool, remember: Bool)`; `func applyWindowProperties()`; `func showToast(_:actionTitle:action:)`; `var scrollOffset: CGFloat`; `var outerScroller: NSScroller?`; plus the existing `LayoutEditing` methods and `beginEditing()` / `endEditing()`.
- Produces (`CheetWindowManager`): `init(model: AppModel)`; `private(set) var windows: [CheetWindowController]` (back to front); `var activeWindow: CheetWindowController?`; `var isVisible: Bool`; `func window(showing: UUID) -> CheetWindowController?`; `func isShowing(_: UUID) -> Bool`; `func show(cheetID: UUID, alongside: Bool = false, focus: Bool? = nil)`; `func toggle(cheetID: UUID)`; `func hide()`; `func toggleLast()`; `func hotkeyPressed(cheetID: UUID, alongside: Bool)`; `func hotkeyReleased(cheetID: UUID)`; `func showToast(_:actionTitle:action:)`; `func editLayout(cheetID: UUID)`; `func relayoutIfVisible()`; `func closeWindow(showing: UUID)`; `func presetFrame(for: UUID?) -> NSRect`; `func neighbour(of: UUID?, delta: Int, for: CheetWindowController) -> UUID?`; window callbacks `windowDidBecomeActive(_:)`, `windowWillClose(_:)`, `windowDidFinishClosing(_:)`.
- In this task the manager keeps at most one window, so behavior is unchanged. `alongside` is accepted and ignored until Task 6.

- [ ] **Step 1: Rename the file and class**

```bash
git mv Sources/CheetWithBothHands/Overlay/OverlayController.swift Sources/CheetWithBothHands/Overlay/CheetWindowController.swift
```

In `CheetWindowController.swift`: rename `final class OverlayController` to `final class CheetWindowController`, the extension `extension OverlayController: LayoutEditing` to `extension CheetWindowController: LayoutEditing`, and update the doc comment to "/// One cheet window: shows, positions and animates it, and handles its keyboard, scrolling and layout editing. `CheetWindowManager` decides which windows exist."

In `OverlayPanel`, add a static minimum size and a key flag (the flag is used from Task 8):

```swift
    static let minimumSize = NSSize(width: 360, height: 220)
    /// Stashed windows don't take keyboard focus.
    var acceptsKey = true
    override var canBecomeKey: Bool { acceptsKey }
```

and change `minSize = NSSize(width: 360, height: 220)` to `minSize = Self.minimumSize`.

- [ ] **Step 2: Give the window controller its manager, and move shared concerns out**

In `CheetWindowController`:

1. Add `unowned let manager: CheetWindowManager` after `let model: AppModel`, and change the initializer to `init(model: AppModel, manager: CheetWindowManager)`, assigning `self.manager = manager`.
2. Delete from `init` the whole `model.addSettingsObserver { … }` block (the manager forwards settings changes in step 4).
3. Delete these members (they move to the manager in step 4): `activePress`, `hotkeyPressed(cheetID:)`, `hotkeyReleased(cheetID:)`, `toggle(cheetID:)`, `toggleLast()`, `showEmpty()`, `screenForPresentation()`, `targetFrame(for:)`, `clamp(_:to:)`, `relayoutIfVisible()`, `outsideClickMonitor` and its use in `installMonitors()` / `removeMonitors()` (keep the key monitor), and the `if old.behavior.dismissOnOutsideClick …` logic.
4. Replace `show(cheetID:focus:)`, `present(wasVisible:cheetChanged:focus:)` and `hide(animated:)` with:

```swift
    var cheetID: UUID? { state.cheetID }
    /// The window's frame (Task 8 makes this its home frame while stashed).
    var frame: NSRect { panel.frame }

    /// Loads a cheet into this window, resetting per-cheet state when it changes.
    private func load(_ cheetID: UUID?) {
        guard state.cheetID != cheetID || cheetID == nil else { return }
        state.query = ""
        state.showControls = false
        resetEditHistory()
        editState.selectedID = nil
        state.cheetID = cheetID
        if let cheetID { model.viewState.lastCheetID = cheetID }
    }

    /// Shows the window for the first time with `cheetID` (nil = the empty-library state) at `frame`.
    func open(cheetID: UUID?, at frame: NSRect, focus: Bool?) {
        load(cheetID)
        applyWindowProperties()
        let behavior = model.settings.behavior
        let takeFocus = (focus ?? behavior.takeFocus) && !behavior.ghostMode && !DebugSnapshots.isRequested
        hideGeneration += 1
        let opacity = model.appearance(for: state.cheetID).windowOpacity
        let fade = behavior.fadeDuration
        isAnimatingFrame = true
        panel.setFrame(fade > 0 ? frame.offsetBy(dx: 0, dy: -10) : frame, display: false)
        panel.alphaValue = fade > 0 ? 0 : opacity
        if takeFocus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        state.isVisible = true
        installMonitors()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fade
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = opacity
            if fade > 0 { panel.animator().setFrame(frame, display: true) }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isAnimatingFrame = false
                self?.panel.invalidateShadow()
            }
        })
        if takeFocus { state.focusSearchRequest += 1 }
    }

    /// Swaps this window's cheet in place (header menu, ⌘[ ], ⇧←/⇧→, ⌘1–9).
    func switchTo(cheetID: UUID) {
        guard model.cheet(id: cheetID) != nil, cheetID != state.cheetID else { return }
        if let owner = manager.window(showing: cheetID), owner !== self {
            manager.show(cheetID: cheetID) // already open elsewhere: bring that window forward
            return
        }
        load(cheetID)
        applyWindowProperties()
        let layout = model.settings.layout
        if layout.perCheetFrames, layout.rememberFrame {
            setFrame(manager.presetFrame(for: cheetID), animate: true, remember: false)
        }
    }

    /// Brings the window forward, optionally taking keyboard focus for filtering.
    func focus(_ takeFocus: Bool) {
        let behavior = model.settings.behavior
        if takeFocus, !behavior.ghostMode, !DebugSnapshots.isRequested {
            panel.makeKeyAndOrderFront(nil)
            if !editState.isEditing { state.focusSearchRequest += 1 }
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Fades the window out and closes it. The manager forgets it straight away.
    func close(animated: Bool = true) {
        guard state.isVisible else { return }
        if editState.isEditing { endEditing() }
        state.isVisible = false
        state.showControls = false
        hideGeneration += 1
        let generation = hideGeneration
        removeMonitors()
        flushFrameSave()
        manager.windowWillClose(self)
        let fade = animated ? model.settings.behavior.fadeDuration : 0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fade
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.manager.windowDidFinishClosing(self)
            }
        })
    }
```

5. Replace the private `setFrame(_:animate:)` with a version that can skip remembering:

```swift
    /// Moves the window. `remember` saves the result as a remembered position (like a user drag).
    func setFrame(_ frame: NSRect, animate: Bool, remember: Bool) {
        if remember { userAdjustedFrame = true }
        isAnimatingFrame = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animate ? 0.25 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isAnimatingFrame = false
                self.panel.invalidateShadow()
                if remember { self.saveFrame() }
            }
        })
    }
```

Update `resetFrame()` to end with `setFrame(manager.presetFrame(for: state.cheetID), animate: true, remember: false)`.

6. Change `step(_ delta:)` and `select(index:)` to use the manager, and route closing keys to `close()`:

```swift
    func step(_ delta: Int) {
        if let next = manager.neighbour(of: state.cheetID, delta: delta, for: self) { switchTo(cheetID: next) }
    }

    func select(index: Int) {
        guard model.cheets.indices.contains(index) else { NSSound.beep(); return }
        switchTo(cheetID: model.cheets[index].id)
    }
```

In `handleEscape()` replace `hide()` with `close()`. In `handleKey`, the `case "w", "q", "h":` branch calls `close()` instead of `hide()`.

7. Add NSWindowDelegate focus tracking next to the other delegate methods:

```swift
    func windowDidBecomeKey(_ notification: Notification) { manager.windowDidBecomeActive(self) }
```

8. Leave `openPicker`, `openSettings`, `newCheet` and `editCheet` unchanged (they call `AppController.shared`). Delete `editLayout(cheetID:)` from this class (the manager's version replaces it in step 4); keep `beginEditing()`.

- [ ] **Step 3: Point the views at the window controller**

In `Sources/CheetWithBothHands/Overlay/OverlayView.swift`, change `let controller: OverlayController` to `let controller: CheetWindowController`. In `cheetMenu`, change `controller.show(cheetID: item.id)` to `controller.switchTo(cheetID: item.id)`. In the header's close button change `controller.hide()` to `controller.close()`.

- [ ] **Step 4: Create the manager (single window)**

Create `Sources/CheetWithBothHands/Overlay/CheetWindowManager.swift`:

```swift
import AppKit
import CheetCore

/// Owns every cheet window: which one is active, where new ones open, what cheet hotkeys do, hiding
/// and bringing back the whole set. (Tiling, stashing and workspaces arrive in later changes.)
@MainActor
final class CheetWindowManager {
    let model: AppModel
    /// Visible cheet windows, back to front; the last is the active window.
    private(set) var windows: [CheetWindowController] = []
    /// Windows fading out, kept alive until their animation finishes.
    private var closing: [CheetWindowController] = []
    private var outsideClickMonitor: Any?

    // Single-window hotkey state, as in the old OverlayController (replaced in the next change).
    private var activePress: (cheetID: UUID, time: Date, hidOnPress: Bool)?

    init(model: AppModel) {
        self.model = model
        model.addSettingsObserver { [weak self] old, new in
            guard let self else { return }
            for window in self.windows { window.applyWindowProperties() }
            if old.layout != new.layout { self.relayoutIfVisible() }
            if old.behavior.dismissOnOutsideClick != new.behavior.dismissOnOutsideClick { self.updateOutsideClickMonitor() }
        }
    }

    var isVisible: Bool { !windows.isEmpty }
    var activeWindow: CheetWindowController? { windows.last }
    func window(showing cheetID: UUID) -> CheetWindowController? { windows.first { $0.cheetID == cheetID } }
    func isShowing(_ cheetID: UUID) -> Bool { window(showing: cheetID) != nil }

    // MARK: Showing

    func show(cheetID: UUID, alongside: Bool = false, focus: Bool? = nil) {
        guard model.cheet(id: cheetID) != nil else { return }
        if let active = activeWindow {
            active.switchTo(cheetID: cheetID)
            active.focus(focus ?? model.settings.behavior.takeFocus)
        } else {
            open(cheetID, at: presetFrame(for: cheetID), focus: focus)
        }
    }

    func toggle(cheetID: UUID) {
        if isShowing(cheetID) { hide() } else { show(cheetID: cheetID) }
    }

    func hide() {
        for window in windows { window.close() }
    }

    func toggleLast() {
        if isVisible { hide(); return }
        if let id = model.cheet(id: model.viewState.lastCheetID)?.id ?? model.cheets.first?.id {
            show(cheetID: id)
        } else {
            open(nil, at: presetFrame(for: nil), focus: true)
        }
    }

    func closeWindow(showing cheetID: UUID) { window(showing: cheetID)?.close() }

    func editLayout(cheetID: UUID) {
        show(cheetID: cheetID, focus: true)
        window(showing: cheetID)?.beginEditing()
    }

    func showToast(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        activeWindow?.showToast(message, actionTitle: actionTitle, action: action)
    }

    func relayoutIfVisible() {
        guard let active = activeWindow else { return }
        active.setFrame(presetFrame(for: active.cheetID), animate: true, remember: false)
    }

    @discardableResult
    private func open(_ cheetID: UUID?, at frame: NSRect, focus: Bool?) -> CheetWindowController {
        let window = CheetWindowController(model: model, manager: self)
        windows.append(window)
        window.open(cheetID: cheetID, at: frame, focus: focus)
        updateOutsideClickMonitor()
        return window
    }

    // MARK: Hotkeys (today's single-window behavior)

    func hotkeyPressed(cheetID: UUID, alongside: Bool) {
        guard activePress?.cheetID != cheetID else { return } // ignore key repeat
        let sameCheetVisible = isShowing(cheetID)
        switch model.settings.behavior.trigger {
        case .toggle, .smart:
            if sameCheetVisible { hide() } else { show(cheetID: cheetID) }
            activePress = (cheetID, Date(), sameCheetVisible)
        case .hold:
            show(cheetID: cheetID, focus: false)
            activePress = (cheetID, Date(), false)
        }
    }

    func hotkeyReleased(cheetID: UUID) {
        guard let press = activePress, press.cheetID == cheetID else { return }
        activePress = nil
        let held = Date().timeIntervalSince(press.time)
        switch model.settings.behavior.trigger {
        case .toggle: break
        case .hold: if isShowing(cheetID) { hide() }
        case .smart:
            if !press.hidOnPress, held >= model.settings.behavior.holdThreshold, isShowing(cheetID) { hide() }
        }
    }

    // MARK: Window callbacks

    func windowDidBecomeActive(_ window: CheetWindowController) {
        guard let index = windows.firstIndex(where: { $0 === window }), index != windows.count - 1 else { return }
        windows.append(windows.remove(at: index))
        if let id = window.cheetID { model.viewState.lastCheetID = id }
    }

    func windowWillClose(_ window: CheetWindowController) {
        windows.removeAll { $0 === window }
        closing.append(window)
        if windows.isEmpty { activePress = nil }
        updateOutsideClickMonitor()
    }

    func windowDidFinishClosing(_ window: CheetWindowController) {
        closing.removeAll { $0 === window }
    }

    /// The next cheet in the library from `cheetID`, skipping cheets open in other windows.
    func neighbour(of cheetID: UUID?, delta: Int, for window: CheetWindowController) -> UUID? {
        let cheets = model.cheets
        guard !cheets.isEmpty else { return nil }
        var index = model.index(of: cheetID) ?? 0
        for _ in 0..<cheets.count {
            index = (index + delta + cheets.count) % cheets.count
            let candidate = cheets[index].id
            if candidate == cheetID { return nil }
            if let owner = self.window(showing: candidate), owner !== window { continue }
            return candidate
        }
        return nil
    }

    // MARK: Placement (moved from OverlayController)

    func screenForPresentation() -> NSScreen {
        switch model.settings.layout.screen {
        case .mouse:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        case .focused:
            return NSScreen.main ?? NSScreen.screens[0]
        case .primary:
            return NSScreen.screens.first ?? NSScreen.main!
        }
    }

    /// A cheet's remembered frame (global or per cheet) or the preset from Position & Size.
    func presetFrame(for cheetID: UUID?) -> NSRect {
        let visible = screenForPresentation().visibleFrame
        let layout = model.settings.layout
        let minSize = OverlayPanel.minimumSize
        if layout.rememberFrame {
            let saved = layout.perCheetFrames ? cheetID.flatMap { model.viewState[cheet: $0].frame } : model.viewState.globalFrame
            if let saved { return saved.denormalized(in: visible).clamped(to: visible, minSize: minSize) }
        }
        let margin = CGFloat(layout.margin)
        let width = min(max(minSize.width, visible.width * layout.widthFraction), visible.width - 2 * margin)
        let height = min(max(minSize.height, visible.height * layout.heightFraction), visible.height - 2 * margin)
        let unit = layout.anchor.unitPosition
        let x = visible.minX + margin + (visible.width - 2 * margin - width) * unit.x
        let y = visible.minY + margin + (visible.height - 2 * margin - height) * unit.y
        return NSRect(x: x, y: y, width: width, height: height).integral
    }

    // MARK: Hide on outside click

    private func updateOutsideClickMonitor() {
        let wanted = model.settings.behavior.dismissOnOutsideClick && !windows.isEmpty
        if wanted, outsideClickMonitor == nil {
            // Global monitors only see clicks in other apps, so clicks in any cheet window don't count.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.windows.contains(where: { $0.editState.isEditing }) else { return }
                    self.hide()
                }
            }
        } else if !wanted, let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}
```

- [ ] **Step 5: Wire the app to the manager**

1. `AppController.swift`: change `let overlay: OverlayController` to `let overlay: CheetWindowManager` and `overlay = OverlayController(model: model)` to `overlay = CheetWindowManager(model: model)`. In `handlePress`, `.showCheet(let id)` calls `overlay.hotkeyPressed(cheetID: id, alongside: false)`.
2. `StatusMenuController.swift`: `item.state = overlay.isVisible && overlay.state.cheetID == cheet.id ? .on : .off` becomes `item.state = overlay.isShowing(cheet.id) ? .on : .off`.
3. `CheetsPane.swift`: `if AppController.shared.overlay.state.cheetID == id { AppController.shared.overlay.hide() }` becomes `AppController.shared.overlay.closeWindow(showing: id)`.
4. `DebugSnapshots.swift`: window-level members move to the active window. Replace (in this order, so the longer patterns match first):
   - `overlay.window.windowNumber` → `overlay.activeWindow!.window.windowNumber`
   - `overlay.window.setFrame` → `overlay.activeWindow!.window.setFrame`
   - `overlay.outerScroller` → `overlay.activeWindow!.outerScroller`
   - `overlay.window` → `overlay.activeWindow!.window` (remaining uses)
   - `overlay.scrollOffset` → `overlay.activeWindow!.scrollOffset`
   - `overlay.state.` → `overlay.activeWindow!.state.`
   - `overlay.beginEditing()`, `overlay.endEditing()`, `overlay.select(`, `overlay.setLiveResize(`, `overlay.commitResize()` → prefix with `overlay.activeWindow!.`
   - `overlay.hide(animated: false)` → `overlay.hide()`

   The snapshot run reads `overlay.activeWindow!.window` right after `overlay.show(...)`, which is fine because `open` appends the window synchronously.

- [ ] **Step 6: Build and run the regression snapshot**

Run:

```bash
make app && SP=$(mktemp -d) && (CWBH_DATA_DIR=$SP/data CWBH_SNAPSHOT_DIR=$SP/shots "build/Cheet with Both Hands.app/Contents/MacOS/CheetWithBothHands" > $SP/log 2>&1); grep -E 'keyboard scroll|stepping|scroller' $SP/log; ls $SP/shots | wc -l
```

Expected: the same lines as before the split — `keyboard scroll: start 0 → ↓ 41 → …`, `cheet stepping: start 1 → ⇧→ 2 → ⇧← 1 → ⇧← 4`, `outer scroller: HairlineScroller` — and the same number of snapshots (≥ 20).

- [ ] **Step 7: Manual check**

`make run`, then: tap ⌃⌥⌘1 (shows), tap again (hides); hold ⌃⌥⌘2 (peeks, hides on release); ⌘] steps; Esc clears then closes; ⌃⌥⌘\` toggles; Settings › Cheets › Show / Edit Layout.

- [ ] **Step 8: Commit**

```bash
git add -A Sources/CheetWithBothHands
git commit -m "Split the overlay into window controllers and a window manager" -m "OverlayController becomes CheetWindowController (one window) and CheetWindowManager (which windows exist, hotkeys, placement, hide/toggle last, outside clicks). Still one window at a time; behavior is unchanged. This is the groundwork for multiple cheet windows." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Multiple windows — replace by default, Shift for alongside

**Files:**
- Modify: `Sources/CheetCore/Models/Settings.swift` (`HotkeySettings.shiftForAlongside`)
- Modify: `Sources/CheetCore/Support/HotkeyResolver.swift` (`.showCheetAlongside`)
- Modify: `Tests/CheetCoreTests/SupportTests.swift` (resolver tests)
- Modify: `CheetWindowManager.swift`, `AppController.swift`, `AppDelegate.swift` (URLCommands), `PickerController.swift`, `StatusMenuController.swift`, `SettingsView.swift`, `DebugSnapshots.swift`

**Interfaces:**
- Consumes: `PressDecision` (Task 1).
- Produces: `HotkeyAction.showCheetAlongside(UUID)`; `HotkeySettings.shiftForAlongside: Bool = true`; `CheetWindowManager.newWindowFrame(for: UUID?) -> NSRect`; `PickerController.onChoose: ((UUID, _ alongside: Bool) -> Void)?`.

- [ ] **Step 1: Write the failing resolver tests**

Append to `HotkeyResolverTests` in `Tests/CheetCoreTests/SupportTests.swift`:

```swift
    @Test func shiftVariantsOpenCheetsAlongside() {
        let list = cheets(2)
        let plan = HotkeyResolver.resolve(cheets: list, settings: HotkeySettings())
        let alongside = plan.combo(for: .showCheetAlongside(list[0].id))
        #expect(alongside == KeyCombo(keyCode: KeyCodes.one, modifiers: [.control, .option, .command, .shift]))
    }

    @Test func noShiftVariantWhenTheComboAlreadyHasShift() {
        var list = cheets(1)
        list[0].hotkey = .custom(KeyCombo(keyCode: KeyCodes.k, modifiers: [.command, .shift]))
        let plan = HotkeyResolver.resolve(cheets: list, settings: HotkeySettings())
        #expect(plan.combo(for: .showCheetAlongside(list[0].id)) == nil)
        #expect(plan.conflicts[.showCheetAlongside(list[0].id)] == nil)
    }

    @Test func shiftVariantsLoseToEverythingElse() {
        var list = cheets(2)
        // Cheet 2's custom combo is exactly cheet 1's Shift variant.
        list[1].hotkey = .custom(KeyCombo(keyCode: KeyCodes.one, modifiers: [.control, .option, .command, .shift]))
        let plan = HotkeyResolver.resolve(cheets: list, settings: HotkeySettings())
        #expect(plan.cheetCombos[list[1].id]?.keyCode == KeyCodes.one)
        #expect(plan.conflicts[.showCheetAlongside(list[0].id)] != nil)
    }

    @Test func shiftVariantsCanBeTurnedOff() {
        var settings = HotkeySettings()
        settings.shiftForAlongside = false
        let list = cheets(1)
        #expect(HotkeyResolver.resolve(cheets: list, settings: settings).combo(for: .showCheetAlongside(list[0].id)) == nil)
    }
```

Run: `make test FILTER=HotkeyResolverTests` — Expected: build failure, "type 'HotkeyAction' has no member 'showCheetAlongside'".

- [ ] **Step 2: Implement in CheetCore**

`Sources/CheetCore/Models/Settings.swift`, in `HotkeySettings` after `ghostMode`:

```swift
    /// Register each cheet's combo plus ⇧ to open it alongside the windows already showing.
    public var shiftForAlongside = true
```

`Sources/CheetCore/Support/HotkeyResolver.swift`: add the case to `HotkeyAction`:

```swift
    case showCheetAlongside(UUID)
```

and at the end of `resolve`, before `return plan`:

```swift
        // Lowest priority: ⇧ variants of every cheet combo that won, for "open alongside".
        if settings.shiftForAlongside {
            for cheet in cheets {
                guard let combo = plan.cheetCombos[cheet.id], !combo.modifiers.contains(.shift) else { continue }
                claim(KeyCombo(keyCode: combo.keyCode, modifiers: combo.modifiers.union(.shift)), for: .showCheetAlongside(cheet.id))
            }
        }
```

Run: `make test FILTER=HotkeyResolverTests` — Expected: all resolver tests pass.

- [ ] **Step 3: Multi-window showing and hotkeys in the manager**

In `CheetWindowManager.swift`:

1. Delete `activePress` and replace the `// MARK: Hotkeys` section (both methods) with:

```swift
    // MARK: Hotkeys

    /// A press waiting for its release to learn whether it was a tap or a hold.
    private struct PendingPress {
        var cheetID: UUID
        var time: Date
        var action: PressDecision.OnPress
        weak var opened: CheetWindowController?
        weak var replaced: CheetWindowController?
    }
    private var pendingPress: PendingPress?

    func hotkeyPressed(cheetID: UUID, alongside: Bool) {
        guard pendingPress?.cheetID != cheetID, model.cheet(id: cheetID) != nil else { return } // ignore key repeat
        hiddenSet = []
        let situation: PressDecision.Situation = isShowing(cheetID) ? .cheetVisible : (windows.isEmpty ? .noWindows : .othersVisible)
        let action = PressDecision.onPress(situation, alongside: alongside)
        let focus = model.settings.behavior.trigger != .hold
        var press = PendingPress(cheetID: cheetID, time: Date(), action: action)
        switch action {
        case .close:
            window(showing: cheetID)?.close()
        case .open:
            press.opened = open(cheetID, at: newWindowFrame(for: cheetID), focus: focus)
        case .openOver:
            press.replaced = activeWindow
            press.opened = open(cheetID, at: activeWindow?.frame ?? newWindowFrame(for: cheetID), focus: focus)
        }
        pendingPress = press
    }

    func hotkeyReleased(cheetID: UUID) {
        guard let press = pendingPress, press.cheetID == cheetID else { return }
        pendingPress = nil
        let behavior = model.settings.behavior
        let release = PressDecision.onRelease(after: press.action, trigger: behavior.trigger,
                                              heldFor: Date().timeIntervalSince(press.time), holdThreshold: behavior.holdThreshold)
        switch release {
        case .nothing: break
        case .closeOpened: press.opened?.close()
        case .closeReplaced: press.replaced?.close()
        }
    }
```

2. Replace `show(cheetID:alongside:focus:)`, `toggle`, `hide`, `toggleLast` with:

```swift
    /// A cheet shown from the picker, menus, Settings or a URL: replaces the active window's cheet,
    /// or opens alongside. A cheet that's already open just comes forward.
    func show(cheetID: UUID, alongside: Bool = false, focus: Bool? = nil) {
        guard model.cheet(id: cheetID) != nil else { return }
        hiddenSet = []
        if let existing = window(showing: cheetID) {
            existing.focus(focus ?? model.settings.behavior.takeFocus)
            windowDidBecomeActive(existing)
        } else if alongside || windows.isEmpty {
            open(cheetID, at: newWindowFrame(for: cheetID), focus: focus)
        } else if let active = activeWindow {
            open(cheetID, at: active.frame, focus: focus)
            active.close() // cross-fades under the new window
        }
    }

    func toggle(cheetID: UUID) {
        if let existing = window(showing: cheetID) { existing.close() } else { show(cheetID: cheetID) }
    }

    /// A window closed by "hide all", remembered for toggle last.
    private struct HiddenWindow { var cheetID: UUID?; var frame: NSRect; var query: String }
    /// The set toggle last brings back: the last hide-all, or the last window closed on its own.
    private var hiddenSet: [HiddenWindow] = []
    private var isHidingAll = false

    /// Closes every cheet window, remembering them for toggle last.
    func hide() {
        guard !windows.isEmpty else { return }
        hiddenSet = windows.map { HiddenWindow(cheetID: $0.cheetID, frame: $0.frame, query: $0.state.query) }
        isHidingAll = true
        for window in windows { window.close() }
        isHidingAll = false
    }

    func toggleLast() {
        if isVisible { hide(); return }
        let set = hiddenSet.filter { $0.cheetID.map { model.cheet(id: $0) != nil } ?? true }
        hiddenSet = []
        if !set.isEmpty {
            for item in set {
                open(item.cheetID, at: item.frame, focus: false).state.query = item.query
            }
            activeWindow?.focus(model.settings.behavior.takeFocus)
        } else if let id = model.cheet(id: model.viewState.lastCheetID)?.id ?? model.cheets.first?.id {
            show(cheetID: id)
        } else {
            open(nil, at: presetFrame(for: nil), focus: true) // the empty-library state
        }
    }

    /// Where a new window goes: the cheet's own remembered frame (per-cheet positions), the preset
    /// frame when it's the only window, otherwise offset from the active window.
    func newWindowFrame(for cheetID: UUID?) -> NSRect {
        let layout = model.settings.layout
        if layout.rememberFrame, layout.perCheetFrames, let id = cheetID, model.viewState[cheet: id].frame != nil {
            return presetFrame(for: id)
        }
        guard let active = activeWindow, let screen = active.window.screen ?? NSScreen.main else { return presetFrame(for: cheetID) }
        return active.frame.offsetBy(dx: 28, dy: -28).clamped(to: screen.visibleFrame, minSize: OverlayPanel.minimumSize)
    }
```

3. In `windowWillClose(_:)`, before `windows.removeAll`, remember a window closed on its own so toggle last can bring it back:

```swift
        if !isHidingAll, windows.count == 1, windows.first === window {
            hiddenSet = [HiddenWindow(cheetID: window.cheetID, frame: window.frame, query: window.state.query)]
        }
```

and change `if windows.isEmpty { activePress = nil }` to `if windows.isEmpty { pendingPress = nil }`.

- [ ] **Step 4: Route the alongside hotkey and the URL flag**

`AppController.swift` `handlePress`:

```swift
        case .showCheet(let id):
            if picker.isVisible { picker.hide() }
            overlay.hotkeyPressed(cheetID: id, alongside: false)
        case .showCheetAlongside(let id):
            if picker.isVisible { picker.hide() }
            overlay.hotkeyPressed(cheetID: id, alongside: true)
```

`handleRelease`:

```swift
        switch action {
        case .showCheet(let id), .showCheetAlongside(let id): overlay.hotkeyReleased(cheetID: id)
        default: break
        }
```

`AppDelegate.swift` (`URLCommands.handle`), `case "show", "open":`

```swift
        case "show", "open":
            let alongside = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .contains { $0.name == "alongside" && $0.value != "0" } ?? false
            if let target { controller.overlay.show(cheetID: target.id, alongside: alongside) } else { controller.overlay.toggleLast() }
```

and in the same function change the argument parsing so the query string doesn't become part of the title: the existing `argument` uses `url.pathComponents`, which already excludes the query — no change needed. Update the doc comment above `URLCommands` to mention `show/2?alongside=1`.

- [ ] **Step 5: Picker — ⇧Return and ⇧-click open alongside**

`PickerController.swift`:

1. `var onChoose: ((UUID) -> Void)?` → `var onChoose: ((UUID, _ alongside: Bool) -> Void)?`.
2. Replace `choose(_:)` and `chooseSelection()`:

```swift
    func choose(_ id: UUID, alongside: Bool = false) {
        hide()
        onChoose?(id, alongside)
    }

    func chooseSelection(alongside: Bool = false) {
        let list = results()
        guard list.indices.contains(state.selection) else { NSSound.beep(); return }
        choose(list[state.selection].cheet.id, alongside: alongside)
    }
```

3. In `installMonitors`, the Return case becomes `self.chooseSelection(alongside: event.modifierFlags.contains(.shift))`.
4. In `PickerView`, the row's tap: `.onTapGesture { controller.choose(item.cheet.id, alongside: NSEvent.modifierFlags.contains(.shift)) }`.
5. In the footer, after `Label("open", systemImage: "return")` add `Label("alongside", systemImage: "shift")`.

`AppController.start()`: `picker.onChoose = { [weak self] id, alongside in self?.overlay.show(cheetID: id, alongside: alongside) }`.

- [ ] **Step 6: Menu bar — Shift alternates**

`StatusMenuController.swift` in `rebuild()`, replace the loop bodies that add cheet items with a helper that adds the item and its alternate:

```swift
        func addCheetItems(index: Int, cheet: Cheet, to menu: NSMenu) {
            let item = cheetItem(index: index, cheet: cheet)
            menu.addItem(item)
            // Holding ⇧ swaps in "Open … Alongside" (same key, plus ⇧). Not for a cheet that's already
            // open, or whose combo already uses ⇧ (an alternate must differ only by modifiers).
            guard !item.keyEquivalentModifierMask.contains(.shift), !overlay.isShowing(cheet.id) else { return }
            let alternate = ActionMenuItem("Open \(cheet.title) Alongside", modifiers: []) { [weak controller] in
                controller?.overlay.show(cheetID: cheet.id, alongside: true)
            }
            alternate.keyEquivalent = item.keyEquivalent
            alternate.keyEquivalentModifierMask = item.keyEquivalentModifierMask.union(.shift)
            alternate.isAlternate = true
            menu.addItem(alternate)
        }
```

and call `addCheetItems(index: index, cheet: cheet, to: menu)` / `addCheetItems(index: index, cheet: cheet, to: submenu)` where `menu.addItem(cheetItem(…))` / `submenu.addItem(cheetItem(…))` were. Rename "Hide Overlay" to "Hide Cheet Windows".

- [ ] **Step 7: Settings — the Shift toggle and per-cheet alongside status**

`SettingsView.swift`:

1. In `HotkeysPane`, after the "Number shortcuts" section add:

```swift
            Section("Opening alongside") {
                Toggle("Add ⇧ to a cheet's shortcut to open it alongside the cheets already showing", isOn: hotkeys.shiftForAlongside)
                Text("Without ⇧, a cheet's shortcut replaces the cheet in the active window. In the picker, ⇧↩ opens alongside.")
                    .font(.caption).foregroundStyle(.secondary)
            }
```

2. In `CheetHotkeyEditor.body`, after the existing `HotkeyStatusBadge(…)` add:

```swift
            if model.settings.hotkeys.shiftForAlongside {
                if let alongside = model.hotkeyPlan.combo(for: .showCheetAlongside(cheet.id)) {
                    Text(alongside.displayString).font(.caption).foregroundStyle(.tertiary).help("Opens alongside")
                }
                HotkeyStatusBadge(model: model, action: .showCheetAlongside(cheet.id), requested: nil)
            }
```

3. In `HotkeyStatusBadge.owner(of:)` add:

```swift
        case .showCheetAlongside(let id): return "“\(model.cheet(id: id)?.title ?? "a cheet")” (alongside)"
```

- [ ] **Step 8: Snapshot check for alongside, replace and key repeat**

In `DebugSnapshots.swift`, after the cheet-stepping block (before `overlay.hide()`), add:

```swift
                // Several windows: alongside adds, a plain tap replaces, key repeat doesn't duplicate.
                if controller.model.cheets.count >= 3 {
                    let ids = controller.model.cheets.prefix(3).map(\.id)
                    overlay.hide()
                    await pause(0.3)
                    overlay.hotkeyPressed(cheetID: ids[0], alongside: false); overlay.hotkeyReleased(cheetID: ids[0])
                    overlay.hotkeyPressed(cheetID: ids[1], alongside: true)
                    overlay.hotkeyPressed(cheetID: ids[1], alongside: true) // auto-repeat
                    overlay.hotkeyReleased(cheetID: ids[1])
                    await pause(0.4)
                    print("alongside: \(overlay.windows.count) windows")
                    overlay.hotkeyPressed(cheetID: ids[2], alongside: false); overlay.hotkeyReleased(cheetID: ids[2])
                    await pause(0.4)
                    let open = overlay.windows.compactMap(\.cheetID).map { id in controller.model.index(of: id).map { $0 + 1 } ?? 0 }
                    print("replace: \(overlay.windows.count) windows showing cheets \(open)")
                    overlay.hide()
                    await pause(0.3)
                }
```

Note the snapshot run's trigger mode is the default smart mode and presses are released immediately, so they count as taps.

- [ ] **Step 9: Build, test, run the snapshot**

Run:

```bash
make test && make app && SP=$(mktemp -d) && (CWBH_DATA_DIR=$SP/data CWBH_SNAPSHOT_DIR=$SP/shots "build/Cheet with Both Hands.app/Contents/MacOS/CheetWithBothHands" > $SP/log 2>&1); grep -E 'alongside:|replace:|stepping' $SP/log
```

Expected:

```
cheet stepping: start 1 → ⇧→ 2 → ⇧← 1 → ⇧← 4
alongside: 2 windows
replace: 2 windows showing cheets [1, 3]
```

(Cheet 2 was active, so tapping cheet 3 replaced it.)

- [ ] **Step 10: Manual check**

`make run`: tap ⌃⌥⌘1, then ⌃⌥⌘⇧2 → two windows; tap ⌃⌥⌘3 → replaces the focused one; hold ⌃⌥⌘4 → peeks over the active window and the old one is intact on release; ⌃⌥⌘\` hides both and brings both back; picker ⇧↩ opens alongside; menu bar with ⇧ held shows "Open … Alongside".

- [ ] **Step 11: Commit**

```bash
git add -A Sources Tests
git commit -m "Several cheet windows: replace by default, Shift for alongside" -m "Cheet hotkeys replace the active window's cheet, and the same combo plus ⇧ opens a cheet alongside. Tap vs hold is decided on release, so a hold peeks over the active window without disturbing it. Toggle last hides and restores the whole set. The picker (⇧↩, ⇧-click), menu bar (⇧ alternates) and URL scheme (?alongside=1) can open alongside too." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Tiling

**Files:**
- Modify: `Settings.swift` (`HotkeySettings.tile`), `HotkeyResolver.swift` (`.tileWindows`), `SupportTests.swift`
- Modify: `CheetWindowManager.swift`, `CheetWindowController.swift` (⌥⌘T), `OverlayView.swift` (header menu), `StatusMenuController.swift`, `AppController.swift`, `SettingsView.swift`

**Interfaces:**
- Consumes: `TileLayout.tile` (Task 2), `CheetWindowController.setFrame(_:animate:remember:)` (Task 5).
- Produces: `HotkeyAction.tileWindows`; `HotkeySettings.tile: KeyCombo? = nil`; `CheetWindowManager.tile()`.

- [ ] **Step 1: Failing resolver test**

Append to `HotkeyResolverTests`:

```swift
    @Test func tileAndStashAreGlobalActionsThatBeatCheets() {
        var settings = HotkeySettings()
        settings.tile = KeyCombo(keyCode: KeyCodes.one, modifiers: [.control, .option, .command])
        let list = cheets(1)
        let plan = HotkeyResolver.resolve(cheets: list, settings: settings)
        #expect(plan.combo(for: .tileWindows) == settings.tile)
        #expect(plan.conflicts[.showCheet(list[0].id)] != nil)
    }
```

Run: `make test FILTER=HotkeyResolverTests` — Expected: build failure, no member `tile`.

- [ ] **Step 2: Implement in CheetCore**

`HotkeySettings`: `public var tile: KeyCombo? = nil` (after `ghostMode`). `HotkeyAction`: `case tileWindows`. In `resolve`, after `claim(settings.toggleLast, for: .toggleLastCheet)` add `claim(settings.tile, for: .tileWindows)`.

Run: `make test FILTER=HotkeyResolverTests` — Expected: pass.

- [ ] **Step 3: Manager tiling**

Add to `CheetWindowManager`:

```swift
    // MARK: Tiling

    /// Tiles the visible windows onto the active window's screen, keeping their reading order.
    func tile() {
        guard let active = activeWindow, let screen = active.window.screen ?? NSScreen.main else { return }
        let margin = CGFloat(model.settings.layout.margin)
        let container = screen.visibleFrame.insetBy(dx: margin, dy: margin)
        let frames = TileLayout.tile(windows.map(\.frame), in: container, gap: 12, minWidth: OverlayPanel.minimumSize.width)
        for (window, frame) in zip(windows, frames) {
            window.setFrame(frame, animate: true, remember: true)
        }
    }
```

- [ ] **Step 4: Entry points**

1. `CheetWindowController.handleKey`, inside `if flags == [.command, .option] { … }` add:

```swift
            if keyCode == KeyCodes.t { manager.tile(); return true } // ⌥⌘T
```

2. `OverlayView.swift` `cheetMenu`, after `Button("Edit Layout")` add `Button("Tile Cheet Windows") { controller.manager.tile() }`.
3. `StatusMenuController.rebuild()`, after the ghost item:

```swift
        let tile = ActionMenuItem("Tile Cheet Windows", modifiers: []) { [weak controller] in controller?.overlay.tile() }
        tile.isEnabled = overlay.windows.count > 1
        apply(model.hotkeyPlan.combo(for: .tileWindows), to: tile)
        menu.addItem(tile)
```

4. `AppController.handlePress`: `case .tileWindows: overlay.tile()`.
5. `SettingsView` `HotkeysPane` "Global actions": `LabeledContent("Tile cheet windows") { globalRecorder(hotkeys.tile, action: .tileWindows) }`; `owner(of:)`: `case .tileWindows: return "tile cheet windows"`.

- [ ] **Step 5: Snapshot check**

In the Task 6 snapshot block, before its final `overlay.hide()`, add:

```swift
                    overlay.show(cheetID: ids[1], alongside: true, focus: false)
                    await pause(0.4)
                    overlay.tile()
                    await pause(0.5)
                    func frames() -> String {
                        overlay.windows.map { w in "\(Int(w.frame.minX)),\(Int(w.frame.minY)) \(Int(w.frame.width))×\(Int(w.frame.height))" }.joined(separator: " | ")
                    }
                    print("tiled: \(frames())")
                    for (index, window) in overlay.windows.enumerated() { shot(window.window, "tiled-\(index + 1)") }
```

- [ ] **Step 6: Build, test, run**

Run: `make test && make app`, then the snapshot command from Task 6 Step 9 with `grep 'tiled:'`.
Expected: `tiled:` shows 3 frames with equal widths, the same `minY` and height, and x positions 12pt apart (e.g. `24,… 454×… | 490,… 454×… | 956,… 454×…` on a 1440-wide screen with the default 24pt margin).

- [ ] **Step 7: Commit**

```bash
git add -A Sources Tests
git commit -m "Tile cheet windows" -m "⌥⌘T, the header menu, the menu bar or an optional global hotkey tiles the visible windows onto the active window's screen: columns up to three, a grid beyond, reading order kept. Tiled frames are remembered like a drag." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Stashing

**Files:**
- Modify: `Settings.swift` (`HotkeySettings.stash`), `HotkeyResolver.swift` (`.stashWindows`), `SupportTests.swift`
- Modify: `CheetWindowController.swift`, `OverlayView.swift` (`OverlayState.isStashed`, sliver click), `CheetWindowManager.swift`, `StatusMenuController.swift`, `AppController.swift`, `SettingsView.swift`, `DebugSnapshots.swift`

**Interfaces:**
- Consumes: `StashGeometry.stash` (Task 3), `OverlayPanel.acceptsKey` (Task 5).
- Produces: `HotkeyAction.stashWindows`; `HotkeySettings.stash: KeyCombo? = ⌃⌥⌘H`; `CheetWindowController.isStashed`, `homeFrame`, `stash(to:)`, `unstash(to:)`; `CheetWindowManager.isStashed`, `toggleStash()`, `stash()`, `unstash()`.

- [ ] **Step 1: Failing resolver test**

Append to `HotkeyResolverTests`:

```swift
    @Test func stashDefaultsToControlOptionCommandH() {
        let plan = HotkeyResolver.resolve(cheets: [], settings: HotkeySettings())
        #expect(plan.combo(for: .stashWindows) == KeyCombo(keyCode: KeyCodes.h, modifiers: [.control, .option, .command]))
    }
```

Run: `make test FILTER=HotkeyResolverTests` — Expected: build failure.

- [ ] **Step 2: Implement in CheetCore**

`HotkeySettings`: `public var stash: KeyCombo? = KeyCombo(keyCode: KeyCodes.h, modifiers: [.control, .option, .command])`. `HotkeyAction`: `case stashWindows`. In `resolve`, after the tile claim: `claim(settings.stash, for: .stashWindows)`.

Run: `make test` — Expected: pass (including the existing settings-decoding test: older settings files gain the default through `ResilientJSON`).

- [ ] **Step 3: Window stash state**

`OverlayView.swift`, `OverlayState`: add `var isStashed = false`. In `OverlayRootView.body`, after `.overlay(alignment: .bottomTrailing) { … }` add:

```swift
        .overlay {
            // A stashed window is a sliver at the screen edge: any click brings every window back.
            if state.isStashed {
                Color.clear.contentShape(Rectangle()).onTapGesture { controller.manager.toggleStash() }
            }
        }
```

`CheetWindowController.swift`:

1. Replace `var frame: NSRect { panel.frame }` with:

```swift
    /// Where the window sits when it isn't stashed.
    private(set) var homeFrame: NSRect?
    var isStashed: Bool { homeFrame != nil }
    /// The window's frame, or its home frame while stashed (for tiling, workspaces and hide).
    var frame: NSRect { homeFrame ?? panel.frame }

    func stash(to stashed: NSRect) {
        guard !isStashed else { return }
        if editState.isEditing { endEditing() }
        homeFrame = panel.frame
        state.isStashed = true
        panel.acceptsKey = false
        if panel.isKeyWindow { panel.resignKey() }
        setFrame(stashed, animate: true, remember: false)
    }

    func unstash(to home: NSRect) {
        guard isStashed else { return }
        homeFrame = nil
        state.isStashed = false
        panel.acceptsKey = true
        setFrame(home, animate: true, remember: false)
    }
```

2. In `scheduleFrameSave()`, add `!isStashed` to the guard: `guard userAdjustedFrame, !isAnimatingFrame, !isStashed, state.isVisible, model.settings.layout.rememberFrame else { return }`. In `saveFrame()` add `guard !isStashed else { return }` as its first line.

- [ ] **Step 4: Manager stash**

Add to `CheetWindowManager`:

```swift
    // MARK: Stashing

    private(set) var isStashed = false

    func toggleStash() { isStashed ? unstash() : stash() }

    /// Slides every window to the nearest free screen edge, leaving a 20pt sliver.
    func stash() {
        guard !windows.isEmpty, !isStashed else { return }
        isStashed = true
        pendingPress = nil
        for window in windows {
            guard let screen = window.window.screen ?? NSScreen.main else { continue }
            let others = NSScreen.screens.filter { $0 !== screen }.map(\.frame)
            let target = StashGeometry.stash(window.frame, visibleFrame: screen.visibleFrame, screenFrame: screen.frame,
                                             otherScreens: others, sliver: 20)
            window.stash(to: target.frame)
        }
    }

    /// Brings every stashed window back to where it was (onto a remaining screen if its display is gone).
    func unstash() {
        guard isStashed else { return }
        isStashed = false
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        for window in windows {
            guard let home = window.homeFrame else { continue }
            let stillOnAScreen = NSScreen.screens.contains { $0.frame.intersects(home) }
            let target = stillOnAScreen || mouseScreen == nil ? home
                : home.clamped(to: mouseScreen!.visibleFrame, minSize: OverlayPanel.minimumSize)
            window.unstash(to: target)
        }
        activeWindow?.focus(model.settings.behavior.takeFocus)
    }
```

Stashing interacts with the rest as the spec says:

1. `show(cheetID:alongside:focus:)`: first line after the `guard`: `if isStashed { unstash() }`.
2. `toggleLast()`: first line: `if isStashed { unstash(); return }`.
3. `tile()`: first line: `if isStashed { unstash() }`.
4. `hotkeyPressed`: after the key-repeat `guard`, add:

```swift
        if isStashed, let existing = window(showing: cheetID) {
            unstash() // its window is a sliver: bring everything back rather than closing it
            existing.focus(model.settings.behavior.takeFocus)
            return
        }
```

5. `hotkeyReleased`: after computing `release`, before the `switch`, add:

```swift
        // A tap or an alongside press brings the stash back; a peek leaves it alone.
        if isStashed, press.action != .close, release != .closeOpened { unstash() }
```

6. `windowWillClose`: after removing the window, `if isStashed, !windows.contains(where: \.isStashed) { isStashed = false }`.

- [ ] **Step 5: Entry points**

1. `AppController.handlePress`: `case .stashWindows: overlay.toggleStash()`.
2. `StatusMenuController.rebuild()`, after the tile item:

```swift
        let stash = ActionMenuItem(overlay.isStashed ? "Bring Back Cheet Windows" : "Stash Cheet Windows", modifiers: []) { [weak controller] in
            controller?.overlay.toggleStash()
        }
        stash.isEnabled = overlay.isVisible
        apply(model.hotkeyPlan.combo(for: .stashWindows), to: stash)
        menu.addItem(stash)
```

3. `SettingsView` `HotkeysPane` "Global actions": `LabeledContent("Stash cheet windows") { globalRecorder(hotkeys.stash, action: .stashWindows) }`; `owner(of:)`: `case .stashWindows: return "stash cheet windows"`.

- [ ] **Step 6: Snapshot check**

In the snapshot block after the `tiled:` print, add:

```swift
                    overlay.toggleStash()
                    await pause(0.5)
                    let visible = overlay.windows.map { w -> String in
                        let screen = w.window.screen?.visibleFrame ?? .zero
                        let inside = w.window.frame.intersection(screen)
                        return "\(Int(inside.width))×\(Int(inside.height))"
                    }
                    print("stashed: visible slivers \(visible)")
                    overlay.toggleStash()
                    await pause(0.5)
                    print("unstashed: \(frames())")
```

- [ ] **Step 7: Build, test, run**

Run: `make test && make app`, then the snapshot command with `grep -E 'tiled:|stashed:'`.
Expected: each sliver is `20×<height>` (left/right) or `<width>×20` (top/bottom); the `unstashed:` frames equal the `tiled:` frames.

- [ ] **Step 8: Manual check**

`make run`: open two windows, press ⌃⌥⌘H — they slide to the nearest edges leaving slivers (never under the menu bar or Dock); click a sliver — all return; stash again and tap a cheet's hotkey — everything returns; hold a hotkey while stashed — it peeks over the slivers and they stay stashed.

- [ ] **Step 9: Commit**

```bash
git add -A Sources Tests
git commit -m "Stash cheet windows at the screen edges" -m "⌃⌥⌘H slides every cheet window to its nearest screen edge that doesn't border another display, leaving a 20pt sliver clear of the menu bar and Dock. Clicking a sliver, the hotkey again, or opening a cheet brings them back; a hold-to-peek shows over the stash without disturbing it. Stashed positions are never remembered." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Workspaces — save, update, recall (manager, menu bar, hotkeys, URL)

**Files:**
- Create: `Sources/CheetWithBothHands/Support/NSScreen+Display.swift`
- Create: `Sources/CheetWithBothHands/Settings/WorkspaceNamingView.swift`
- Modify: `HotkeyResolver.swift` (`.recallWorkspace`, workspaces parameter), `SupportTests.swift`
- Modify: `AppModel.swift` (resolver call), `CheetWindowManager.swift`, `CheetWindowController.swift` (⌥⌘S), `OverlayView.swift` (header menu), `WindowManager.swift`, `StatusMenuController.swift`, `AppController.swift`, `AppDelegate.swift` (URLCommands), `SettingsView.swift` (owner)

**Interfaces:**
- Consumes: `Workspace`, `WorkspaceWindow`, `ScreenInfo`, `restoredFrame` (Task 4); `AppModel.workspaces` (Task 4).
- Produces: `HotkeyAction.recallWorkspace(UUID)`; `HotkeyResolver.resolve(cheets:workspaces:settings:)` (`workspaces` defaults to `[]`); `NSScreen.displayUUID: String?`, `NSScreen.info: ScreenInfo`; `CheetWindowManager.currentWorkspaceID`, `workspaceWindows()`, `saveWorkspace(named:)`, `updateCurrentWorkspace()`, `recall(workspaceID:)`, `promptSaveWorkspace()`; `WindowManager.showWorkspaceNaming(suggestedName:existingNames:onSave:)`.

- [ ] **Step 1: Failing resolver tests**

Append to `HotkeyResolverTests`:

```swift
    @Test func workspaceHotkeysBeatCheetsButNotGlobalActions() {
        let list = cheets(1)
        let base: ModifierSet = [.control, .option, .command]
        let workspace = Workspace(name: "W", windows: [], hotkey: KeyCombo(keyCode: KeyCodes.one, modifiers: base))
        let plan = HotkeyResolver.resolve(cheets: list, workspaces: [workspace], settings: HotkeySettings())
        #expect(plan.combo(for: .recallWorkspace(workspace.id)) == workspace.hotkey)
        #expect(plan.conflicts[.showCheet(list[0].id)] != nil)

        let clash = Workspace(name: "Clash", windows: [], hotkey: KeyCombo(keyCode: KeyCodes.slash, modifiers: base))
        let second = HotkeyResolver.resolve(cheets: [], workspaces: [clash], settings: HotkeySettings())
        #expect(second.conflicts[.recallWorkspace(clash.id)] != nil) // the picker's ⌃⌥⌘/ wins
    }
```

Run: `make test FILTER=HotkeyResolverTests` — Expected: build failure.

- [ ] **Step 2: Implement in CheetCore**

`HotkeyAction`: `case recallWorkspace(UUID)`. Change the signature to `public static func resolve(cheets: [Cheet], workspaces: [Workspace] = [], settings: HotkeySettings) -> HotkeyPlan`, and after the global-action claims (picker, toggleLast, tile, stash, ghostMode) add:

```swift
        for workspace in workspaces {
            claim(workspace.hotkey, for: .recallWorkspace(workspace.id))
        }
```

Make the global claims read in this order: picker, toggleLast, stash, tile, ghostMode (move `ghostMode` after `tile`/`stash` if needed; all are global so their relative order only matters when two global actions share a combo).

Run: `make test` — Expected: pass.

`AppModel.swift`: both `HotkeyResolver.resolve(cheets: cheets, settings: settings.hotkeys)` calls become `HotkeyResolver.resolve(cheets: cheets, workspaces: workspaces, settings: settings.hotkeys)`.

- [ ] **Step 3: Screen identity**

Create `Sources/CheetWithBothHands/Support/NSScreen+Display.swift`:

```swift
import AppKit
import CheetCore

extension NSScreen {
    /// The display's UUID, stable across reboots and reconnects (unlike its display number).
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    var info: ScreenInfo { ScreenInfo(displayID: displayUUID, visibleFrame: visibleFrame) }

    /// The screen showing most of `rect`.
    static func bestMatch(for rect: NSRect) -> NSScreen? {
        screens.max { a, b in
            let areaA = a.frame.intersection(rect).width * a.frame.intersection(rect).height
            let areaB = b.frame.intersection(rect).width * b.frame.intersection(rect).height
            return areaA < areaB
        } ?? main
    }
}
```

- [ ] **Step 4: Manager — save, update, recall**

Add to `CheetWindowManager`:

```swift
    // MARK: Workspaces

    /// The workspace last saved or recalled, offered as "Update …" in the menus.
    private(set) var currentWorkspaceID: UUID?

    var currentWorkspace: Workspace? { model.workspaces.first { $0.id == currentWorkspaceID } }

    /// The open windows as workspace entries (home frames while stashed), back to front.
    func workspaceWindows() -> [WorkspaceWindow] {
        windows.compactMap { window in
            guard let id = window.cheetID, let screen = NSScreen.bestMatch(for: window.frame) else { return nil }
            return WorkspaceWindow(cheetID: id, frame: NormalizedRect(rect: window.frame, in: screen.visibleFrame),
                                   displayID: screen.displayUUID)
        }
    }

    /// Saves the open windows as a workspace, replacing one with the same name (case-insensitive).
    func saveWorkspace(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entries = workspaceWindows()
        if let index = model.workspaces.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            model.workspaces[index].windows = entries
            model.workspaces[index].updatedAt = Date()
            currentWorkspaceID = model.workspaces[index].id
        } else {
            let workspace = Workspace(name: trimmed, windows: entries)
            model.workspaces.append(workspace)
            currentWorkspaceID = workspace.id
        }
        showToast("Saved workspace “\(trimmed)”")
    }

    func updateCurrentWorkspace() {
        guard let id = currentWorkspaceID, let index = model.workspaces.firstIndex(where: { $0.id == id }) else { return }
        model.workspaces[index].windows = workspaceWindows()
        model.workspaces[index].updatedAt = Date()
        showToast("Updated “\(model.workspaces[index].name)”")
    }

    /// Replaces the open windows with the workspace's, focusing its active window.
    func recall(workspaceID: UUID) {
        guard let workspace = model.workspaces.first(where: { $0.id == workspaceID }) else { return }
        let entries = workspace.windows.filter { model.cheet(id: $0.cheetID) != nil }
        guard !entries.isEmpty else {
            if isVisible { showToast("Nothing to recall in “\(workspace.name)”") } else { NSSound.beep() } // toasts need a window
            return
        }
        if isStashed { unstash() }
        hiddenSet = []
        isHidingAll = true
        for window in windows { window.close() }
        isHidingAll = false
        let screens = NSScreen.screens.map(\.info)
        let fallback = screenForPresentation().info
        for (position, entry) in entries.enumerated() {
            let frame = entry.restoredFrame(on: screens, fallback: fallback, minSize: OverlayPanel.minimumSize)
            open(entry.cheetID, at: frame, focus: position == entries.count - 1 ? nil : false)
        }
        currentWorkspaceID = workspace.id
    }

    /// Asks for a name, then saves the open windows as a workspace.
    func promptSaveWorkspace() {
        let titles = windows.compactMap { $0.cheetID.flatMap { model.cheet(id: $0)?.title } }
        guard !titles.isEmpty else { NSSound.beep(); return }
        AppController.shared.windows.showWorkspaceNaming(
            suggestedName: currentWorkspace?.name ?? Workspace.suggestedName(for: titles),
            existingNames: model.workspaces.map(\.name)
        ) { [weak self] name in self?.saveWorkspace(named: name) }
    }
```

- [ ] **Step 5: Naming window**

Create `Sources/CheetWithBothHands/Settings/WorkspaceNamingView.swift`:

```swift
import SwiftUI

/// "Save Workspace…": a name field that warns when saving will replace an existing workspace.
struct WorkspaceNamingView: View {
    let existingNames: [String]
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State var name: String

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var replaces: Bool {
        existingNames.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Workspace").font(.headline)
            Text("Saves the cheet windows that are open now, with their positions and sizes.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            if replaces {
                Label("A workspace with this name exists. Saving replaces its windows.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(replaces ? "Replace" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
    }
}
```

`WindowManager.swift`: add `private(set) var namingWindow: NSWindow?`, include `namingWindow` in `managedWindows`, and add:

```swift
    func showWorkspaceNaming(suggestedName: String, existingNames: [String], onSave: @escaping (String) -> Void) {
        namingWindow?.close()
        let view = WorkspaceNamingView(
            existingNames: existingNames,
            onSave: { [weak self] name in
                self?.namingWindow?.close()
                onSave(name)
            },
            onCancel: { [weak self] in self?.namingWindow?.close() },
            name: suggestedName
        )
        let window = makeWindow(title: "Save Workspace", size: NSSize(width: 380, height: 170), autosave: "CWBHWorkspaceNaming", content: view)
        window.styleMask.remove([.resizable, .miniaturizable])
        namingWindow = window
        present(window)
    }
```

- [ ] **Step 6: Entry points**

1. `CheetWindowController.handleKey`, inside `if flags == [.command, .option] { … }`: `if keyCode == KeyCodes.s { manager.promptSaveWorkspace(); return true } // ⌥⌘S`.
2. `OverlayView.swift` `cheetMenu`, after "Tile Cheet Windows": `Button("Save Workspace…") { controller.manager.promptSaveWorkspace() }` and, when `controller.manager.currentWorkspace` is non-nil, `Button("Update “\(workspace.name)”") { controller.manager.updateCurrentWorkspace() }`.
3. `AppController.handlePress`: `case .recallWorkspace(let id): overlay.recall(workspaceID: id)`.
4. `SettingsView` `owner(of:)`: `case .recallWorkspace(let id): return "workspace “\(model.workspaces.first { $0.id == id }?.name ?? "?")”"`.
5. `StatusMenuController.rebuild()`, after the stash item:

```swift
        let workspacesItem = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
        let workspacesMenu = NSMenu()
        for workspace in model.workspaces {
            let item = ActionMenuItem(workspace.name, modifiers: []) { [weak controller] in controller?.overlay.recall(workspaceID: workspace.id) }
            apply(model.hotkeyPlan.combo(for: .recallWorkspace(workspace.id)), to: item)
            item.state = overlay.currentWorkspaceID == workspace.id ? .on : .off
            workspacesMenu.addItem(item)
        }
        if !model.workspaces.isEmpty { workspacesMenu.addItem(.separator()) }
        let save = ActionMenuItem("Save Workspace…", modifiers: []) { [weak controller] in controller?.overlay.promptSaveWorkspace() }
        save.isEnabled = overlay.isVisible
        workspacesMenu.addItem(save)
        if let current = overlay.currentWorkspace {
            let update = ActionMenuItem("Update “\(current.name)”", modifiers: []) { [weak controller] in controller?.overlay.updateCurrentWorkspace() }
            update.isEnabled = overlay.isVisible
            workspacesMenu.addItem(update)
        }
        workspacesMenu.addItem(ActionMenuItem("Manage Workspaces…", modifiers: []) { [weak controller] in controller?.openSettings(.workspaces) })
        workspacesItem.submenu = workspacesMenu
        menu.addItem(workspacesItem)
```

(`SettingsPane.workspaces` is added in Task 10; until then, point "Manage Workspaces…" at `.cheets` and change it in Task 10 Step 3.)

6. `URLCommands.handle`: add

```swift
        case "workspace":
            let name = argument ?? ""
            let workspaces = controller.model.workspaces
            let match = Int(name).flatMap { workspaces.indices.contains($0 - 1) ? workspaces[$0 - 1] : nil }
                ?? workspaces.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            if let match { controller.overlay.recall(workspaceID: match.id) } else { NSSound.beep() }
```

and add `…/workspace/<name or number>` to the doc comment.

- [ ] **Step 7: Snapshot check**

In the snapshot block after `unstashed:`, add:

```swift
                    overlay.saveWorkspace(named: "Snapshot Test")
                    let saved = frames()
                    overlay.hide()
                    await pause(0.4)
                    if let id = controller.model.workspaces.first(where: { $0.name == "Snapshot Test" })?.id {
                        overlay.recall(workspaceID: id)
                        await pause(0.5)
                        print("workspace: saved \(saved)")
                        print("workspace: recalled \(frames())")
                    }
                    controller.model.workspaces.removeAll { $0.name == "Snapshot Test" } // keep scratch libraries clean
```

- [ ] **Step 8: Build, test, run**

Run: `make test && make app`, then the snapshot command with `grep workspace:`.
Expected: the `recalled` frames equal the `saved` frames (±1pt from normalization rounding).

- [ ] **Step 9: Commit**

```bash
git add -A Sources Tests
git commit -m "Save and recall cheet workspaces" -m "A workspace is a named set of cheet windows with their frames and displays. Save from the menu bar, the header menu or ⌥⌘S, update the current one, and recall from the menu bar, a per-workspace hotkey or cheetwithbothhands://workspace/<name>. Recalling replaces the open windows; windows whose display is gone land on the current screen." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Workspaces in the picker and Settings

**Files:**
- Create: `Sources/CheetWithBothHands/Settings/WorkspacesPane.swift`
- Modify: `PickerController.swift`, `WindowManager.swift` (`SettingsPane`), `SettingsView.swift`, `StatusMenuController.swift`, `AppController.swift`

**Interfaces:**
- Consumes: `CheetWindowManager.recall(workspaceID:)`, `AppModel.workspaces`, `HotkeyRecorder`, `HotkeyStatusBadge`.
- Produces: `PickerItem` (`.workspace(Workspace)`, `.cheet(index: Int, cheet: Cheet)`); `PickerController.onRecall: ((UUID) -> Void)?`; `SettingsPane.workspaces`.

- [ ] **Step 1: Picker items**

`PickerController.swift`:

1. Add above `PickerState`:

```swift
enum PickerItem: Identifiable {
    case workspace(Workspace)
    case cheet(index: Int, cheet: Cheet)

    var id: UUID {
        switch self {
        case .workspace(let workspace): workspace.id
        case .cheet(_, let cheet): cheet.id
        }
    }
}
```

2. Add `var onRecall: ((UUID) -> Void)?` next to `onChoose`.
3. Replace `results()` with:

```swift
    /// Matching workspaces first, then cheets (best title matches first).
    func results() -> [PickerItem] {
        let tokens = CheetSearchIndex.tokens(for: state.query)
        let workspaces = model.workspaces.filter { workspace in
            tokens.allSatisfy { workspace.name.searchFolded.contains($0) }
        }.map(PickerItem.workspace)
        let all = model.cheets.enumerated().map { (index: $0.offset, cheet: $0.element) }
        guard !tokens.isEmpty else { return workspaces + all.map { .cheet(index: $0.index, cheet: $0.cheet) } }
        let scored = all.compactMap { item -> (Int, (index: Int, cheet: Cheet))? in
            let title = item.cheet.title.searchFolded
            let sections = item.cheet.sections.map { $0.title.searchFolded }.joined(separator: " ")
            let haystack = title + " " + sections
            guard tokens.allSatisfy({ haystack.contains($0) }) else { return nil }
            var score = 0
            if title.hasPrefix(tokens[0]) { score += 100 }
            if tokens.allSatisfy({ title.contains($0) }) { score += 50 }
            return (score, item)
        }
        let cheets = scored.sorted { $0.0 > $1.0 || ($0.0 == $1.0 && $0.1.index < $1.1.index) }
            .map { PickerItem.cheet(index: $0.1.index, cheet: $0.1.cheet) }
        return workspaces + cheets
    }
```

4. Replace `choose(_:alongside:)` / `chooseSelection(alongside:)` with:

```swift
    func choose(_ item: PickerItem, alongside: Bool = false) {
        hide()
        switch item {
        case .workspace(let workspace): onRecall?(workspace.id)
        case .cheet(_, let cheet): onChoose?(cheet.id, alongside)
        }
    }

    func chooseSelection(alongside: Bool = false) {
        let list = results()
        guard list.indices.contains(state.selection) else { NSSound.beep(); return }
        choose(list[state.selection], alongside: alongside)
    }
```

5. In `show(focus:)`, the initial selection skips the workspaces: `state.selection = model.workspaces.count + max(0, model.index(of: model.viewState.lastCheetID) ?? 0)`.
6. In `PickerView`, the `ForEach` becomes `ForEach(Array(results.enumerated()), id: \.element.id) { position, item in … }` and renders:

```swift
                            Group {
                                switch item {
                                case .workspace(let workspace):
                                    WorkspacePickerRow(workspace: workspace, cheets: model.cheets,
                                                       combo: model.hotkeyPlan.combo(for: .recallWorkspace(workspace.id)),
                                                       isSelected: position == state.selection, accent: appearance.accent.color)
                                case .cheet(let index, let cheet):
                                    PickerRow(number: index + 1, cheet: cheet, combo: model.combo(forCheet: cheet.id),
                                              isSelected: position == state.selection, accent: appearance.accent.color)
                                }
                            }
                            .id(item.id)
                            .onTapGesture { controller.choose(item, alongside: NSEvent.modifierFlags.contains(.shift)) }
                            .onHover { if $0 { state.selection = position } }
```

and the `onChange(of: state.selection)` scrolls to `results[state.selection].id`.

7. Add the workspace row next to `PickerRow`:

```swift
private struct WorkspacePickerRow: View {
    let workspace: Workspace
    let cheets: [Cheet]
    let combo: KeyCombo?
    let isSelected: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(accent.opacity(isSelected ? 0.35 : 0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(workspace.windows.compactMap { window in cheets.first { $0.id == window.cheetID }?.title }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let combo {
                Text(combo.displayString)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? Color.primary.opacity(0.12) : .clear))
        .contentShape(Rectangle())
    }
}
```

`AppController.start()`: `picker.onRecall = { [weak self] id in self?.overlay.recall(workspaceID: id) }`.

- [ ] **Step 2: Settings pane**

Create `Sources/CheetWithBothHands/Settings/WorkspacesPane.swift`:

```swift
import CheetCore
import SwiftUI

/// Saved workspaces: rename, reorder, assign hotkeys, recall, delete.
struct WorkspacesPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("A workspace remembers a set of cheet windows and where they were. Save one from the menu bar › Workspaces, or press ⌥⌘S in a cheet.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(16)
            if model.workspaces.isEmpty {
                ContentUnavailableView("No Workspaces Yet", systemImage: "square.stack.3d.up",
                                       description: Text("Open the cheets you want, arrange them, then save them as a workspace."))
            } else {
                List {
                    ForEach($model.workspaces) { $workspace in
                        WorkspaceRow(model: model, workspace: $workspace)
                    }
                    .onMove { model.workspaces.move(fromOffsets: $0, toOffset: $1) }
                }
            }
        }
    }
}

private struct WorkspaceRow: View {
    let model: AppModel
    @Binding var workspace: Workspace

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $workspace.name).textFieldStyle(.plain).font(.body.weight(.semibold))
                Text(workspace.windows.compactMap { model.cheet(id: $0.cheetID)?.title }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            HotkeyStatusBadge(model: model, action: .recallWorkspace(workspace.id), requested: workspace.hotkey)
            HotkeyRecorder(combo: $workspace.hotkey)
            Button("Recall") { AppController.shared.overlay.recall(workspaceID: workspace.id) }
            Button(role: .destructive) {
                model.workspaces.removeAll { $0.id == workspace.id }
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete this workspace")
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 3: Register the pane**

`WindowManager.swift` `SettingsPane`: add `case workspaces` after `cheets` in the case list (`case general, hotkeys, appearance, layout, cheets, workspaces`), with title `"Workspaces"` and symbol `"square.stack.3d.up"`. `SettingsView` switch: `case .workspaces: WorkspacesPane(model: model)`. `StatusMenuController`: "Manage Workspaces…" opens `.workspaces`.

- [ ] **Step 4: Build and check**

Run: `make test && make app`, then `make run`: save a workspace with two windows, open the picker — the workspace is listed first and ↩ recalls it; type part of its name — it filters; Settings › Workspaces lists it; rename it, set a hotkey (its badge turns green), drag to reorder, Recall, Delete.

- [ ] **Step 5: Commit**

```bash
git add -A Sources
git commit -m "Workspaces in the picker and Settings" -m "The picker lists matching workspaces above cheets; Settings › Workspaces renames, reorders, sets hotkeys for, recalls and deletes them." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Docs and final verification

**Files:**
- Modify: `README.md`, `Sources/CheetCore/Storage/SampleCheets.swift`

- [ ] **Step 1: README**

In `README.md`:

1. In the "Using it" shortcut table add rows:

```markdown
| ⌃⌥⌘⇧1 … (a cheet's shortcut + ⇧) | Open that cheet alongside the ones showing |
| ⌃⌥⌘H | Stash every cheet window at the screen edges (again to bring them back) |
```

2. After the "Inside the overlay" paragraph add:

```markdown
### Several cheets at once

A cheet's shortcut replaces the cheet in the active window; add ⇧ to open it alongside instead (in
the picker, ⇧↩ or ⇧-click). Hold a shortcut to peek at a cheet over the others. ⌥⌘T (or the menu
bar) tiles the open windows side by side, or in a grid when there are four or more. ⌃⌥⌘H stashes
every window at its nearest screen edge, leaving a sliver; click one or press ⌃⌥⌘H again to bring
them back.

**Workspaces** remember a set of cheet windows and where they were. Save one from the menu bar ›
Workspaces or with ⌥⌘S in a cheet, and recall it from the picker, the menu bar, its own hotkey, or
`cheetwithbothhands://workspace/<name>`. Manage them in Settings › Workspaces.
```

3. In "Automation" add `open "cheetwithbothhands://show/2?alongside=1"` and `open "cheetwithbothhands://workspace/Coding"`.
4. In "Data", mention that `library.json` also holds workspaces.

- [ ] **Step 2: Welcome cheet**

In `Sources/CheetCore/Storage/SampleCheets.swift`, "Open cheets" table, add:

```markdown
    | Add ⇧ to a cheet's combo | Open it alongside the others |
    | ⌃⌥⌘H | Stash every cheet window at the screen edges |
```

and in "Inside the overlay" add `| ⌥⌘T | Tile the open cheet windows |` and `| ⌥⌘S | Save the open windows as a workspace |`.

- [ ] **Step 3: Full verification**

Run:

```bash
make test && make app && SP=$(mktemp -d) && (CWBH_DATA_DIR=$SP/data CWBH_SNAPSHOT_DIR=$SP/shots "build/Cheet with Both Hands.app/Contents/MacOS/CheetWithBothHands" > $SP/log 2>&1); grep -E 'keyboard scroll|stepping|alongside:|replace:|tiled:|stashed:|unstashed:|workspace:' $SP/log
```

Expected: all tests pass (including the sample round-trip test with the new welcome rows); the log shows every line from Tasks 5–9 with the expected values.

- [ ] **Step 4: Commit**

```bash
git add README.md Sources/CheetCore/Storage/SampleCheets.swift
git commit -m "Document several cheet windows, stashing and workspaces" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
