import Foundation

// Formulas are stored as inline Markdown text: Unicode where it is reliable (², ₃, √, ∑, ℝ…) and
// Apple's extended attribute syntax for the rest, e.g. `x^[n−1](script: 1)` for a superscript
// and `a^[i,j](script: -1)` for a subscript. The overlay renders script runs with a baseline shift.

// MARK: - Script attribute

/// `script: 1` = superscript, `script: -1` = subscript.
public enum ScriptAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
    public typealias Value = Int
    public static let name = "script"
}

extension AttributeScopes {
    public struct CheetAttributes: AttributeScope {
        public let script: ScriptAttribute
        public let foundation: FoundationAttributes
    }

    public var cheet: CheetAttributes.Type { CheetAttributes.self }
}

extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.CheetAttributes, T>) -> T {
        self[T.self]
    }
}

public enum MathScript {
    static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "−": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ",
    ]
    static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "−": "₋", "=": "₌", "(": "₍", ")": "₎",
    ]
    /// Wider sets, used only when flattening to plain text (e.g. for the clipboard).
    static let plainSuperscripts: [Character: Character] = superscripts.merging([
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "j": "ʲ", "k": "ᵏ",
        "l": "ˡ", "m": "ᵐ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ", "v": "ᵛ", "w": "ʷ",
        "x": "ˣ", "y": "ʸ", "z": "ᶻ", " ": " ",
    ]) { a, _ in a }
    static let plainSubscripts: [Character: Character] = subscripts.merging([
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
        "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ", " ": " ",
    ]) { a, _ in a }

    public static func superscript(_ markdown: String) -> String { script(markdown, raised: true) }
    public static func `subscript`(_ markdown: String) -> String { script(markdown, raised: false) }

    private static func script(_ markdown: String, raised: Bool) -> String {
        let text = markdown.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return "" }
        let map = raised ? superscripts : subscripts
        if text.allSatisfy({ map[$0] != nil }) {
            return String(text.map { map[$0]! })
        }
        // Scripts can't nest in the attribute syntax, so flatten any inner markup first.
        let plain = markdown.contains("](script:") || markdown.contains("](") ? InlineMarkdown.plainText(text) : text
        let inner = plain == text ? text : InlineMarkdown.escape(plain)
        return "^[\(inner)](script: \(raised ? 1 : -1))"
    }

    /// Plain-text form of a script run for copying/searching: Unicode if possible, else ^(…) / _(…).
    static func flatten(_ text: String, raised: Bool) -> String {
        let map = raised ? plainSuperscripts : plainSubscripts
        if text.allSatisfy({ map[$0] != nil }) { return String(text.map { map[$0]! }) }
        return (raised ? "^" : "_") + (text.count == 1 ? text : "(\(text))")
    }
}

// MARK: - LaTeX

/// Converts TeX math (as used by MathJax, KaTeX, Wikipedia, codecogs images…) to inline Markdown.
public enum TeXConverter {
    public static func convert(_ tex: String) -> String {
        var parser = Parser(Array(tex))
        let result = parser.parseSequence(untilGroupEnd: false)
        return spaceAfterBigOperators(collapseSpaces(result))
    }

