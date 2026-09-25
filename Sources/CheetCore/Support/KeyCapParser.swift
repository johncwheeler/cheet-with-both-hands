import Foundation

/// Recognises keyboard shortcuts in cell text ("Ctrl+Shift+P", "⌘K ⌘S", "`C-x` `C-s`") so they can
/// be drawn as keycaps.
public enum KeyCapParser {
    public enum Element: Hashable, Sendable {
        /// Keys pressed together.
        case chord([String])
        /// Connective text between chords: "then", "or", "/", ",".
        case separator(String)
    }

    private static let modifierNames: [String: String] = [
        "cmd": "⌘", "command": "⌘", "⌘": "⌘", "super": "⌘", "win": "⊞", "windows": "⊞",
        "ctrl": "⌃", "control": "⌃", "ctl": "⌃", "⌃": "⌃",
        "alt": "⌥", "opt": "⌥", "option": "⌥", "meta": "⌥", "⌥": "⌥",
        "shift": "⇧", "⇧": "⇧",
        "fn": "fn", "hyper": "✦",
    ]

    private static let specialNames: [String: String] = [
        "esc": "esc", "escape": "esc", "⎋": "esc",
        "tab": "⇥", "⇥": "⇥",
        "enter": "↩", "return": "↩", "ret": "↩", "↩": "↩", "⏎": "↩", "↵": "↩", "⌤": "⌤",
        "space": "Space", "spacebar": "Space", "␣": "Space", "spc": "Space",
        "backspace": "⌫", "bksp": "⌫", "⌫": "⌫", "delete": "⌫",
        "del": "⌦", "⌦": "⌦", "forwarddelete": "⌦",
        "ins": "Ins", "insert": "Ins",
        "home": "Home", "↖": "Home", "end": "End", "↘": "End",
        "pgup": "PgUp", "pageup": "PgUp", "⇞": "PgUp", "pgdn": "PgDn", "pagedown": "PgDn", "⇟": "PgDn",
        "up": "↑", "down": "↓", "left": "←", "right": "→",
        "↑": "↑", "↓": "↓", "←": "←", "→": "→",
        "caps": "⇪", "capslock": "⇪", "⇪": "⇪",
        "prtsc": "PrtSc", "printscreen": "PrtSc", "menu": "Menu",
        "click": "Click", "leftclick": "Click", "rightclick": "Right-Click", "drag": "Drag",
        "scroll": "Scroll", "wheel": "Scroll", "plus": "+", "minus": "-",
    ]

    private static let modifierSymbolChars: Set<Character> = ["⌘", "⌃", "⌥", "⇧"]
    /// Mouse actions only read as keys alongside a modifier ("⌘-Click"), never on their own ("Scroll").
    private static let mouseWords: Set<String> = ["click", "leftclick", "rightclick", "drag", "scroll", "wheel"]
    private static let separatorWords: Set<String> = ["then", "or", "/", ",", "and", "|", "→", ">", "…", "...", "–", "to", "through"]
    private static let symbolOrder: [String] = ["fn", "⌃", "⌥", "⇧", "⌘", "⊞", "✦"]

