import Foundation
import CoreGraphics

public struct AppSettings: Codable, Equatable, Sendable {
    public var hotkeys = HotkeySettings()
    public var appearance = Appearance()
    public var layout = OverlayLayout()
    public var behavior = Behavior()
    public var branding = Branding()

    public init() {}
}

// MARK: - Branding

public enum IconScheme: String, Codable, CaseIterable, Sendable {
    /// The Cheeter mascot (the default): character app icon, hammer menu bar icon, splash screen, picker cameo.
    case cheeter
    /// The original keycap icons.
    case classic

    public var label: String {
        switch self {
        case .cheeter: "Cheeter"
        case .classic: "Classic"
        }
    }
}

public struct Branding: Codable, Equatable, Sendable {
    public var iconScheme: IconScheme = .cheeter
    /// Cheeter scheme only: show the splash screen at launch.
    public var showSplash = true
    /// Cheeter scheme only: show Cheeter's head in the cheet picker.
    public var showPickerMascot = true

    public init() {}

    public var splashEnabled: Bool { iconScheme == .cheeter && showSplash }
    public var pickerMascotEnabled: Bool { iconScheme == .cheeter && showPickerMascot }
}

// MARK: - Hotkeys

public struct HotkeySettings: Codable, Equatable, Sendable {
    /// Master switch for all global hotkeys.
    public var enabled = true
    /// Modifiers combined with the number row to auto-map the first ten cheets.
    public var baseModifiers: ModifierSet = [.control, .option, .command]
    public var autoNumbering = true
    public var picker: KeyCombo? = KeyCombo(keyCode: KeyCodes.slash, modifiers: [.control, .option, .command])
    public var toggleLast: KeyCombo? = KeyCombo(keyCode: KeyCodes.grave, modifiers: [.control, .option, .command])
    public var ghostMode: KeyCombo? = nil
    public var tile: KeyCombo? = nil
    public var stash: KeyCombo? = KeyCombo(keyCode: KeyCodes.h, modifiers: [.control, .option, .command])
    /// Register each cheet's combo plus ⇧ to open it alongside the windows already showing.
    public var shiftForAlongside = true

    public init() {}
}

// MARK: - Appearance

public struct RGBAColor: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
        } else {
            self.init(r: Double((v >> 24) & 0xFF) / 255, g: Double((v >> 16) & 0xFF) / 255,
                      b: Double((v >> 8) & 0xFF) / 255, a: Double(v & 0xFF) / 255)
        }
    }

    public static let indigo = RGBAColor(r: 0.20, g: 0.22, b: 0.55)
    public static let accentBlue = RGBAColor(r: 0.45, g: 0.70, b: 1.0)
}

public enum MaterialStyle: String, Codable, CaseIterable, Sendable {
    case hud, popover, menu, sidebar, sheet, underWindow, fullScreen, tooltip, solid

    public var label: String {
        switch self {
        case .hud: "HUD Glass"
        case .popover: "Popover"
        case .menu: "Menu"
        case .sidebar: "Sidebar"
        case .sheet: "Sheet"
        case .underWindow: "Under Window"
        case .fullScreen: "Full-Screen UI"
        case .tooltip: "Tooltip"
        case .solid: "Solid (no blur)"
        }
    }
}

public enum SchemeChoice: String, Codable, CaseIterable, Sendable {
    case system, light, dark
    public var label: String { rawValue.capitalized }
}

public enum FontDesignChoice: String, Codable, CaseIterable, Sendable {
    case standard, rounded, serif, monospaced
    public var label: String { self == .standard ? "Default" : rawValue.capitalized }
}

public enum Density: String, Codable, CaseIterable, Sendable {
    case compact, regular, relaxed
    public var label: String { rawValue.capitalized }
    public var rowSpacing: Double {
        switch self {
        case .compact: 2
        case .regular: 5
        case .relaxed: 9
        }
    }
}

public enum ModifierStyle: String, Codable, CaseIterable, Sendable {
    /// ⌘⇧P — Mac symbols in a single keycap per chord.
    case symbols
    /// Cmd + Shift + P — spelled-out names, one keycap per key.
    case names
    /// Keep whatever the source used.
    case asWritten

    public var label: String {
        switch self {
        case .symbols: "Symbols (⌘⇧P)"
        case .names: "Names (Cmd+Shift+P)"
        case .asWritten: "As written"
        }
    }
}

public struct Appearance: Codable, Hashable, Sendable {
    public var material: MaterialStyle = .hud
    public var colorScheme: SchemeChoice = .dark
    public var tint: RGBAColor = .indigo
    /// Opacity of the tint wash over the blurred background.
    public var tintStrength: Double = 0.30
    /// Opacity of the background (blur + tint). Lower = more see-through, text stays crisp.
    public var backgroundOpacity: Double = 1.0
    /// Overall window opacity, including text.
    public var windowOpacity: Double = 0.97
    /// `nil` = system font using `fontDesign`.
    public var fontFamily: String? = nil
    public var fontDesign: FontDesignChoice = .standard
    public var fontSize: Double = 13
    /// `nil` = automatic (primary label color).
    public var textColor: RGBAColor? = nil
    public var accent: RGBAColor = .accentBlue
    public var cornerRadius: Double = 16
    /// 0 = automatic (based on `minColumnWidth`).
    public var columns: Int = 0
    public var minColumnWidth: Double = 300
    public var density: Density = .regular
    public var sectionCards = true
    public var rowSeparators = true
    public var keycaps = true
    public var modifierStyle: ModifierStyle = .symbols
    public var showHeader = true
    public var showBorder = true
    /// Light backdrop behind images, so dark diagrams stay legible on dark overlays.
    public var imageBackdrop = true

