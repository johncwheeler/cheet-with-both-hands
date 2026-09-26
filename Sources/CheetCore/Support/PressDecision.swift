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
