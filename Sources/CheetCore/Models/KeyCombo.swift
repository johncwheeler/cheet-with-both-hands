import Foundation

/// Modifier keys, using the same bit values as Carbon's `cmdKey`/`shiftKey`/`optionKey`/`controlKey`
/// so the raw value can be handed straight to `RegisterEventHotKey`.
public struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command = ModifierSet(rawValue: 1 << 8)
    public static let shift = ModifierSet(rawValue: 1 << 9)
    public static let option = ModifierSet(rawValue: 1 << 11)
    public static let control = ModifierSet(rawValue: 1 << 12)

    /// Apple's canonical display order: ⌃ ⌥ ⇧ ⌘.
    public static let displayOrder: [(ModifierSet, String, String)] = [
        (.control, "⌃", "Control"),
        (.option, "⌥", "Option"),
        (.shift, "⇧", "Shift"),
        (.command, "⌘", "Command"),
    ]

    public var symbols: String {
        ModifierSet.displayOrder.filter { contains($0.0) }.map(\.1).joined()
    }

    /// Whether the set contains at least one modifier that makes a combo safe to register globally.
    public var hasPrimaryModifier: Bool {
        !intersection([.command, .control, .option]).isEmpty
    }
}

public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: ModifierSet

    public init(keyCode: UInt32, modifiers: ModifierSet) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Display string using the US-ANSI key names. The app target overrides key names with the
    /// user's active keyboard layout.
    public var fallbackDisplayString: String {
        modifiers.symbols + (KeyCodes.name(for: keyCode) ?? "#\(keyCode)")
    }
}

public struct HotkeyAssignment: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        /// Base combo + the cheet's position number (1…9, 0).
        case automatic
        case custom
        case disabled
    }

    public var mode: Mode
    public var combo: KeyCombo?

    public init(mode: Mode, combo: KeyCombo? = nil) {
        self.mode = mode
        self.combo = combo
    }

    public static let automatic = HotkeyAssignment(mode: .automatic)
    public static let disabled = HotkeyAssignment(mode: .disabled)
    public static func custom(_ combo: KeyCombo) -> HotkeyAssignment { HotkeyAssignment(mode: .custom, combo: combo) }
}

/// Virtual key codes (Carbon `kVK_*`) and their US-layout names.
public enum KeyCodes {
    public static let a: UInt32 = 0x00, s: UInt32 = 0x01, d: UInt32 = 0x02, f: UInt32 = 0x03
    public static let h: UInt32 = 0x04, g: UInt32 = 0x05, z: UInt32 = 0x06, x: UInt32 = 0x07
    public static let c: UInt32 = 0x08, v: UInt32 = 0x09, b: UInt32 = 0x0B, q: UInt32 = 0x0C
    public static let w: UInt32 = 0x0D, e: UInt32 = 0x0E, r: UInt32 = 0x0F, y: UInt32 = 0x10
    public static let t: UInt32 = 0x11, o: UInt32 = 0x1F, u: UInt32 = 0x20, i: UInt32 = 0x22
    public static let p: UInt32 = 0x23, l: UInt32 = 0x25, j: UInt32 = 0x26, k: UInt32 = 0x28
    public static let n: UInt32 = 0x2D, m: UInt32 = 0x2E

    public static let one: UInt32 = 0x12, two: UInt32 = 0x13, three: UInt32 = 0x14, four: UInt32 = 0x15
    public static let five: UInt32 = 0x17, six: UInt32 = 0x16, seven: UInt32 = 0x1A, eight: UInt32 = 0x1C
    public static let nine: UInt32 = 0x19, zero: UInt32 = 0x1D

    public static let equal: UInt32 = 0x18, minus: UInt32 = 0x1B, rightBracket: UInt32 = 0x1E
    public static let leftBracket: UInt32 = 0x21, quote: UInt32 = 0x27, semicolon: UInt32 = 0x29
    public static let backslash: UInt32 = 0x2A, comma: UInt32 = 0x2B, slash: UInt32 = 0x2C
    public static let period: UInt32 = 0x2F, grave: UInt32 = 0x32

    public static let returnKey: UInt32 = 0x24, tab: UInt32 = 0x30, space: UInt32 = 0x31
    public static let delete: UInt32 = 0x33, escape: UInt32 = 0x35, forwardDelete: UInt32 = 0x75
    public static let home: UInt32 = 0x73, end: UInt32 = 0x77, pageUp: UInt32 = 0x74, pageDown: UInt32 = 0x79
    public static let leftArrow: UInt32 = 0x7B, rightArrow: UInt32 = 0x7C
    public static let downArrow: UInt32 = 0x7D, upArrow: UInt32 = 0x7E
    public static let keypadEnter: UInt32 = 0x4C, help: UInt32 = 0x72

    public static let functionKeys: [UInt32: Int] = [
        0x7A: 1, 0x78: 2, 0x63: 3, 0x76: 4, 0x60: 5, 0x61: 6, 0x62: 7, 0x64: 8, 0x65: 9, 0x6D: 10,
        0x67: 11, 0x6F: 12, 0x69: 13, 0x6B: 14, 0x71: 15, 0x6A: 16, 0x40: 17, 0x4F: 18, 0x50: 19, 0x5A: 20,
    ]

    /// Number-row key codes for positions 1…10 (the tenth position is the `0` key).
    public static let digitRow: [UInt32] = [one, two, three, four, five, six, seven, eight, nine, zero]

    /// Keys whose names do not depend on the keyboard layout.
    public static let specialNames: [UInt32: String] = [
        returnKey: "↩", tab: "⇥", space: "Space", delete: "⌫", escape: "⎋", forwardDelete: "⌦",
        home: "↖", end: "↘", pageUp: "⇞", pageDown: "⇟",
        leftArrow: "←", rightArrow: "→", downArrow: "↓", upArrow: "↑",
        keypadEnter: "⌤", help: "Help",
    ]

    private static let usNames: [UInt32: String] = [
        a: "A", s: "S", d: "D", f: "F", h: "H", g: "G", z: "Z", x: "X", c: "C", v: "V", b: "B",
        q: "Q", w: "W", e: "E", r: "R", y: "Y", t: "T", o: "O", u: "U", i: "I", p: "P", l: "L",
        j: "J", k: "K", n: "N", m: "M",
        one: "1", two: "2", three: "3", four: "4", five: "5", six: "6", seven: "7", eight: "8",
        nine: "9", zero: "0",
        equal: "=", minus: "-", rightBracket: "]", leftBracket: "[", quote: "'", semicolon: ";",
        backslash: "\\", comma: ",", slash: "/", period: ".", grave: "`",
    ]

    public static func isFunctionKey(_ keyCode: UInt32) -> Bool { functionKeys[keyCode] != nil }

    public static func name(for keyCode: UInt32) -> String? {
        if let special = specialNames[keyCode] { return special }
        if let fn = functionKeys[keyCode] { return "F\(fn)" }
        return usNames[keyCode]
    }
}
