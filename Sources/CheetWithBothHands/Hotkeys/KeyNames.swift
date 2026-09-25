import AppKit
import Carbon.HIToolbox
import CheetCore

/// Layout-aware key names (so a German or French keyboard shows its own characters).
enum KeyNames {
    static func name(for keyCode: UInt32) -> String {
        if let special = KeyCodes.specialNames[keyCode] { return special }
        if let fn = KeyCodes.functionKeys[keyCode] { return "F\(fn)" }
        if let translated = translate(keyCode) { return translated.uppercased() }
        return KeyCodes.name(for: keyCode) ?? "Key \(keyCode)"
    }

    /// The character a key produces with no modifiers on the current keyboard layout.
    static func translate(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        let maxLength = 4
        var chars = [UniChar](repeating: 0, count: maxLength)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                maxLength,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }
}

extension KeyCombo {
    var keyName: String { KeyNames.name(for: keyCode) }
    var displayString: String { modifiers.symbols + keyName }

    /// Key equivalent for showing this combo in an NSMenu.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        let flags = modifiers.eventFlags
        if let fn = KeyCodes.functionKeys[keyCode], let scalar = UnicodeScalar(UInt32(NSF1FunctionKey + fn - 1)) {
            return (String(Character(scalar)), flags)
        }
        let specials: [UInt32: Int] = [
            KeyCodes.upArrow: NSUpArrowFunctionKey, KeyCodes.downArrow: NSDownArrowFunctionKey,
            KeyCodes.leftArrow: NSLeftArrowFunctionKey, KeyCodes.rightArrow: NSRightArrowFunctionKey,
            KeyCodes.home: NSHomeFunctionKey, KeyCodes.end: NSEndFunctionKey,
            KeyCodes.pageUp: NSPageUpFunctionKey, KeyCodes.pageDown: NSPageDownFunctionKey,
            KeyCodes.forwardDelete: NSDeleteFunctionKey,
        ]
        if let code = specials[keyCode], let scalar = UnicodeScalar(UInt32(code)) {
            return (String(Character(scalar)), flags)
        }
        switch keyCode {
        case KeyCodes.space: return (" ", flags)
        case KeyCodes.returnKey: return ("\r", flags)
        case KeyCodes.tab: return ("\t", flags)
        case KeyCodes.escape: return ("\u{1b}", flags)
        case KeyCodes.delete: return ("\u{8}", flags)
        default: break
        }
        guard let char = KeyNames.translate(keyCode) ?? KeyCodes.name(for: keyCode), char.count == 1 else { return nil }
        return (char.lowercased(), flags)
    }
}

extension ModifierSet {
    init(_ flags: NSEvent.ModifierFlags) {
        var set: ModifierSet = []
        if flags.contains(.command) { set.insert(.command) }
        if flags.contains(.option) { set.insert(.option) }
        if flags.contains(.control) { set.insert(.control) }
        if flags.contains(.shift) { set.insert(.shift) }
        self = set
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        if contains(.shift) { flags.insert(.shift) }
        return flags
    }
}
