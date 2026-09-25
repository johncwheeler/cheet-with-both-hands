import Foundation

/// A pragmatic, line-based Markdown reader covering what cheets actually use:
/// ATX/Setext headings, GFM pipe tables, (nested) lists, fenced code, quotes and paragraphs.
public enum MarkdownImporter {
    public static func events(from text: String) -> [OutlineEvent] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var events: [OutlineEvent] = []
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            events.append(.block(.text(paragraph.joined(separator: " "))))
            paragraph = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmed

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // Fenced code block.
            if let fence = fenceMarker(trimmed) {
                flushParagraph()
                let language = String(trimmed.dropFirst(fence.count)).trimmed
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmed.hasPrefix(fence) {
                    code.append(lines[i])
                    i += 1
                }
                i += 1 // closing fence
                events.append(.block(.code(CodeBlock(
                    code: dedent(code).joined(separator: "\n"),
                    language: language.isEmpty ? nil : language
                ))))
                continue
            }

            // ATX heading.
            if let heading = atxHeading(trimmed) {
                flushParagraph()
                events.append(.heading(level: heading.level, text: heading.text))
                i += 1
                continue
            }

            // Setext heading (text followed by === or ---).
            if paragraph.isEmpty, i + 1 < lines.count, listItem(line) == nil, !trimmed.contains("|"),
               let level = setextLevel(lines[i + 1]) {
                events.append(.heading(level: level, text: trimmed))
                i += 2
                continue
            }

            if isHorizontalRule(trimmed) {
                flushParagraph()
                i += 1
                continue
            }

            // Pipe table: a row followed by a delimiter row.
            if trimmed.contains("|"), i + 1 < lines.count, isTableDelimiter(lines[i + 1]) {
                flushParagraph()
                let headers = splitTableRow(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let rowLine = lines[i].trimmed
                    guard !rowLine.isEmpty, rowLine.contains("|") else { break }
                    rows.append(splitTableRow(rowLine))
                    i += 1
                }
                events.append(.block(.table(CheetTable(headers: headers, rows: rows))))
                continue
            }

            // List.
            if let first = listItem(line) {
                flushParagraph()
                var items: [String] = []
                let baseIndent = first.indent
                var previousBlank = false
                while i < lines.count {
                    let current = lines[i]
                    let currentTrimmed = current.trimmed
                    if currentTrimmed.isEmpty {
                        // A blank line ends the list unless another item (or indented continuation) follows.
                        var j = i + 1
                        while j < lines.count, lines[j].trimmed.isEmpty { j += 1 }
                        if j < lines.count, listItem(lines[j]) != nil || leadingSpaces(lines[j]) > baseIndent + 1 {
                            previousBlank = true
                            i += 1
                            continue
                        }
                        break
                    }
                    if let item = listItem(current) {
                        let depth = max(0, min(4, (item.indent - baseIndent + 1) / 2))
                        items.append(String(repeating: "  ", count: depth) + item.text)
                    } else if !items.isEmpty,
                              leadingSpaces(current) > baseIndent || (!previousBlank && isLazyContinuation(currentTrimmed)) {
                        items[items.count - 1] += " " + currentTrimmed
                    } else {
                        break
                    }
                    previousBlank = false
                    i += 1
                }
                events.append(.block(.list(ListBlock(items: items, ordered: first.ordered))))
                continue
            }

            // Block quote → plain text.
            if trimmed.hasPrefix(">") {
                paragraph.append(String(trimmed.drop { $0 == ">" || $0 == " " }))
                i += 1
                continue
            }

            // Stand-alone HTML tag lines (e.g. <br>, <div>) carry no content.
            if isBareHTMLTagLine(trimmed) {
                i += 1
                continue
            }