    /// Collapses runs of ordinary spaces only; deliberate thin/em spaces survive.
    static func collapseSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }

    private static let bigOperatorSpacing = try! NSRegularExpression(
        pattern: #"((?:[∑∏∐∫∬∭∮⋃⋂]|\b(?:sin|cos|tan|sec|csc|cot|sinh|cosh|tanh|arcsin|arccos|arctan|log|ln|lg|exp|det)(?=[⁰¹²³⁴⁵⁶⁷⁸⁹ⁱⁿ⁺⁻⁼⁽⁾₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎^]))(?:[⁰¹²³⁴⁵⁶⁷⁸⁹ⁱⁿ⁺⁻⁼⁽⁾₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎]|\^\[[^\]]*\]\(script: -?1\))*)(?=[\p{L}\p{N}(√])"#
    )

    /// TeX puts a thin space between ∑/∫ (with their limits) and what follows.
    static func spaceAfterBigOperators(_ text: String) -> String {
        bigOperatorSpacing.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1\u{2009}")
    }

    static let symbols: [String: String] = [
        // Greek
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ", "varepsilon": "ε", "zeta": "ζ",
        "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν",
        "xi": "ξ", "omicron": "ο", "pi": "π", "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ", "sigma": "σ", "varsigma": "ς",
        "tau": "τ", "upsilon": "υ", "phi": "ϕ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ",
        "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        // Big operators
        "sum": "∑", "prod": "∏", "coprod": "∐", "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮",
        "bigcup": "⋃", "bigcap": "⋂", "bigoplus": "⨁", "bigotimes": "⨂",
        // Binary operators
        "times": "×", "cdot": "⋅", "div": "÷", "pm": "±", "mp": "∓", "ast": "∗", "star": "⋆", "circ": "∘",
        "bullet": "∙", "oplus": "⊕", "ominus": "⊖", "otimes": "⊗", "odot": "⊙", "cup": "∪", "cap": "∩",
        "setminus": "∖", "wedge": "∧", "land": "∧", "vee": "∨", "lor": "∨", "neg": "¬", "lnot": "¬",
        // Relations
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠", "approx": "≈", "equiv": "≡",
        "sim": "∼", "simeq": "≃", "cong": "≅", "propto": "∝", "ll": "≪", "gg": "≫", "prec": "≺", "succ": "≻",
        "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂", "supset": "⊃", "subseteq": "⊆", "supseteq": "⊇",
        "perp": "⊥", "parallel": "∥", "mid": "∣", "models": "⊨", "vdash": "⊢", "coloneqq": "≔",
        // Arrows
        "to": "→", "rightarrow": "→", "leftarrow": "←", "gets": "←", "leftrightarrow": "↔", "Rightarrow": "⇒",
        "Leftarrow": "⇐", "Leftrightarrow": "⇔", "implies": "⟹", "impliedby": "⟸", "iff": "⟺", "mapsto": "↦",
        "longrightarrow": "⟶", "longleftarrow": "⟵", "uparrow": "↑", "downarrow": "↓", "nearrow": "↗", "searrow": "↘",
        // Misc symbols
        "infty": "∞", "partial": "∂", "nabla": "∇", "forall": "∀", "exists": "∃", "nexists": "∄", "emptyset": "∅",
        "varnothing": "∅", "angle": "∠", "triangle": "△", "square": "□", "degree": "°", "prime": "′", "hbar": "ℏ",
        "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ", "wp": "℘", "top": "⊤", "bot": "⊥", "therefore": "∴",
        "because": "∵", "surd": "√", "checkmark": "✓", "dagger": "†", "ddagger": "‡", "S": "§", "P": "¶",
        "ldots": "…", "dots": "…", "cdots": "⋯", "vdots": "⋮", "ddots": "⋱",
        // Delimiters
        "langle": "⟨", "rangle": "⟩", "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉", "vert": "|",
        "Vert": "‖", "lvert": "|", "rvert": "|", "lVert": "‖", "rVert": "‖", "lbrace": "{", "rbrace": "}",
        "backslash": "∖",
        // Spacing
        "quad": "\u{2003}", "qquad": "\u{2003}\u{2003}", "enspace": "\u{2002}", "thinspace": "\u{2009}",
    ]

    static let functions: Set<String> = [
        "sin", "cos", "tan", "sec", "csc", "cot", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "coth",
        "log", "ln", "lg", "exp", "lim", "limsup", "liminf", "sup", "inf", "max", "min", "det", "dim", "ker",
        "gcd", "lcm", "deg", "arg", "Pr", "hom", "mod", "sgn", "tr", "rank", "span", "argmax", "argmin",
    ]

    /// Relations and operators get spaces around them; + and − only when used as binary operators.
    static let spacedRelations: Set<String> = [
        "=", "<", ">", "≤", "≥", "≠", "≈", "≡", "∼", "≃", "≅", "∝", "≪", "≫", "∈", "∉", "∋", "⊂", "⊃", "⊆", "⊇",
        "→", "←", "↔", "⇒", "⇐", "⇔", "⟹", "⟸", "⟺", "↦", "⟶", "⟵", "⊨", "⊢", "≔", "∣",
    ]
    static let binaryOperators: Set<String> = ["+", "−", "±", "∓", "×", "÷", "⋅", "∪", "∩", "∖", "∧", "∨", "⊕", "⊗", "∘"]

    static let accents: [String: String] = [
        "hat": "\u{0302}", "widehat": "\u{0302}", "check": "\u{030C}", "tilde": "\u{0303}", "widetilde": "\u{0303}",
        "acute": "\u{0301}", "grave": "\u{0300}", "dot": "\u{0307}", "ddot": "\u{0308}", "breve": "\u{0306}",
        "bar": "\u{0304}", "overline": "\u{0305}", "vec": "\u{20D7}", "overrightarrow": "\u{20D7}",
        "underline": "\u{0332}",
    ]

    static func alphabet(_ text: String, _ style: String) -> String {
        let special: [String: [Character: String]] = [
            "mathbb": ["C": "ℂ", "H": "ℍ", "N": "ℕ", "P": "ℙ", "Q": "ℚ", "R": "ℝ", "Z": "ℤ"],
            "mathcal": ["B": "ℬ", "E": "ℰ", "F": "ℱ", "H": "ℋ", "I": "ℐ", "L": "ℒ", "M": "ℳ", "R": "ℛ", "e": "ℯ", "g": "ℊ", "o": "ℴ"],
            "mathfrak": ["C": "ℭ", "H": "ℌ", "I": "ℑ", "R": "ℜ", "Z": "ℨ"],
        ]
        let base: [String: (upper: UInt32, lower: UInt32?, digit: UInt32?)] = [
            "mathbb": (0x1D538, 0x1D552, 0x1D7D8),
            "mathcal": (0x1D49C, 0x1D4B6, nil),
            "mathfrak": (0x1D504, 0x1D51E, nil),
        ]
        guard let origin = base[style] else { return text }
        return text.map { ch -> String in
            if let s = special[style]?[ch] { return s }
            guard let ascii = ch.asciiValue else { return String(ch) }
            let value: UInt32?
            switch ch {
            case "A"..."Z": value = origin.upper + UInt32(ascii - 65)
            case "a"..."z": value = origin.lower.map { $0 + UInt32(ascii - 97) }
            case "0"..."9": value = origin.digit.map { $0 + UInt32(ascii - 48) }
            default: value = nil
            }
            return value.flatMap(UnicodeScalar.init).map { String(Character($0)) } ?? String(ch)
        }.joined()
    }

    struct Parser {
        let chars: [Character]
        var i = 0
        /// The last emitted token, for binary-operator spacing.
        var lastWasOperand = false
        /// Inside a superscript/subscript operators stay tight: a_{n+1}, not a_{n + 1}.
        var scriptDepth = 0

        init(_ chars: [Character]) { self.chars = chars }

        var atEnd: Bool { i >= chars.count }
        var peek: Character? { atEnd ? nil : chars[i] }

        mutating func skipSpaces() {
            while let c = peek, c.isWhitespace { i += 1 }
        }

        mutating func parseSequence(untilGroupEnd: Bool, stopAtEnd env: String? = nil) -> String {
            var out = ""
            lastWasOperand = false
            while let c = peek {
                if c == "}" {
                    if untilGroupEnd { i += 1; return out }
                    i += 1
                    continue
                }
                if let env, lookingAt("\\end{\(env)}") {
                    i += "\\end{\(env)}".count
                    return out
                }
                switch c {
                case "{":
                    i += 1
                    let group = parseSequence(untilGroupEnd: true)
                    out += group
                    lastWasOperand = !group.isEmpty
                case "^", "_":
                    i += 1
                    scriptDepth += 1
                    let arg = parseArgument()
                    scriptDepth -= 1
                    out += c == "^" ? MathScript.superscript(arg) : MathScript.subscript(arg)
                    lastWasOperand = true
                case "\\":
                    out += parseCommand()
                case "&":
                    i += 1
                    out += "\u{2003}"
                    lastWasOperand = false
                case "~":
                    i += 1
                    out += " "
                case "'":
                    var primes = 0
                    while peek == "'" { primes += 1; i += 1 }
                    out += primes == 1 ? "′" : primes == 2 ? "″" : String(repeating: "′", count: primes)
                case _ where c.isWhitespace:
                    i += 1
                default:
                    i += 1
                    out += emit(literal(c))
                }
            }
            return out
        }

        func lookingAt(_ text: String) -> Bool {
            let target = Array(text)
            guard i + target.count <= chars.count else { return false }
            return Array(chars[i..<(i + target.count)]) == target
        }

        func literal(_ c: Character) -> String {
            switch c {
            case "-": "−"
            case "*": "∗"
            case "[", "]", "`", "_": InlineMarkdown.escape(String(c))
            default: String(c)
            }
        }

        /// Emits a symbol, adding spaces around relations and binary operators.
        mutating func emit(_ symbol: String) -> String {
            if scriptDepth > 0, TeXConverter.spacedRelations.contains(symbol) || TeXConverter.binaryOperators.contains(symbol) {
                lastWasOperand = false
                return symbol
            }
            if TeXConverter.spacedRelations.contains(symbol) {
                lastWasOperand = false
                return " \(symbol) "
            }
            if TeXConverter.binaryOperators.contains(symbol) {
                let binary = lastWasOperand
                lastWasOperand = false
                return binary ? " \(symbol) " : symbol
            }
            lastWasOperand = !(symbol == "(" || symbol == "[" || symbol == "{" || symbol == "," || symbol.allSatisfy(\.isWhitespace))
            return symbol
        }

        /// A single-token or braced argument.
        mutating func parseArgument() -> String {
            skipSpaces()
            guard let c = peek else { return "" }
            if c == "{" {
                i += 1
                let saved = lastWasOperand
                let group = parseSequence(untilGroupEnd: true)
                lastWasOperand = saved
                return group
            }
            if c == "\\" {
                let saved = lastWasOperand
                let command = parseCommand()
                lastWasOperand = saved
                return command.trimmingCharacters(in: .whitespaces)
            }
            i += 1
            return literal(c)
        }

        /// Raw text inside braces (for \text{…}), unescaped TeX spaces kept.
        mutating func parseTextArgument() -> String {
            skipSpaces()
            guard peek == "{" else { return parseArgument() }
            i += 1
            var depth = 1
            var text = ""
            while let c = peek {
                i += 1
                if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { break } }
                if c == "\\", let next = peek, "{}$%&#_ ".contains(next) {
                    text.append(next)
                    i += 1
                    continue
                }
                if depth > 0 { text.append(c) }
            }
            return InlineMarkdown.escape(text)
        }

        mutating func optionalArgument() -> String? {
            skipSpaces()
            guard peek == "[" else { return nil }
            i += 1
            var text = ""
            var depth = 0
            while let c = peek {
                i += 1
                if c == "{" { depth += 1 }
                if c == "}" { depth -= 1 }
                if c == "]" && depth == 0 { break }
                text.append(c)
            }
            return TeXConverter.convert(text)
        }

        mutating func parseCommand() -> String {
            i += 1 // backslash
            guard let first = peek else { return "" }
            if !first.isLetter {
                i += 1
                switch first {
                case ",", ":", ";", ">": return "\u{2009}"
                case "!": return ""
                case " ": return " "
                case "\\":
                    lastWasOperand = false
                    return "; "
                case "{": return emit("{")
                case "}": return emit("}")
                case "|": return emit("‖")
                default: return emit(InlineMarkdown.escape(String(first)))
                }
            }
            var name = ""
            while let c = peek, c.isLetter { name.append(c); i += 1 }

            if let symbol = TeXConverter.symbols[name] {
                return emit(symbol)
            }
            if TeXConverter.functions.contains(name) {
                lastWasOperand = true
                let next = chars.dropFirst(i).first { !$0.isWhitespace }
                return name + (next.map { $0.isLetter || $0.isNumber || $0 == "\\" } == true ? "\u{2009}" : "")
            }
            if let mark = TeXConverter.accents[name] {
                let arg = parseArgument()
                lastWasOperand = true
                let plain = InlineMarkdown.plainText(arg)
                if plain.count == 1 || name == "overline" || name == "underline" {
                    return plain.map { String($0) + mark }.joined()
                }
                return plain + mark
            }

            switch name {
            case "frac", "dfrac", "tfrac", "cfrac":
                let numerator = parseArgument()
                let denominator = parseArgument()
                lastWasOperand = true
                return TeXConverter.fraction(numerator, denominator)
            case "binom", "dbinom", "tbinom":
                let n = parseArgument(), k = parseArgument()
                lastWasOperand = true
                return "C(\(n), \(k))"
            case "sqrt":
                let index = optionalArgument()
                let radicand = parseArgument()
                lastWasOperand = true
                return (index.map(MathScript.superscript) ?? "") + "√" + TeXConverter.wrapIfNeeded(radicand)
            case "text", "textrm", "textnormal", "mbox", "hbox", "textsf", "texttt", "operatorname", "mathrm", "mathsf", "mathtt", "rm":
                let text = name == "operatorname" || name.hasPrefix("math") ? parseArgument() : parseTextArgument()
                lastWasOperand = true
                return text
            case "textbf", "mathbf", "boldsymbol", "bm", "bf":
                let text = name == "textbf" ? parseTextArgument() : parseArgument()
                lastWasOperand = true
                return text.isEmpty ? "" : "**\(text)**"
            case "textit", "mathit", "emph", "it", "mathnormal":
                let text = name.hasPrefix("text") || name == "emph" ? parseTextArgument() : parseArgument()
                lastWasOperand = true
                return text.isEmpty ? "" : "*\(text)*"
            case "mathbb", "mathcal", "mathscr", "mathfrak", "Bbb":
                let text = InlineMarkdown.plainText(parseArgument())
                lastWasOperand = true
                let style = name == "mathscr" ? "mathcal" : name == "Bbb" ? "mathbb" : name
                return TeXConverter.alphabet(text, style)
            case "left", "right", "middle", "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr", "biggl", "biggr", "Biggl", "Biggr":
                skipSpaces()
                if peek == "." { i += 1; return "" }
                return ""
            case "displaystyle", "textstyle", "scriptstyle", "scriptscriptstyle", "limits", "nolimits", "nonumber", "notag", "strut":
                return ""
            case "label", "hspace", "vspace", "phantom", "hphantom", "vphantom":
                _ = parseArgument()
                return ""
            case "tag":
                return " (\(parseArgument()))"
            case "mod", "bmod":
                lastWasOperand = false
                return " mod "
            case "pmod":
                lastWasOperand = true
                return " (mod \(parseArgument()))"
            case "not":
                skipSpaces()
                if peek == "=" { i += 1; return emit("≠") }
                let next = parseArgument()
                let negated: [String: String] = ["∈": "∉", "≡": "≢", "⊂": "⊄", "⊆": "⊈", "∃": "∄", "∼": "≁", "≈": "≉"]
                let trimmed = next.trimmingCharacters(in: .whitespaces)
                return emit(negated[trimmed] ?? (trimmed + "\u{0338}"))
            case "overset", "stackrel":
                let over = parseArgument(), base = parseArgument()
                lastWasOperand = true
                return base + MathScript.superscript(over)
            case "underset":
                let under = parseArgument(), base = parseArgument()
                lastWasOperand = true
                return base + MathScript.subscript(under)
            case "overbrace", "underbrace":
                return parseArgument()
            case "begin":
                let env = InlineMarkdown.plainText(parseArgument())
                if env == "array" || env == "tabular" { _ = parseArgument() }
                let body = parseSequence(untilGroupEnd: false, stopAtEnd: env)
                lastWasOperand = true
                return TeXConverter.environment(env, body)
            case "end":
                _ = parseArgument()
                return ""
            default:
                lastWasOperand = true
                return name
            }
        }
    }

    /// True when nothing at the top level (outside brackets) could bind looser than a fraction bar.
    static func isAtomic(_ markdown: String) -> Bool {
        let plain = InlineMarkdown.plainText(markdown)
        guard !plain.isEmpty else { return false }
        var depth = 0
        for ch in plain {
            if "([{⟨".contains(ch) { depth += 1; continue }
            if ")]}⟩".contains(ch) { depth -= 1; continue }
            if depth == 0, ch == " " || "+−-±∓=/×⋅,;<>≤≥≠".contains(ch) { return false }
        }
        return true
    }

    static func wrapIfNeeded(_ markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespaces)
        return isAtomic(trimmed) ? trimmed : "(\(trimmed))"
    }

    static let vulgarFractions: [String: String] = [
        "1/2": "½", "1/3": "⅓", "2/3": "⅔", "1/4": "¼", "3/4": "¾", "1/5": "⅕", "2/5": "⅖", "3/5": "⅗",
        "4/5": "⅘", "1/6": "⅙", "5/6": "⅚", "1/8": "⅛", "3/8": "⅜", "5/8": "⅝", "7/8": "⅞",
    ]

    static func fraction(_ numerator: String, _ denominator: String) -> String {
        let n = numerator.trimmingCharacters(in: .whitespaces), d = denominator.trimmingCharacters(in: .whitespaces)
        if let vulgar = vulgarFractions["\(n)/\(d)"] { return vulgar }
        return "\(wrapIfNeeded(n))/\(wrapIfNeeded(d))"
    }

    static func environment(_ name: String, _ body: String) -> String {
        var rows = body.components(separatedBy: "; ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        switch name {
        case "cases", "dcases", "rcases":
            rows = rows.map { $0.replacingOccurrences(of: "\u{2003}", with: ", ").replacingOccurrences(of: ",  ", with: ", ") }
            return "{ " + rows.joined(separator: "; ")
        case "pmatrix", "smallmatrix": return "(" + rows.joined(separator: "; ") + ")"
        case "bmatrix": return "[" + rows.joined(separator: "; ") + "]"
        case "Bmatrix": return "{" + rows.joined(separator: "; ") + "}"
        case "vmatrix": return "|" + rows.joined(separator: "; ") + "|"
        case "Vmatrix": return "‖" + rows.joined(separator: "; ") + "‖"
        default: return rows.joined(separator: "; ").replacingOccurrences(of: "\u{2003}", with: " ")
        }
    }
}

