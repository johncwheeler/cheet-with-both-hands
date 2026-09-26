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

struct RelocationTests {
    let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let fallback = CGRect(x: 0, y: 60, width: 1440, height: 815)
    let minSize = CGSize(width: 360, height: 220)

    @Test func aFrameStillOnAScreenStaysPut() {
        let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
        #expect(frame.relocated(ontoScreens: [builtIn], fallback: fallback, minSize: minSize) == frame)
    }

    @Test func aFrameOnADisconnectedDisplayMovesIntoTheFallbackKeepingItsSize() {
        let onExternal = CGRect(x: 2000, y: 100, width: 600, height: 400)
        let moved = onExternal.relocated(ontoScreens: [builtIn], fallback: fallback, minSize: minSize)
        #expect(fallback.contains(moved))
        #expect(moved.size == onExternal.size)
    }
}
