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
