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
