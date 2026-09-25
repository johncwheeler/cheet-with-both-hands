import Foundation

/// Extracts cheet structure from HTML: headings, tables, (definition) lists, code and paragraphs.
/// Inline formatting (`<code>`, `<kbd>`, `<b>`, `<a>` …) is preserved as inline Markdown.
public enum HTMLImporter {
    public struct Result {
        public var documentTitle: String?
        public var events: [OutlineEvent]
    }

    public static func parse(_ html: String, baseURL: URL? = nil) -> Result {
        var math = MathPrepass()
        let cleaned = preClean(math.process(html))
        let wrapped = cleaned.range(of: "<html", options: .caseInsensitive) == nil
            ? "<html><body>\(cleaned)</body></html>" : cleaned

        guard let document = try? XMLDocument(xmlString: wrapped, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let root = document.rootElement() else {
            // Last resort: strip tags and treat the rest as Markdown-ish text.
            let text = cleaned.replacingOccurrences(of: #"<[^>]+>"#, with: "\n", options: .regularExpression)
            return Result(documentTitle: nil, events: math.resolve(MarkdownImporter.events(from: decodeEntities(text))))
        }

        let walker = Walker()
        walker.baseURL = documentBase(html) ?? baseURL
        let body = root.elements(forLocalName: "body", uri: xhtmlNamespace).first
            ?? root.elements(forName: "body").first
            ?? root
        walker.walkChildren(of: body)
        walker.flushInline()

        return Result(documentTitle: documentTitle(root), events: math.resolve(walker.events))
    }

    /// `<base href>` resolved against nothing (it must be absolute to be useful).
    static func documentBase(_ html: String) -> URL? {
        guard let range = html.range(of: #"<base\b[^>]*href\s*=\s*"([^"]+)""#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let tag = String(html[range])
        guard let href = tag.range(of: #"href\s*=\s*"[^"]+""#, options: .regularExpression) else { return nil }
        let value = tag[href].replacingOccurrences(of: #"^href\s*=\s*"|"$"#, with: "", options: .regularExpression)
        let fixed = value.hasPrefix("//") ? "https:" + value : value
        return URL(string: fixed).flatMap { $0.scheme == nil ? nil : $0 }
    }

    /// A first row made of `<th>` cells, or of cells that are entirely bold, is a header.
    static func isHeaderRow(_ cells: [XMLElement], texts: [String]) -> Bool {
        let names = cells.map { ($0.localName ?? $0.name ?? "").lowercased() }
        if !names.isEmpty, names.allSatisfy({ $0 == "th" }) { return true }
        let filled = texts.filter { !$0.isEmpty }
        return filled.count >= 2 && filled.allSatisfy { $0.hasPrefix("**") && $0.hasSuffix("**") && $0.count > 4 && !$0.dropFirst(2).dropLast(2).contains("**") }
    }

    static func unbolded(_ text: String) -> String {
        guard text.hasPrefix("**"), text.hasSuffix("**"), text.count > 4 else { return text }
        return String(text.dropFirst(2).dropLast(2))
    }

    /// Soft hyphens and zero-width characters only get in the way of copying and searching.
    static func stripInvisibles(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { [0x00AD, 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF].contains($0.value) }) else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.filter { ![0x00AD, 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF].contains($0.value) }))
    }

    /// Resolves an image or link reference against the page.
    static func resolve(_ reference: String, against base: URL?) -> String? {
        let trimmed = decodeEntities(reference).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.lowercased().hasPrefix("javascript:") else { return nil }
        if trimmed.hasPrefix("data:") { return trimmed }
        if trimmed.hasPrefix("//") { return "https:" + trimmed }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            return scheme == "http" || scheme == "https" ? url.absoluteString : nil
        }
        guard let base, let resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              let scheme = resolved.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return resolved.absoluteString
    }

    static let xhtmlNamespace = "http://www.w3.org/1999/xhtml"

    /// The page's main content region (`<main>`, a single `<article>`, or `role="main"`), if it has one.
    public static func mainContent(_ html: String) -> String? {
        if occurrences(of: "<main\\b", in: html) == 1, let range = elementRange(tag: "main", in: html) {
            return String(html[range])
        }
        if occurrences(of: "<article\\b", in: html) == 1, let range = elementRange(tag: "article", in: html) {
            return String(html[range])
        }
        if let match = html.range(of: #"<([a-zA-Z][a-zA-Z0-9]*)\b[^>]*role\s*=\s*["']main["']"#, options: [.regularExpression, .caseInsensitive]),
           let tagMatch = html[match].range(of: #"^<[a-zA-Z][a-zA-Z0-9]*"#, options: .regularExpression) {
            let tag = String(html[match][tagMatch].dropFirst())
            if let range = elementRange(tag: tag, in: html, startingAt: match.lowerBound) { return String(html[range]) }
        }
        return nil
    }

    private static func occurrences(of pattern: String, in html: String) -> Int {
        (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?
            .numberOfMatches(in: html, range: NSRange(html.startIndex..., in: html)) ?? 0
    }

    /// The range of the first `<tag …>…</tag>` element (nesting-aware), from `start` onwards.
    static func elementRange(tag: String, in html: String, startingAt start: String.Index? = nil) -> Range<String.Index>? {
        guard let open = html.range(of: "<\(tag)\\b", options: [.regularExpression, .caseInsensitive], range: (start ?? html.startIndex)..<html.endIndex),
              let regex = try? NSRegularExpression(pattern: "<(/?)\(tag)\\b[^>]*>", options: .caseInsensitive) else { return nil }
        var depth = 0
        let searchRange = NSRange(open.lowerBound..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: searchRange) {
            let isClosing = (Range(match.range(at: 1), in: html).map { !html[$0].isEmpty }) ?? false
            depth += isClosing ? -1 : 1
            if depth == 0, let end = Range(match.range, in: html) {
                return open.lowerBound..<end.upperBound
            }
        }
        return nil
    }

    /// Inline Markdown for an element's content (links, code, emphasis kept), on one line.
    static func inlineText(of node: XMLNode, baseURL: URL? = nil) -> String {
        let walker = Walker()
        walker.baseURL = baseURL
        return InlineMarkdown.collapseWhitespace(walker.inlineMarkdown(node)).trimmed
    }

    /// Like `inlineText`, but `<br>` and paragraph breaks become line breaks.
    static func richText(of node: XMLNode, baseURL: URL? = nil) -> String {
        let walker = Walker()
        walker.preserveLineBreaks = true
        walker.baseURL = baseURL
        let raw = walker.inlineMarkdown(node)
        var lines: [String] = []
        for line in raw.components(separatedBy: "\n") {
            let collapsed = InlineMarkdown.collapseWhitespace(line).trimmed
            if collapsed.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(collapsed)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// Removes chrome and non-content elements before tidying (tidy drops unknown HTML5 tags but keeps their text).
    static func preClean(_ html: String) -> String {
        var s = html
        // Tidying drops HTML5 tags it doesn't know; keep figures recognisable.
        for tag in ["figure", "figcaption"] {
            s = s.replacingOccurrences(of: "<\(tag)\\b", with: "<div data-cheet=\"\(tag)\"", options: [.regularExpression, .caseInsensitive])
            s = s.replacingOccurrences(of: "</\(tag)\\s*>", with: "</div>", options: [.regularExpression, .caseInsensitive])
        }
        let patterns = [
            #"<!--[\s\S]*?-->"#,
            #"<(script|style|noscript|template|svg|nav|footer|aside|button|select|iframe|canvas|form)\b[^>]*>[\s\S]*?</\1\s*>"#,
            #"<(input|meta|link|source)\b[^>]*/?>"#,
        ]
        for pattern in patterns {
            s = s.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        return s
    }

    static func documentTitle(_ root: XMLElement) -> String? {
        guard let titleNode = try? root.nodes(forXPath: "//*[local-name()='title']").first,
              let raw = titleNode.stringValue else { return nil }
        var title = InlineMarkdown.collapseWhitespace(raw).trimmed
        for separator in [" | ", " — ", " – ", " · "] {
            if let range = title.range(of: separator) {
                title = String(title[..<range.lowerBound]).trimmed
            }
        }
        return title.isEmpty ? nil : title
    }

    /// Decodes named and numeric HTML entities.
    static let namedEntities: [String: String] = [
        "nbsp": " ", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "amp": "&", "shy": "",
        "ndash": "–", "mdash": "—", "hellip": "…", "laquo": "«", "raquo": "»", "copy": "©", "reg": "®", "trade": "™",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "rarr": "→", "larr": "←", "uarr": "↑", "darr": "↓",
        "harr": "↔", "rArr": "⇒", "lArr": "⇐", "hArr": "⇔", "times": "×", "divide": "÷", "plusmn": "±", "minus": "−",
        "le": "≤", "ge": "≥", "ne": "≠", "asymp": "≈", "equiv": "≡", "prop": "∝", "infin": "∞", "sum": "∑", "prod": "∏",
        "int": "∫", "radic": "√", "part": "∂", "nabla": "∇", "forall": "∀", "exist": "∃", "empty": "∅", "isin": "∈",
        "notin": "∉", "ni": "∋", "sub": "⊂", "sup": "⊃", "sube": "⊆", "supe": "⊇", "cup": "∪", "cap": "∩", "and": "∧",
        "or": "∨", "not": "¬", "ang": "∠", "perp": "⊥", "deg": "°", "micro": "µ", "middot": "·", "sdot": "⋅",
        "prime": "′", "Prime": "″", "frac12": "½", "frac14": "¼", "frac34": "¾", "sup1": "¹", "sup2": "²", "sup3": "³",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "zeta": "ζ", "eta": "η", "theta": "θ",
        "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "omicron": "ο", "pi": "π", "rho": "ρ",
        "sigma": "σ", "sigmaf": "ς", "tau": "τ", "upsilon": "υ", "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Phi": "Φ",
        "Psi": "Ψ", "Omega": "Ω", "lceil": "⌈", "rceil": "⌉", "lfloor": "⌊", "rfloor": "⌋", "lang": "⟨", "rang": "⟩",
        // MathML
        "InvisibleTimes": "", "it": "", "ApplyFunction": "", "af": "", "InvisibleComma": "", "ic": "",
        "PlusMinus": "±", "MinusPlus": "∓", "Integral": "∫", "Sum": "∑", "Product": "∏", "Sqrt": "√",
        "PartialD": "∂", "DifferentialD": "ⅆ", "dd": "ⅆ", "ExponentialE": "ⅇ", "ee": "ⅇ", "ImaginaryI": "ⅈ",
        "ii": "ⅈ", "Element": "∈", "NotElement": "∉", "LessEqual": "≤", "GreaterEqual": "≥", "NotEqual": "≠",
        "RightArrow": "→", "LeftArrow": "←", "Rightarrow": "⇒", "Infinity": "∞", "infty": "∞", "OverBar": "‾",
        "UnderBar": "_", "Hat": "^", "Tilde": "~", "ThinSpace": " ", "MediumSpace": " ", "NegativeThinSpace": "",
        "CenterDot": "·", "Cross": "⨯", "VerticalBar": "∣", "DoubleVerticalBar": "∥", "LeftAngleBracket": "⟨",
        "RightAngleBracket": "⟩", "NoBreak": "", "af;": "",
    ]

    /// Decodes named and numeric HTML entities. With `keepingXMLEscapes`, `&lt;` `&gt;` `&amp;` `&quot;`
    /// `&apos;` stay encoded so the result is still valid XML (used before parsing MathML).
    public static func decodeEntities(_ text: String, keepingXMLEscapes: Bool = false) -> String {
        guard text.contains("&") else { return text }
        let xmlEscapes: Set<String> = ["lt", "gt", "amp", "quot", "apos"]
        let named = namedEntities
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            guard let semi = after.prefix(10).firstIndex(of: ";") else {
                out += "&"
                rest = after
                continue
            }
            let entity = String(after[..<semi])
            var replacement: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                replacement = UInt32(entity.dropFirst(2), radix: 16).flatMap(UnicodeScalar.init).map { String(Character($0)) }
            } else if entity.hasPrefix("#") {
                replacement = UInt32(entity.dropFirst()).flatMap(UnicodeScalar.init).map { String(Character($0)) }
            } else if keepingXMLEscapes && xmlEscapes.contains(entity) {
                replacement = "&\(entity);"
            } else {
                replacement = named[entity]
            }
            if keepingXMLEscapes, let r = replacement, ["<", ">", "&"].contains(r) {
                replacement = r == "<" ? "&lt;" : r == ">" ? "&gt;" : "&amp;"
            }
            if let replacement {
                out += replacement.replacingOccurrences(of: "\u{00AD}", with: "")
                rest = after[after.index(after: semi)...]
            } else {
                out += "&"
                rest = after
            }
        }
        out += rest
        return out
    }

    // MARK: - Walker

    private static let blockTags: Set<String> = [
        "div", "section", "article", "main", "header", "body", "html", "details", "figure", "center",
        "address", "fieldset", "hgroup", "blockquote", "dd", "dt", "li", "caption", "summary", "figcaption", "p",
    ]
    private static let skipTags: Set<String> = [
        "script", "style", "noscript", "template", "head", "title", "nav", "footer", "aside",
        "button", "select", "option", "iframe", "svg", "canvas", "form", "input",
    ]

    final class Walker {
        var events: [OutlineEvent] = []
        /// Turn `<br>` and paragraphs into newlines instead of spaces (for free-form text blocks).
        var preserveLineBreaks = false
        /// Resolves relative image and link references.
        var baseURL: URL?
        private var inline = ""

        func walkChildren(of node: XMLNode) {
            for child in node.children ?? [] { walk(child) }
        }

        func flushInline() {
            let text = InlineMarkdown.collapseWhitespace(inline).trimmed
            if let image = InlineMarkdown.soleImage(text) {
                // A paragraph that is only an image becomes an image block.
                events.append(.block(.image(ImageBlock(source: image.source, alt: image.alt, caption: image.title))))
            } else if !text.isEmpty {
                events.append(.block(.text(text)))
            }
            inline = ""
        }

        /// Elements hidden from assistive tech are visual duplicates (KaTeX/MathJax renderings,
        /// Wikipedia's formula images) or decoration.
        fileprivate func isHidden(_ element: XMLElement) -> Bool {
            if element.attribute(forName: "aria-hidden")?.stringValue == "true" { return true }
            if element.attribute(forName: "hidden") != nil { return true }
            let classes = element.attribute(forName: "class")?.stringValue ?? ""
            return classes.contains("mwe-math-fallback") || classes.contains("katex-html")
        }

        /// `![alt](url)` for an `<img>`, or nil for spacers, tracking pixels and unresolvable sources.
        func imageMarkdown(_ image: XMLElement) -> String? {
            func attribute(_ name: String) -> String? {
                image.attribute(forName: name)?.stringValue.flatMap { $0.trimmed.isEmpty ? nil : $0 }
            }
            let alt = InlineMarkdown.collapseWhitespace(attribute("alt") ?? attribute("title") ?? "").trimmed
            let classes = (attribute("class") ?? "").lowercased()
            if classes.contains("emoji") { return alt.isEmpty ? nil : InlineMarkdown.escape(alt) }
            for dimension in ["width", "height"] {
                if let raw = attribute(dimension), let value = Int(String(raw.filter { $0.isNumber })), value <= 3 { return nil }
            }
            // Lazy-loading sites keep the real image in data-* attributes and a placeholder in src.
            var candidates = [attribute("data-src"), attribute("data-original"), attribute("data-lazy-src"), bestFromSrcset(attribute("srcset") ?? attribute("data-srcset"))]
            let src = attribute("src")
            if let src, !(src.hasPrefix("data:image/gif") || src.hasPrefix("data:image/svg")) || candidates.allSatisfy({ $0 == nil }) {
                candidates.insert(src, at: 0)
            }
            guard let raw = candidates.compactMap({ $0 }).first, let source = HTMLImporter.resolve(raw, against: baseURL) else { return nil }
            let lower = source.lowercased()
            if lower.contains("spacer") || lower.contains("pixel.gif") || lower.contains("blank.gif") || lower.contains("1x1") { return nil }
            return InlineMarkdown.imageMarkdown(alt: alt, source: source)
        }

        private func bestFromSrcset(_ srcset: String?) -> String? {
            guard let srcset else { return nil }
            var scored: [(url: String, density: Double)] = []
            for entry in srcset.split(separator: ",") {
                let parts = String(entry).trimmed.split(separator: " ").map(String.init)
                guard let url = parts.first else { continue }
                let descriptor = parts.count > 1 ? parts[1] : "1x"
                let value = Double(String(descriptor.dropLast())) ?? 1
                scored.append((url, descriptor.hasSuffix("w") ? value / 1000 : value))
            }
            // Prefer ~2x density without going huge.
            return scored.min { a, b in abs(a.density - 2) < abs(b.density - 2) }?.url
        }

        private func walk(_ node: XMLNode) {
            switch node.kind {
            case .text:
                inline += InlineMarkdown.escape(HTMLImporter.stripInvisibles(node.stringValue ?? ""))
            case .element:
                guard let element = node as? XMLElement else { return }
                let name = tagName(element)
                if HTMLImporter.skipTags.contains(name) || isHidden(element) { return }

                switch name {
                case "img":
                    if let markdown = imageMarkdown(element) { inline += markdown }
                case "div" where element.attribute(forName: "data-cheet")?.stringValue == "figure":
                    flushInline()
                    walkFigure(element)
                case "h1", "h2", "h3", "h4", "h5", "h6":
                    flushInline()
                    let level = Int(String(name.dropFirst())) ?? 2
                    events.append(.heading(level: level, text: inlineMarkdown(element)))
                case "table":
                    flushInline()
                    if isLayoutTable(element) {
                        // Tables used for page layout: read the cells as ordinary content.
                        for row in tableRows(element) {
                            for cell in (row.children ?? []).compactMap({ $0 as? XMLElement }) {
                                walkChildren(of: cell)
                                flushInline()
                            }
                        }
                    } else {
                        events.append(contentsOf: parseTable(element))
                    }
                case "ul", "ol", "menu":
                    flushInline()
                    var items: [String] = []
                    collectListItems(element, depth: 0, into: &items)
                    events.append(.block(.list(ListBlock(items: items, ordered: name == "ol"))))
                case "dl":
                    flushInline()
                    let rows = parseDefinitionList(element)
                    if !rows.isEmpty { events.append(.block(.table(CheetTable(headers: nil, rows: rows)))) }
                case "pre":
                    flushInline()
                    events.append(.block(.code(CodeBlock(code: preText(element), language: codeLanguage(element)))))
                case "br":
                    inline += " "
                case "hr":
                    flushInline()
                default:
                    if HTMLImporter.blockTags.contains(name) {
                        flushInline()
                        walkChildren(of: element)
                        flushInline()
                    } else if isInlineOnly(element) {
                        inline += inlineMarkdown(element)
                    } else {
                        walkChildren(of: element)
                    }
                }
            default:
                break
            }
        }

        /// `<figure>`: its image(s) get the figcaption as a caption.
        private func walkFigure(_ figure: XMLElement) {
            let images = ((try? figure.nodes(forXPath: ".//*[local-name()='img']")) ?? []).compactMap { $0 as? XMLElement }.filter { !isHidden($0) }
            let captionNode = ((try? figure.nodes(forXPath: ".//*[@data-cheet='figcaption']")) ?? []).first
            let caption = captionNode.map { InlineMarkdown.collapseWhitespace(inlineMarkdown($0)).trimmed }.flatMap { $0.isEmpty ? nil : $0 }
            let parsed = images.compactMap { imageMarkdown($0).flatMap(InlineMarkdown.soleImage) }
            guard !parsed.isEmpty else {
                walkChildren(of: figure)
                flushInline()
                return
            }
            for (index, image) in parsed.enumerated() {
                let isLast = index == parsed.count - 1
                events.append(.block(.image(ImageBlock(source: image.source, alt: image.alt, caption: isLast ? caption : nil))))
            }
            // Anything else in the figure (e.g. a formula or table) still counts.
            for child in figure.children ?? [] {
                if let el = child as? XMLElement,
                   ["img", "picture", "a"].contains(tagName(el)) || el.attribute(forName: "data-cheet")?.stringValue == "figcaption" { continue }
                walk(child)
            }
            flushInline()
        }

        // MARK: Tables

        private func parseTable(_ table: XMLElement) -> [OutlineEvent] {
            var rows: [(cells: [String], isHeader: Bool)] = []
            for tr in tableRows(table) {
                let cells = (tr.children ?? []).compactMap { $0 as? XMLElement }
                    .filter { ["td", "th"].contains(tagName($0)) }
                guard !cells.isEmpty else { continue }
                let texts = cells.map { cellMarkdown($0) }
                let isHeader = cells.allSatisfy { tagName($0) == "th" } || tagName(tr.parent as? XMLElement) == "thead"
                    || (rows.isEmpty && HTMLImporter.isHeaderRow(cells, texts: texts))
                rows.append((isHeader ? texts.map(HTMLImporter.unbolded) : texts, isHeader))
            }
            guard !rows.isEmpty else { return [] }

            let columns = rows.map(\.cells.count).max() ?? 0
            var events: [OutlineEvent] = []
            var headers: [String]? = nil
            var body: [[String]] = []
            var index = 0
            if rows[0].isHeader && rows.count > 1 {
                headers = rows[0].cells
                index = 1
            }
            if let caption = table.elements(forName: "caption").first ?? table.elements(forLocalName: "caption", uri: HTMLImporter.xhtmlNamespace).first {
                let text = inlineMarkdown(caption)
                if !text.isEmpty { events.append(.block(.heading(text))) }
            }

            func flushTable() {
                if !body.isEmpty { events.append(.block(.table(CheetTable(headers: headers, rows: body)))) }
                body = []
            }

            for row in rows[index...] {
                let nonEmpty = row.cells.filter { !$0.isEmpty }
                if columns >= 2 && row.cells.count == 1 && nonEmpty.count == 1 {
                    // A full-width row inside a table acts as a group heading.
                    flushTable()
                    events.append(.block(.heading(nonEmpty[0])))
                } else if row.isHeader && index > 0 && row.cells == headers {
                    continue // repeated header row
                } else {
                    body.append(row.cells)
                }
            }
            flushTable()
            return events
        }

        /// A table whose cells hold headings or other tables is page layout, not data.
        private func isLayoutTable(_ table: XMLElement) -> Bool {
            let query = ".//*[local-name()='td' or local-name()='th']//*[local-name()='table' or local-name()='h1' or "
                + "local-name()='h2' or local-name()='h3' or local-name()='h4' or local-name()='h5' or local-name()='h6']"
            return ((try? table.nodes(forXPath: query))?.isEmpty == false)
        }

        private func tableRows(_ table: XMLElement) -> [XMLElement] {
            var result: [XMLElement] = []
            for child in (table.children ?? []).compactMap({ $0 as? XMLElement }) {
                switch tagName(child) {
                case "tr": result.append(child)
                case "thead", "tbody", "tfoot":
                    result.append(contentsOf: (child.children ?? []).compactMap { $0 as? XMLElement }.filter { tagName($0) == "tr" })
                default: break
                }
            }
            return result
        }

        private func cellMarkdown(_ cell: XMLElement) -> String {
            // Cells may contain block content (lists, paragraphs) — flatten to a single line.
            let parts = (cell.children ?? []).map { child -> String in
                if let el = child as? XMLElement, ["ul", "ol"].contains(tagName(el)) {
                    var items: [String] = []
                    collectListItems(el, depth: 0, into: &items)
                    return " " + items.map(\.trimmed).joined(separator: "; ") + " "
                }
                if let el = child as? XMLElement, tagName(el) == "pre" {
                    return InlineMarkdown.codeSpan(InlineMarkdown.collapseWhitespace(el.stringValue ?? ""))
                }
                return inlineMarkdown(child)
            }
            return InlineMarkdown.collapseWhitespace(parts.joined()).trimmed
        }

        // MARK: Lists

        private func collectListItems(_ list: XMLElement, depth: Int, into items: inout [String]) {
            for li in (list.children ?? []).compactMap({ $0 as? XMLElement }) where tagName(li) == "li" {
                var textParts: [String] = []
                var nested: [XMLElement] = []
                for child in li.children ?? [] {
                    if let el = child as? XMLElement, ["ul", "ol"].contains(tagName(el)) {
                        nested.append(el)
                    } else if let el = child as? XMLElement, tagName(el) == "pre" {
                        textParts.append(InlineMarkdown.codeSpan(InlineMarkdown.collapseWhitespace(el.stringValue ?? "")))
                    } else {
                        textParts.append(inlineMarkdown(child))
                    }
                }
                let text = InlineMarkdown.collapseWhitespace(textParts.joined(separator: "")).trimmed
                if !text.isEmpty {
                    items.append(String(repeating: "  ", count: min(depth, 4)) + text)
                }
                for sub in nested { collectListItems(sub, depth: depth + 1, into: &items) }
            }
        }

        private func parseDefinitionList(_ dl: XMLElement) -> [[String]] {
            var rows: [[String]] = []
            var pendingTerms: [String] = []
            var definitions: [String] = []

            func flush() {
                if !pendingTerms.isEmpty || !definitions.isEmpty {
                    rows.append([pendingTerms.joined(separator: ", "), definitions.joined(separator: "; ")])
                }
                pendingTerms = []
                definitions = []
            }

            var children = (dl.children ?? []).compactMap { $0 as? XMLElement }
            // <dl><div><dt/><dd/></div></dl> is valid HTML too.
            children = children.flatMap { tagName($0) == "div" ? ($0.children ?? []).compactMap { $0 as? XMLElement } : [$0] }
            for child in children {
                switch tagName(child) {
                case "dt":
                    if !definitions.isEmpty { flush() }
                    pendingTerms.append(InlineMarkdown.collapseWhitespace(inlineMarkdown(child)).trimmed)
                case "dd":
                    definitions.append(cellMarkdown(child))
                default: break
                }
            }
            flush()
            return rows
        }

        // MARK: Code

        private func preText(_ pre: XMLElement) -> String {
            var text = pre.stringValue ?? ""
            while text.hasPrefix("\n") { text.removeFirst() }
            while text.hasSuffix("\n") || text.hasSuffix(" ") { text.removeLast() }
            return text
        }

        private func codeLanguage(_ pre: XMLElement) -> String? {
            let candidates = [pre] + pre.elements(forName: "code") + pre.elements(forLocalName: "code", uri: HTMLImporter.xhtmlNamespace)
            for el in candidates {
                guard let classes = el.attribute(forName: "class")?.stringValue else { continue }
                for cls in classes.split(separator: " ") {
                    for prefix in ["language-", "lang-"] where cls.hasPrefix(prefix) {
                        return String(cls.dropFirst(prefix.count))
                    }
                }
            }
            return nil
        }

        // MARK: Inline

        private func isInlineOnly(_ element: XMLElement) -> Bool {
            let name = tagName(element)
            if HTMLImporter.blockTags.contains(name) || ["table", "ul", "ol", "dl", "pre", "h1", "h2", "h3", "h4", "h5", "h6", "hr"].contains(name) {
                return false
            }
            return (element.children ?? []).allSatisfy { child in
                guard let el = child as? XMLElement else { return true }
                return isInlineOnly(el)
            }
        }

        func inlineMarkdown(_ node: XMLNode) -> String {
            switch node.kind {
            case .text:
                let text = HTMLImporter.stripInvisibles(node.stringValue ?? "")
                return InlineMarkdown.escape(InlineMarkdown.collapseWhitespace(text))
            case .element:
                guard let el = node as? XMLElement else { return "" }
                let name = tagName(el)
                if HTMLImporter.skipTags.contains(name) || isHidden(el) { return "" }
                switch name {
                case "img":
                    return imageMarkdown(el) ?? ""
                case "sup", "sub":
                    let inner = InlineMarkdown.collapseWhitespace((el.children ?? []).map(inlineMarkdown).joined()).trimmed
                    // Citation markers ([1], [note 2]) aren't part of the content.
                    let classes = (el.attribute(forName: "class")?.stringValue ?? "").lowercased()
                    if classes.contains("reference") || classes.contains("footnote") || classes.contains("noprint")
                        || InlineMarkdown.plainText(inner).range(of: #"^\[[^\]]{1,12}\]$"#, options: .regularExpression) != nil {
                        return ""
                    }
                    return name == "sup" ? MathScript.superscript(inner) : MathScript.subscript(inner)
                case "var":
                    return InlineMarkdown.wrap((el.children ?? []).map(inlineMarkdown).joined(), with: "*")
                case "code", "kbd", "samp", "tt":
                    return InlineMarkdown.codeSpan(InlineMarkdown.collapseWhitespace(el.stringValue ?? ""))
                case "br":
                    return preserveLineBreaks ? "\n" : " "
                default:
                    let inner = (el.children ?? []).map(inlineMarkdown).joined()
                    switch name {
                    case "strong", "b":
                        return InlineMarkdown.wrap(inner, with: "**")
                    case "em", "i", "cite", "dfn":
                        return InlineMarkdown.wrap(inner, with: "*")
                    case "a":
                        if let href = el.attribute(forName: "href")?.stringValue,
                           let resolved = HTMLImporter.resolve(href, against: baseURL), !resolved.hasPrefix("data:"),
                           !inner.trimmed.isEmpty {
                            return "[\(inner.trimmed)](\(resolved.replacingOccurrences(of: ")", with: "%29").replacingOccurrences(of: " ", with: "%20")))"
                        }
                        return inner
                    case "p", "div", "li", "dt", "dd", "tr":
                        return preserveLineBreaks ? "\n" + inner + "\n" : " " + inner + " "
                    case "td", "th":
                        return inner + " "
                    default:
                        return inner
                    }
                }
            default:
                return ""
            }
        }

        private func tagName(_ element: XMLElement?) -> String {
            (element?.localName ?? element?.name ?? "").lowercased()
        }
    }
}