// MARK: - MathML

/// Converts presentation MathML (`<math>…</math>`) to inline Markdown.
public enum MathMLConverter {
    public static func convert(_ xml: String) -> String? {
        let prepared = HTMLImporter.decodeEntities(xml, keepingXMLEscapes: true)
        guard let document = try? XMLDocument(xmlString: prepared, options: [.nodeLoadExternalEntitiesNever]),
              let root = document.rootElement() else { return nil }
        let cleaned = TeXConverter.spaceAfterBigOperators(TeXConverter.collapseSpaces(render(root)))
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func name(_ node: XMLNode) -> String {
        ((node as? XMLElement)?.localName ?? node.name ?? "").lowercased()
    }

    private static func children(_ node: XMLNode) -> [XMLElement] {
        (node.children ?? []).compactMap { $0 as? XMLElement }
    }

    /// Text of token elements, ignoring comments (Wikipedia annotates operators with `<!-- − -->`).
    private static func textContent(_ node: XMLNode) -> String {
        if node.kind == .text { return node.stringValue ?? "" }
        if node.kind == .comment { return "" }
        return (node.children ?? []).map(textContent).joined()
    }

    private static let bigOperators: Set<String> = ["∑", "∏", "∐", "∫", "∬", "∭", "∮", "⋃", "⋂", "lim", "max", "min", "sup", "inf"]

    static func render(_ node: XMLNode, tight: Bool = false) -> String {
        let render = { (child: XMLNode) in Self.render(child, tight: tight) }
        let script = { (child: XMLNode) in Self.render(child, tight: true) }
        guard let element = node as? XMLElement else {
            return node.kind == .text ? InlineMarkdown.escape(node.stringValue ?? "") : ""
        }
        let kids = children(element)
        switch name(element) {
        case "annotation", "annotation-xml", "mphantom", "none", "mprescripts":
            return ""
        case "semantics":
            return kids.first.map(render) ?? ""
        case "mi", "mn", "mtext", "ms":
            let text = textContent(element).trimmingCharacters(in: .whitespacesAndNewlines)
            return InlineMarkdown.escape(text.replacingOccurrences(of: "-", with: "−"))
        case "mo":
            let op = textContent(element).trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "-", with: "−")
                .replacingOccurrences(of: "\u{2061}", with: "") // function application
                .replacingOccurrences(of: "\u{2062}", with: "") // invisible times
            let hasPrevious = element.previousSibling != nil
            if tight { return op == "," ? "," : InlineMarkdown.escape(op) }
            if TeXConverter.spacedRelations.contains(op) { return " \(op) " }
            if TeXConverter.binaryOperators.contains(op) { return hasPrevious ? " \(op) " : op }
            if op == "," { return ", " }
            return InlineMarkdown.escape(op)
        case "mspace":
            return " "
        case "msup" where kids.count >= 2:
            return render(kids[0]) + MathScript.superscript(script(kids[1]))
        case "msub" where kids.count >= 2:
            return render(kids[0]) + MathScript.subscript(script(kids[1]))
        case "msubsup" where kids.count >= 3:
            return render(kids[0]) + MathScript.subscript(script(kids[1])) + MathScript.superscript(script(kids[2]))
        case "munder" where kids.count >= 2:
            let under = script(kids[1])
            if under.trimmingCharacters(in: .whitespaces) == "_" || under == "\u{0332}" { return render(kids[0]) + "\u{0332}" }
            return render(kids[0]) + MathScript.subscript(under)
        case "mover" where kids.count >= 2:
            let base = render(kids[0])
            let over = InlineMarkdown.plainText(render(kids[1])).trimmingCharacters(in: .whitespaces)
            let accents: [String: String] = ["¯": "\u{0304}", "‾": "\u{0305}", "^": "\u{0302}", "ˆ": "\u{0302}", "~": "\u{0303}", "˜": "\u{0303}",
                                             "˙": "\u{0307}", "¨": "\u{0308}", "→": "\u{20D7}", "⃗": "\u{20D7}", "ˇ": "\u{030C}"]
            if let mark = accents[over] {
                let plain = InlineMarkdown.plainText(base)
                return plain.count <= 1 || over == "‾" || over == "¯" ? plain.map { String($0) + mark }.joined() : plain + mark
            }
            return base + MathScript.superscript(script(kids[1]))
        case "munderover" where kids.count >= 3:
            return render(kids[0]) + MathScript.subscript(script(kids[1])) + MathScript.superscript(script(kids[2]))
        case "mfrac" where kids.count >= 2:
            return TeXConverter.fraction(render(kids[0]), render(kids[1]))
        case "msqrt":
            return "√" + TeXConverter.wrapIfNeeded(kids.map(render).joined())
        case "mroot" where kids.count >= 2:
            return MathScript.superscript(script(kids[1])) + "√" + TeXConverter.wrapIfNeeded(render(kids[0]))
        case "mfenced":
            let open = element.attribute(forName: "open")?.stringValue ?? "("
            let close = element.attribute(forName: "close")?.stringValue ?? ")"
            let separator = element.attribute(forName: "separators")?.stringValue ?? ","
            return open + kids.map(render).joined(separator: separator + " ") + close
        case "mtable":
            return kids.map { row in children(row).map(render).joined(separator: "\u{2003}") }.joined(separator: "; ")
        case "mtr", "mlabeledtr":
            return kids.map(render).joined(separator: "\u{2003}")
        case "mmultiscripts":
            return kids.first.map(render) ?? ""
        default:
            // math, mrow, mstyle, mpadded, menclose, merror, mtd, maction…
            return (element.children ?? []).map(render).joined()
        }
    }