    public init() {}

    public static let fontSizeRange: ClosedRange<Double> = 9...28
}

// MARK: - Layout

public enum OverlayAnchor: String, Codable, CaseIterable, Sendable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight

    /// Horizontal/vertical position in 0…1 (0 = left/bottom in AppKit coordinates).
    public var unitPosition: (x: Double, y: Double) {
        switch self {
        case .topLeft: (0, 1)
        case .top: (0.5, 1)
        case .topRight: (1, 1)
        case .left: (0, 0.5)
        case .center: (0.5, 0.5)
        case .right: (1, 0.5)
        case .bottomLeft: (0, 0)
        case .bottom: (0.5, 0)
        case .bottomRight: (1, 0)
        }
    }
}

public enum ScreenChoice: String, Codable, CaseIterable, Sendable {
    case mouse, focused, primary
    public var label: String {
        switch self {
        case .mouse: "Screen with mouse pointer"
        case .focused: "Screen with focused window"
        case .primary: "Primary screen"
        }
    }
}

/// A rectangle expressed as fractions of a screen's visible frame, so a remembered position
/// carries over sensibly between displays of different sizes.
public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(rect: CGRect, in container: CGRect) {
        x = (rect.minX - container.minX) / container.width
        y = (rect.minY - container.minY) / container.height
        width = rect.width / container.width
        height = rect.height / container.height
    }

    public func denormalized(in container: CGRect) -> CGRect {
        CGRect(
            x: container.minX + x * container.width,
            y: container.minY + y * container.height,
            width: width * container.width,
            height: height * container.height
        )
    }
}

public struct OverlayLayout: Codable, Equatable, Sendable {
    public var anchor: OverlayAnchor = .center
    public var widthFraction: Double = 0.66
    public var heightFraction: Double = 0.72
    public var margin: Double = 24
    public var screen: ScreenChoice = .mouse
    /// Remember where the overlay was dragged/resized to.
    public var rememberFrame = true
    /// Remember frame per cheet instead of one global frame.
    public var perCheetFrames = false

    public init() {}
}

// MARK: - Behavior

public enum TriggerMode: String, Codable, CaseIterable, Sendable {
    /// Press to show, press again to hide.
    case toggle
    /// Visible only while the combo is held.
    case hold
    /// Tap toggles; press-and-hold peeks and hides on release.
    case smart

    public var label: String {
        switch self {
        case .toggle: "Toggle (press to show, press again to hide)"
        case .hold: "Hold to peek (hide on release)"
        case .smart: "Smart (tap toggles, hold peeks)"
        }
    }
}

public struct Behavior: Codable, Equatable, Sendable {
    public var trigger: TriggerMode = .smart
    public var holdThreshold: Double = 0.35
    public var fadeDuration: Double = 0.18
    /// Let the overlay take keyboard focus (for search / shortcuts) without activating the app.
    public var takeFocus = true
    public var dismissOnOutsideClick = false
    /// Click-through overlay that never intercepts the mouse.
    public var ghostMode = false
    public var showOnAllSpaces = true
    public var copyOnClick = true
    /// Keep images when importing web pages (they're downloaded once and cached with the library).
    public var importImages = true

    public init() {}
}

// MARK: - View state (runtime memory, persisted separately from settings)

public struct CheetViewState: Codable, Equatable, Sendable {
    public var collapsedSections: Set<UUID> = []
    public var frame: NormalizedRect? = nil

    public init() {}
}

public struct ViewState: Codable, Equatable, Sendable {
    public var lastCheetID: UUID? = nil
    public var globalFrame: NormalizedRect? = nil
    public var cheets: [String: CheetViewState] = [:]
    public var hasLaunchedBefore = false

    public init() {}

    public subscript(cheet id: UUID) -> CheetViewState {
        get { cheets[id.uuidString] ?? CheetViewState() }
        set { cheets[id.uuidString] = newValue }
    }
}

// MARK: - Forward-compatible decoding

/// Decodes a value by deep-merging the stored JSON over the encoded defaults, so settings files
/// written by older versions (missing keys) still load without losing the user's choices.
public enum ResilientJSON {
    public static func decode<T: Codable>(_ type: T.Type, from data: Data, defaults: T) -> T {
        let encoder = JSONEncoder.cheet
        let decoder = JSONDecoder.cheet
        guard
            let stored = try? JSONSerialization.jsonObject(with: data),
            let defaultData = try? encoder.encode(defaults),
            let base = try? JSONSerialization.jsonObject(with: defaultData),
            let mergedData = try? JSONSerialization.data(withJSONObject: merge(base, stored)),
            let value = try? decoder.decode(T.self, from: mergedData)
        else {
            return (try? decoder.decode(T.self, from: data)) ?? defaults
        }
        return value
    }

    static func merge(_ base: Any, _ over: Any) -> Any {
        guard let b = base as? [String: Any], let o = over as? [String: Any] else { return over }
        var result = b
        for (key, value) in o {
            result[key] = b[key].map { merge($0, value) } ?? value
        }
        return result
    }
}

extension JSONEncoder {
    public static var cheet: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    public static var cheet: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