    /// Returns keycap elements if the whole text is a key sequence, otherwise `nil`.
    public static func parse(_ raw: String) -> [Element]? {
        // `Ctrl`+`C` and "Ctrl + C" both mean Ctrl+C. Paired backticks are code spans; a lone one is the ` key.
        var text = raw.replacingOccurrences(of: #"`\s*\+\s*`"#, with: "+", options: .regularExpression)
        text = text.replacingOccurrences(of: #"`([^`\n]+)`"#, with: " $1 ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\\([\\`*_\[\]|])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(\S)\s+\+\s+(\S)"#, with: "$1+$2", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 48, !text.contains("\n") else { return nil }

        var elements: [Element] = []
        var sawSignificantKey = false

        let tokens = text.split(whereSeparator: { $0 == " " }).map(String.init)
        for (position, token) in tokens.enumerated() {
            if separatorWords.contains(token.lowercased()) {
                guard !elements.isEmpty else { return nil }
                elements.append(.separator(token.lowercased() == "and" ? "&" : token))
                continue
            }
            // "Ctrl+C, Ctrl+V" → chord, separator, chord. A final "⌘," is the comma key.
            var chordToken = token
            var trailingSeparator: String? = nil
            if position < tokens.count - 1, chordToken.count > 1, chordToken.last == ",",
               let previous = chordToken.dropLast().last, !modifierSymbolChars.contains(previous), previous != "+" {
                chordToken.removeLast()
                trailingSeparator = ","
            }
            guard let chord = parseChord(chordToken) else { return nil }
            if chord.contains(where: { isModifier($0) || (isSpecial($0) && !mouseWords.contains($0.lowercased())) }) {
                sawSignificantKey = true
            }
            elements.append(.chord(chord))
            if let sep = trailingSeparator { elements.append(.separator(sep)) }
        }

        if case .separator = elements.last { elements.removeLast() }
        let chordCount = elements.filter { if case .chord = $0 { return true } else { return false } }.count
        guard sawSignificantKey, chordCount >= 1, chordCount <= 5 else { return nil }
        return elements
    }

    /// Parses a single chord token: "Ctrl+Shift+P", "⌘⇧P", "C-x", "Cmd-K".
    static func parseChord(_ token: String) -> [String]? {
        guard !token.isEmpty else { return nil }

        // Symbol modifiers followed by a single key, including "+" itself: ⌘+, ⌘-, ⌘/
        let leadingSymbols = token.prefix { modifierSymbolChars.contains($0) }
        if !leadingSymbols.isEmpty, token.count - leadingSymbols.count == 1 {
            let key = String(token.last!)
            return isValidKey(key) ? leadingSymbols.map(String.init) + [key] : nil
        }

        // Plus-separated, allowing "Ctrl++" for the plus key itself.
        if token.count > 1, token.contains("+") {
            var parts = token.components(separatedBy: "+")
            if token.hasSuffix("++") {
                parts = Array(token.dropLast(2).components(separatedBy: "+")) + ["+"]
            }
            let keys = parts.filter { !$0.isEmpty }
            guard keys.count >= 2 || (keys.count == 1 && keys[0] == "+") else { return nil }
            return keys.allSatisfy(isValidKey) ? keys : nil
        }

        // Caret notation from terminals: ^C, ^Z, ^[  (a lone "^" is just the caret key)
        if token.count == 2, token.first == "^", let key = token.last, key.isLetter || "@[]\\_?".contains(key) {
            return ["Ctrl", String(key).uppercased()]
        }

        // Emacs notation: C-x, M-f, C-M-s, s-a
        if token.range(of: #"^([CMSs]-)+\S+$"#, options: .regularExpression) != nil {
            var keys: [String] = []
            var rest = Substring(token)
            while rest.count > 2, rest.dropFirst().first == "-", let letter = rest.first, "CMSs".contains(letter) {
                keys.append(["C": "Ctrl", "M": "Meta", "S": "Shift", "s": "Super"][String(letter)]!)
                rest = rest.dropFirst(2)
            }
            let final = String(rest)
            guard isValidKey(final) else { return nil }
            return keys + [final]
        }

        // Dash-separated names: Cmd-Shift-P (only when every part is a known key name).
        if token.count > 2, token.contains("-"), !token.hasPrefix("-") {
            let parts = token.components(separatedBy: "-").filter { !$0.isEmpty }
            if parts.count >= 2, parts.dropLast().allSatisfy(isModifier), isValidKey(parts.last!) {
                return parts
            }
        }

        // Leading modifier symbols: ⌘⇧P, ⌃⌥⌘Space
        let symbolPrefix = token.prefix { modifierSymbolChars.contains($0) }
        if !symbolPrefix.isEmpty {
            let rest = String(token.dropFirst(symbolPrefix.count))
            let mods = symbolPrefix.map(String.init)
            if rest.isEmpty { return mods }
            guard isValidKey(rest) else { return nil }
            return mods + [rest]
        }

        return isValidKey(token) ? [token] : nil
    }

    public static func isModifier(_ key: String) -> Bool { modifierNames[key.lowercased()] != nil }
    static func isSpecial(_ key: String) -> Bool {
        specialNames[key.lowercased()] != nil || functionKeyNumber(key) != nil
    }

    static func isValidKey(_ key: String) -> Bool {
        if key.count == 1, let ch = key.first {
            if ch.isWhitespace { return false }
            if ch.isLetter || ch.isNumber || ch.isASCII { return true }
            return specialNames[key] != nil || modifierNames[key] != nil
        }
        if isModifier(key) || isSpecial(key) { return true }
        let lower = key.lowercased()
        if lower.hasPrefix("num") || lower.hasPrefix("kp") {
            return key.dropFirst(lower.hasPrefix("num") ? 3 : 2).count <= 2
        }
        return false
    }

    private static func functionKeyNumber(_ key: String) -> Int? {
        guard key.count >= 2, key.first == "F" || key.first == "f", let n = Int(key.dropFirst()), (1...24).contains(n) else { return nil }
        return n
    }

    // MARK: - Display

    /// Display strings for a chord in the requested style.
    public static func display(_ chord: [String], style: ModifierStyle) -> [String] {
        let hasModifier = chord.contains(where: isModifier)
        return chord.map { key in
            let lower = key.lowercased()
            switch style {
            case .asWritten:
                return key.count == 1 && hasModifier ? key.uppercased() : key
            case .symbols:
                if let symbol = modifierNames[lower] { return symbol }
                if let special = specialNames[lower] { return special }
                if let n = functionKeyNumber(key) { return "F\(n)" }
                return key.count == 1 && hasModifier ? key.uppercased() : key
            case .names:
                if let symbol = modifierNames[lower] {
                    return ["⌘": "Cmd", "⌃": "Ctrl", "⌥": "Opt", "⇧": "Shift", "⊞": "Win", "fn": "Fn", "✦": "Hyper"][symbol] ?? key
                }
                if let special = specialNames[lower] {
                    return ["⇥": "Tab", "↩": "Return", "⌫": "Delete", "⌦": "Fwd Del", "↑": "Up", "↓": "Down",
                            "←": "Left", "→": "Right", "⇪": "Caps", "esc": "Esc", "⌤": "Enter"][special] ?? special
                }
                if let n = functionKeyNumber(key) { return "F\(n)" }
                return key.count == 1 && hasModifier ? key.uppercased() : key
            }
        }
    }

    /// For symbol style, joins a chord into one Mac-style keycap label with modifiers in canonical order.
    public static func compactSymbolLabel(_ displayKeys: [String]) -> String {
        let mods = displayKeys.filter { symbolOrder.contains($0) }
            .sorted { symbolOrder.firstIndex(of: $0)! < symbolOrder.firstIndex(of: $1)! }
        let rest = displayKeys.filter { !symbolOrder.contains($0) }
        let separator = rest.contains { $0.count > 1 } || mods.contains("fn") ? " " : ""
        return (mods.joined() + separator + rest.joined(separator: " ")).trimmingCharacters(in: .whitespaces)
    }
}