    /// TeX source carried alongside MathML (Wikipedia, KaTeX), for when the MathML can't be read.
    static func texAnnotation(in xml: String) -> String? {
        for pattern in [#"<annotation[^>]*encoding="application/x-tex"[^>]*>([\s\S]*?)</annotation>"#, #"alttext="([^"]*)""#] {
            if let range = xml.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let match = String(xml[range])
                let inner = match.replacingOccurrences(of: #"^<annotation[^>]*>|</annotation>$|^alttext="|"$"#, with: "", options: .regularExpression)
                let tex = HTMLImporter.decodeEntities(inner).trimmingCharacters(in: .whitespacesAndNewlines)
                if !tex.isEmpty { return tex }
            }
        }
        return nil
    }
}

// MARK: - HTML pre-pass

/// Finds math in raw HTML before it is tidied (tidying drops MathML tags and scripts) and replaces
/// each formula with a private-use placeholder; `resolve` swaps the converted Markdown back in.
struct MathPrepass {
    private(set) var formulas: [String] = []

    private static let open: Character = "\u{E000}"
    private static let close: Character = "\u{E001}"

    private mutating func token(for markdown: String, display: Bool) -> String {
        formulas.append(markdown)
        let token = "\(Self.open)\(formulas.count - 1)\(Self.close)"
        return display ? "<div>\(token)</div>" : token
    }