            paragraph.append(trimmed)
            i += 1
        }
        flushParagraph()
        return events
    }

    // MARK: - Line classification

    static func fenceMarker(_ trimmed: String) -> String? {
        for marker in ["```", "~~~"] where trimmed.hasPrefix(marker) {
            let run = trimmed.prefix { $0 == marker.first }
            return String(run)
        }
        return nil
    }

    static func atxHeading(_ trimmed: String) -> (level: Int, text: String)? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = String(rest).trimmed
        // Strip optional closing hashes: "## Title ##"
        while text.hasSuffix("#") { text.removeLast() }
        return (hashes, text.trimmed)
    }

    static func setextLevel(_ line: String) -> Int? {
        let t = line.trimmed
        guard t.count >= 2 else { return nil }
        if t.allSatisfy({ $0 == "=" }) { return 1 }
        if t.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    static func isHorizontalRule(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { $0 != " " }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    static func isTableDelimiter(_ line: String) -> Bool {
        let t = line.trimmed
        guard t.contains("-"), t.contains("|") else { return false }
        let cells = splitTableRow(t)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let c = cell.trimmed
            guard !c.isEmpty else { return false }
            let core = c.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !core.isEmpty && core.allSatisfy { $0 == "-" }
        }
    }

    /// Splits a pipe-table row, honouring `\|` escapes and pipes inside code spans.
    static func splitTableRow(_ line: String) -> [String] {
        var t = line.trimmed
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }

        var cells: [String] = []
        var current = ""
        var inCode = false
        let chars = Array(t)
        var idx = 0
        while idx < chars.count {
            let ch = chars[idx]
            if ch == "\\", idx + 1 < chars.count, chars[idx + 1] == "|" {
                current.append("|")
                idx += 2
                continue
            }
            if ch == "`" {
                // Only treat a backtick as opening a code span when a closing one follows.
                if inCode || chars[(idx + 1)...].contains("`") { inCode.toggle() }
            }
            if ch == "|" && !inCode {
                cells.append(current.trimmed)
                current = ""
            } else {
                current.append(ch)
            }
            idx += 1
        }
        cells.append(current.trimmed)
        return cells
    }

    struct ListItem {
        var indent: Int
        var ordered: Bool
        var text: String
    }

    static func listItem(_ line: String) -> ListItem? {
        let indent = leadingSpaces(line)
        let t = line.trimmed
        guard let first = t.first else { return nil }
        var text: Substring
        var ordered = false
        if "-*+•".contains(first) {
            let rest = t.dropFirst()
            guard rest.first == " " || rest.first == "\t" else { return nil }
            if isHorizontalRule(t) { return nil }
            text = rest
        } else if first.isNumber {
            let digits = t.prefix { $0.isNumber }
            guard digits.count <= 3 else { return nil }
            let rest = t.dropFirst(digits.count)
            guard let marker = rest.first, marker == "." || marker == ")" else { return nil }
            let afterMarker = rest.dropFirst()
            guard afterMarker.first == " " || afterMarker.first == "\t" else { return nil }
            text = afterMarker
            ordered = true
        } else {
            return nil
        }
        var itemText = String(text).trimmed
        // Task list checkboxes.
        for box in ["[ ] ", "[x] ", "[X] "] where itemText.hasPrefix(box) {
            itemText = String(itemText.dropFirst(box.count))
        }
        return ListItem(indent: indent, ordered: ordered, text: itemText)
    }

    static func leadingSpaces(_ line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 } else if ch == "\t" { count += 4 } else { break }
        }
        return count
    }

    private static func isLazyContinuation(_ trimmed: String) -> Bool {
        !(trimmed.hasPrefix("#") || trimmed.hasPrefix("|") || trimmed.hasPrefix(">")
            || fenceMarker(trimmed) != nil || isHorizontalRule(trimmed))
    }

    private static func isBareHTMLTagLine(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">") else { return false }
        let inner = trimmed.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        return inner.trimmed.isEmpty
    }

    private static func dedent(_ lines: [String]) -> [String] {
        let indents = lines.filter { !$0.trimmed.isEmpty }.map { $0.prefix { $0 == " " }.count }
        guard let common = indents.min(), common > 0 else { return lines }
        return lines.map { $0.count >= common ? String($0.dropFirst(common)) : $0.trimmed }
    }
}
