import Foundation

public enum Delimiter: String, Codable, CaseIterable, Sendable {
    case comma, tab, semicolon, pipe
    /// Columns separated by a tab or two-plus spaces ("Ctrl+C    Copy").
    case whitespace

    public var label: String {
        switch self {
        case .comma: "Comma (CSV)"
        case .tab: "Tab (TSV)"
        case .semicolon: "Semicolon"
        case .pipe: "Pipe |"
        case .whitespace: "Aligned columns (2+ spaces)"
        }
    }

    var character: Character? {
        switch self {
        case .comma: ","
        case .tab: "\t"
        case .semicolon: ";"
        case .pipe: "|"
        case .whitespace: nil
        }
    }
}

public enum HeaderMode: String, Codable, CaseIterable, Sendable {
    case auto, yes, no
    public var label: String {
        switch self {
        case .auto: "Detect"
        case .yes: "First row is header"
        case .no: "No header"
        }
    }
}

/// CSV / TSV / aligned-column text → tables. Single-cell rows become section headings, and a
/// leading "Category"/"Section" column groups rows into sections.
public enum DelimitedImporter {
    public static func events(from text: String, delimiter: Delimiter?, header: HeaderMode) -> [OutlineEvent] {
        guard let delim = delimiter ?? detectDelimiter(text) else { return [] }
        let rawRows = parseRows(text, delimiter: delim)
        let rows = rawRows.map { $0.map(\.trimmed) }
        let contentRows = rows.filter { $0.contains { !$0.isEmpty } }
        guard !contentRows.isEmpty else { return [] }

        // Column count = most common width among multi-cell rows.
        let widths = contentRows.map { row in row.lastIndex { !$0.isEmpty }.map { $0 + 1 } ?? 0 }.filter { $0 > 1 }
        let columns = mode(of: widths) ?? max(1, widths.max() ?? 1)

        let hasHeader: Bool
        switch header {
        case .yes: hasHeader = true
        case .no: hasHeader = false
        case .auto: hasHeader = looksLikeHeader(contentRows, columns: columns)
        }

        var headers: [String]? = nil
        var bodyRows = contentRows
        if hasHeader {
            headers = fit(contentRows[0], to: columns, delimiter: delim)
            bodyRows = Array(contentRows.dropFirst())
        }

        // Grouping column: "Category, Shortcut, Description".
        if let h = headers, columns >= 3, groupingHeaderNames.contains(h[0].searchFolded) {
            var events: [OutlineEvent] = []
            var currentGroup: String? = nil
            var groupRows: [[String]] = []
            let subHeaders = Array(h.dropFirst())
            func flushGroup() {
                guard !groupRows.isEmpty else { return }
                events.append(.heading(level: 2, text: currentGroup?.isEmpty == false ? currentGroup! : "General"))
                events.append(.block(.table(CheetTable(headers: subHeaders, rows: groupRows))))
                groupRows = []
            }
            for row in bodyRows {
                let cells = fit(row, to: columns, delimiter: delim)
                let group = cells[0]
                if group != currentGroup && !(group.isEmpty && currentGroup != nil) {
                    flushGroup()
                    currentGroup = group
                }
                groupRows.append(Array(cells.dropFirst()))
            }
            flushGroup()
            return events
        }

        var events: [OutlineEvent] = []
        var tableRows: [[String]] = []
        func flushTable() {
            guard !tableRows.isEmpty else { return }
            events.append(.block(.table(CheetTable(headers: headers, rows: tableRows))))
            tableRows = []
        }
        for row in bodyRows {
            let nonEmpty = row.filter { !$0.isEmpty }
            if columns >= 2, nonEmpty.count == 1, !row[0].isEmpty {
                flushTable()
                events.append(.heading(level: 2, text: stripSectionDecoration(row[0])))
            } else {
                tableRows.append(fit(row, to: columns, delimiter: delim))
            }
        }
        flushTable()
        return events
    }

    // MARK: - Detection

    public static func detectDelimiter(_ text: String) -> Delimiter? {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmed.isEmpty }.prefix(60)
        guard !lines.isEmpty else { return nil }

        var best: (Delimiter, Double)? = nil
        for candidate in [Delimiter.tab, .pipe, .semicolon, .comma] {
            guard let ch = candidate.character else { continue }
            let counts = lines.map { countOutsideQuotes(ch, in: $0) }
            guard let common = mode(of: counts.filter { $0 > 0 }), common > 0 else { continue }
            let consistency = Double(counts.filter { $0 == common }.count) / Double(lines.count)
            let coverage = Double(counts.filter { $0 > 0 }.count) / Double(lines.count)
            let score = consistency * 0.7 + coverage * 0.3
            if score >= 0.6, score > (best?.1 ?? 0) + 0.001 { best = (candidate, score) }
        }
        if let best { return best.0 }