    mutating func process(_ html: String) -> String {
        var s = html
        let lower = html.lowercased()

        // 1. MathML (Wikipedia, KaTeX's accessible copy, MathJax 3's assistive MathML).
        if lower.contains("<math") {
            s = Self.replace(in: s, pattern: #"<math\b[\s\S]*?</math\s*>"#) { match in
                let display = match.range(of: #"display\s*=\s*"block""#, options: .regularExpression) != nil
                let converted = MathMLConverter.convert(match) ?? MathMLConverter.texAnnotation(in: match).map(TeXConverter.convert) ?? ""
                return self.token(for: converted, display: display)
            }
        }

        // 2. MathJax 2 script blocks: <script type="math/tex">…</script>
        if lower.contains("math/tex") {
            s = Self.replace(in: s, pattern: #"<script[^>]*type\s*=\s*["']math/tex(;\s*mode=display)?["'][^>]*>([\s\S]*?)</script>"#) { match in
                let display = match.contains("mode=display")
                let tex = match.replacingOccurrences(of: #"^<script[^>]*>|</script>$"#, with: "", options: .regularExpression)
                return self.token(for: TeXConverter.convert(HTMLImporter.decodeEntities(tex)), display: display)
            }
            // MathJax previews duplicate the formula.
            s = s.replacingOccurrences(of: #"<span class="MathJax_Preview"[^>]*>[\s\S]*?</span>"#, with: "", options: .regularExpression)
        }

        // 3. Formula images whose alt text is TeX (codecogs, WordPress LaTeX, …). Wikipedia's fallback
        //    images are aria-hidden (their MathML was handled above) and are left for the walker to skip.
        s = Self.replace(in: s, pattern: #"<img\b[^>]*>"#) { tag in
            let lowerTag = tag.lowercased()
            guard !lowerTag.contains("aria-hidden=\"true\""),
                  lowerTag.range(of: #"(latex|codecogs|mathtex|/math/|tex\.cgi|class="[^"]*(math|tex|equation|latex))"#, options: .regularExpression) != nil,
                  let alt = tag.range(of: #"alt\s*=\s*"([^"]*)""#, options: .regularExpression)
            else { return tag }
            let tex = HTMLImporter.decodeEntities(String(tag[alt]).replacingOccurrences(of: #"^alt\s*=\s*"|"$"#, with: "", options: .regularExpression))
            guard !tex.trimmingCharacters(in: .whitespaces).isEmpty else { return tag }
            return self.token(for: TeXConverter.convert(tex), display: false)
        }

        // 4. Raw TeX in text, for pages that typeset math with JavaScript (which never runs here).
        let usesTeX = lower.contains("mathjax") || lower.contains("katex") || s.contains("\\(") || s.contains("\\[") || s.contains("$$")
        if usesTeX {
            s = Self.transformText(s) { text in
                var t = text
                t = self.replaceTeX(in: t, pattern: #"\$\$([\s\S]+?)\$\$"#, display: true)
                t = self.replaceTeX(in: t, pattern: #"\\\[([\s\S]+?)\\\]"#, display: true)
                t = self.replaceTeX(in: t, pattern: #"\\\(([\s\S]+?)\\\)"#, display: false)
                if lower.contains("mathjax") || lower.contains("katex") {
                    // $…$ only when the page is known to use it, and never "$5 and $10".
                    t = self.replaceTeX(in: t, pattern: #"(?<![\\$\w])\$(?=[^\s$\d])([^$\n<>]{1,300}?[^\s$\\])\$(?![\w$])"#, display: false)
                }
                return t
            }
        }
        return s
    }

    private mutating func replaceTeX(in text: String, pattern: String, display: Bool) -> String {
        Self.replace(in: text, pattern: pattern, group: 1) { tex in
            self.token(for: TeXConverter.convert(HTMLImporter.decodeEntities(tex)), display: display)
        }
    }

    /// Applies `transform` only to text between tags, and never inside pre/code/script/style/textarea.
    private static func transformText(_ html: String, _ transform: (String) -> String) -> String {
        guard let tagRegex = try? NSRegularExpression(pattern: #"<[^>]+>"#) else { return html }
        var out = ""
        var cursor = html.startIndex
        var protectedDepth = 0
        let protected = ["pre", "code", "script", "style", "textarea", "kbd", "samp"]
        for match in tagRegex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let text = String(html[cursor..<range.lowerBound])
            out += protectedDepth > 0 ? text : transform(text)
            let tag = html[range].lowercased()
            if let name = protected.first(where: { tag.hasPrefix("<\($0)") && !tag.hasSuffix("/>") }) {
                _ = name
                protectedDepth += 1
            } else if protected.contains(where: { tag.hasPrefix("</\($0)") }) {
                protectedDepth = max(0, protectedDepth - 1)
            }
            out += html[range]
            cursor = range.upperBound
        }
        let tail = String(html[cursor...])
        out += protectedDepth > 0 ? tail : transform(tail)
        return out
    }

    private static func replace(in text: String, pattern: String, group: Int = 0, _ convert: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }
        var out = ""
        var cursor = text.startIndex
        for match in matches {
            guard let whole = Range(match.range, in: text), let part = Range(match.range(at: group), in: text) else { continue }
            out += text[cursor..<whole.lowerBound]
            out += convert(String(text[part]))
            cursor = whole.upperBound
        }
        out += text[cursor...]
        return out
    }

    /// Replaces placeholders in every string of the outline.
    func resolve(_ events: [OutlineEvent]) -> [OutlineEvent] {
        guard !formulas.isEmpty else { return events }
        return events.map { $0.mapStrings(resolve) }
    }

    func resolve(_ text: String) -> String {
        guard text.contains(Self.open) else { return text }
        var out = ""
        var number = ""
        var inToken = false
        for ch in text {
            if ch == Self.open { inToken = true; number = ""; continue }
            if ch == Self.close, inToken {
                inToken = false
                if let index = Int(number), formulas.indices.contains(index) { out += formulas[index] }
                continue
            }
            if inToken { number.append(ch) } else { out.append(ch) }
        }
        return out
    }
}

extension OutlineEvent {
    func mapStrings(_ transform: (String) -> String) -> OutlineEvent {
        switch self {
        case .heading(let level, let text): return .heading(level: level, text: transform(text))
        case .block(let block): return .block(block.mapStrings(transform))
        }
    }
}

extension CheetBlock {
    func mapStrings(_ transform: (String) -> String) -> CheetBlock {
        switch self {
        case .heading(let text): return .heading(transform(text))
        case .text(let text): return .text(transform(text))
        case .table(let table):
            return .table(CheetTable(headers: table.headers?.map(transform), rows: table.rows.map { $0.map(transform) }))
        case .list(let list): return .list(ListBlock(items: list.items.map(transform), ordered: list.ordered))
        case .code(let code):
            guard code.code.contains("\u{E000}") else { return self }
            return .code(CodeBlock(code: InlineMarkdown.plainText(transform(code.code)), language: code.language))
        case .image(var image):
            if image.alt.contains("\u{E000}") { image.alt = InlineMarkdown.plainText(transform(image.alt)) }
            image.caption = image.caption.map(transform)
            return .image(image)
        }
    }
}
