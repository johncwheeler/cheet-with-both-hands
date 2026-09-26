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