        let splitCount = lines.filter { splitWhitespaceColumns($0).count >= 2 }.count
        if Double(splitCount) / Double(lines.count) >= 0.6 { return .whitespace }
        return nil
    }

    /// Confidence (0…1) that text is delimited tabular data.
    static func tabularConfidence(_ text: String) -> Double {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmed.isEmpty }
        guard lines.count >= 2, let delim = detectDelimiter(text) else { return 0 }
        let rows = parseRows(text, delimiter: delim).filter { $0.count > 1 }
        return Double(rows.count) / Double(lines.count)
    }

    // MARK: - Parsing

    public static func parseRows(_ text: String, delimiter: Delimiter) -> [[String]] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        switch delimiter {
        case .whitespace:
            return normalized.components(separatedBy: "\n").map { line in
                line.trimmed.isEmpty ? [] : splitWhitespaceColumns(line)
            }
        case .pipe:
            return normalized.components(separatedBy: "\n").compactMap { line in
                let t = line.trimmed
                if t.isEmpty { return [] }
                if MarkdownImporter.isTableDelimiter(t) { return nil }
                return MarkdownImporter.splitTableRow(t)
            }
        default:
            return parseQuoted(normalized, separator: delimiter.character!)
        }
    }

    /// RFC 4180-style parsing: quoted fields, doubled quotes, newlines inside quotes.
    static func parseQuoted(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var atFieldStart = true
        var iterator = Array(text).makeIterator()
        var pending: Character? = nil

        func nextChar() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let ch = nextChar() {
            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
                continue
            }
            switch ch {
            case "\"" where atFieldStart || field.trimmed.isEmpty:
                inQuotes = true
                field = ""
                atFieldStart = false
            case separator:
                row.append(field)
                field = ""
                atFieldStart = true
            case "\n":
                row.append(field)
                rows.append(row.count == 1 && row[0].trimmed.isEmpty ? [] : row)
                row = []
                field = ""
                atFieldStart = true
            default:
                field.append(ch)
                atFieldStart = false
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    static func splitWhitespaceColumns(_ line: String) -> [String] {
        line.trimmed
            .replacingOccurrences(of: #"\t+| {2,}"#, with: "\u{1F}", options: .regularExpression)
            .components(separatedBy: "\u{1F}")
            .map(\.trimmed)
            .filter { !$0.isEmpty }
    }

    // MARK: - Helpers

    static let groupingHeaderNames: Set<String> = ["category", "section", "group", "context", "mode", "area", "scope", "type", "topic"]

    private static let headerWords: Set<String> = [
        "key", "keys", "shortcut", "shortcuts", "keystroke", "binding", "combo", "command", "commands",
        "action", "description", "desc", "name", "function", "what", "does", "effect", "usage", "example",
        "syntax", "result", "meaning", "notes", "note", "category", "section", "group", "context", "mode",
        "windows", "mac", "macos", "linux", "operation", "task", "value", "option", "flag", "term", "definition",
    ]

    static func looksLikeHeader(_ rows: [[String]], columns: Int) -> Bool {
        guard rows.count >= 2, let first = rows.first else { return false }
        let cells = first.prefix(columns).map(\.trimmed)
        guard cells.count >= 2, cells.allSatisfy({ !$0.isEmpty && $0.count <= 40 }) else { return false }

        let words = cells.flatMap { $0.searchFolded.split(whereSeparator: { !$0.isLetter }).map(String.init) }
        if words.contains(where: headerWords.contains) { return true }

        // Every header cell is a plain capitalised word/phrase and the data rows look different.
        let plainTitleCase = cells.allSatisfy { cell in
            cell.allSatisfy { $0.isLetter || $0 == " " } && cell.first?.isUppercase == true
        }
        guard plainTitleCase else { return false }
        let secondRowHasSymbols = rows[1].contains { cell in cell.contains { !$0.isLetter && $0 != " " } }
        return secondRowHasSymbols
    }

    /// Pads short rows and merges overflow cells (unquoted delimiters in the last column) back together.
    static func fit(_ row: [String], to columns: Int, delimiter: Delimiter) -> [String] {
        if row.count == columns { return row }
        if row.count < columns { return row + Array(repeating: "", count: columns - row.count) }
        let joiner = delimiter == .whitespace ? "  " : String(delimiter.character ?? ",") + (delimiter == .tab ? "" : " ")
        let head = row.prefix(columns - 1)
        let tail = row.dropFirst(columns - 1).filter { !$0.isEmpty }.joined(separator: joiner)
        return Array(head) + [tail]
    }

    private static func stripSectionDecoration(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "#=-*[]: ").union(.whitespaces))
    }

    private static func countOutsideQuotes(_ ch: Character, in line: String) -> Int {
        var count = 0
        var inQuotes = false
        for c in line {
            if c == "\"" { inQuotes.toggle() } else if c == ch && !inQuotes { count += 1 }
        }
        return count
    }

    static func mode(of values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        return counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
    }
}
