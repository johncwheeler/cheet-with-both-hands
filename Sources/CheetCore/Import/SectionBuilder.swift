import Foundation

/// A flat stream of document structure produced by each importer and turned into sections here.
public enum OutlineEvent: Hashable, Sendable {
    case heading(level: Int, text: String)
    case block(CheetBlock)
}

/// Turns an outline (headings + blocks) into a cheet title and sections:
/// - a leading top-level heading that outranks every other heading becomes the cheet title,
/// - the shallowest remaining heading level becomes sections,
/// - deeper headings become sub-headings inside a section,
/// - "term — description" style lists become two-column tables.
public enum SectionBuilder {
    public static func build(events rawEvents: [OutlineEvent]) -> (title: String?, sections: [CheetSection]) {
        var events = rawEvents.compactMap(clean)
        var title: String?

        // Title: first event is a heading that outranks every other heading.
        if case .heading(let level, let text) = events.first {
            let others = events.dropFirst().compactMap(\.headingLevel)
            if others.allSatisfy({ $0 > level }) {
                title = text
                events.removeFirst()
            }
        }
        // Title: exactly one H1 anywhere, with every other heading deeper.
        if title == nil {
            let levels = events.compactMap(\.headingLevel)
            if levels.filter({ $0 == 1 }).count == 1, levels.filter({ $0 != 1 }).allSatisfy({ $0 > 1 }),
               let index = events.firstIndex(where: { $0.headingLevel == 1 }),
               case .heading(_, let text) = events[index] {
                title = text
                events.remove(at: index)
            }
        }

        let sectionLevel = events.compactMap(\.headingLevel).min()
        var sections: [CheetSection] = []

        func appendBlock(_ block: CheetBlock) {
            if sections.isEmpty { sections.append(CheetSection(title: "", blocks: [])) }
            sections[sections.count - 1].blocks.append(block)
        }

        for event in events {
            switch event {
            case .heading(let level, let text):
                if level == sectionLevel {
                    sections.append(CheetSection(title: text, blocks: []))
                } else {
                    appendBlock(.heading(text))
                }
            case .block(let block):
                appendBlock(block)
            }
        }

        sections = sections.compactMap(trimTrailingHeadings).filter { !$0.blocks.isEmpty }

        // A single section full of sub-headings reads better split into cards.
        if sections.count == 1, sections[0].blocks.filter(\.isHeading).count >= 2 {
            sections = splitAtHeadings(sections[0])
        }

        return (title, sections)
    }

    private static func clean(_ event: OutlineEvent) -> OutlineEvent? {
        switch event {
        case .heading(let level, let text):
            let t = text.trimmed
            return t.isEmpty ? nil : .heading(level: level, text: t)
        case .block(let block):
            switch block {
            case .heading(let text):
                let t = text.trimmed
                return t.isEmpty ? nil : .block(.heading(t))
            case .text(let text):
                let t = text.trimmed
                if let image = InlineMarkdown.soleImage(t) {
                    return .block(.image(ImageBlock(source: image.source, alt: image.alt, caption: image.title)))
                }
                return t.isEmpty ? nil : .block(.text(t))
            case .code(let code):
                return code.code.trimmed.isEmpty ? nil : event
            case .image(let image):
                return image.source.isEmpty ? nil : event
            case .list(let list):
                let items = list.items.filter { !$0.trimmed.isEmpty }
                guard !items.isEmpty else { return nil }
                if let table = keyValueTable(from: ListBlock(items: items, ordered: list.ordered)) {
                    return .block(.table(table))
                }
                return .block(.list(ListBlock(items: items, ordered: list.ordered)))
            case .table(var table):
                table.rows = table.rows.filter { row in row.contains { !$0.trimmed.isEmpty } }
                if let headers = table.headers, headers.allSatisfy({ $0.trimmed.isEmpty }) { table.headers = nil }
                guard !table.rows.isEmpty else { return nil }
                return .block(.table(table))
            }
        }
    }

    private static func trimTrailingHeadings(_ section: CheetSection) -> CheetSection? {
        var s = section
        while let last = s.blocks.last, last.isHeading { s.blocks.removeLast() }
        return s
    }

    private static func splitAtHeadings(_ section: CheetSection) -> [CheetSection] {
        var result: [CheetSection] = []
        var current = CheetSection(title: section.title, blocks: [])
        for block in section.blocks {
            if case .heading(let text) = block {
                if !current.blocks.isEmpty { result.append(current) }
                current = CheetSection(title: text, blocks: [])
            } else {
                current.blocks.append(block)
            }
        }
        if !current.blocks.isEmpty { result.append(current) }
        return result
    }

    // MARK: - List → key/value table

    private static let codeKeyPattern = try! NSRegularExpression(
        pattern: #"^((?:`[^`]+`(?:\s*[+/,]\s*|\s+(?:then|or)\s+|\s*)?)+?)\s*(?:[-–—:=→]|=>|->)?\s+(\S.*)$"#
    )
    private static let boldKeyPattern = try! NSRegularExpression(
        pattern: #"^\*\*(.+?)\*\*\s*(?:[-–—:=→]|=>|->)?\s*(\S.*)$"#
    )
    private static let separatorPattern = try! NSRegularExpression(
        pattern: #"^(.{1,48}?)\s+(?:[-–—→]|=>|->|=)\s+(\S.*)$"#
    )
    private static let colonPattern = try! NSRegularExpression(
        pattern: #"^([^:]{1,40}?):\s+(\S.*)$"#
    )

    /// Converts a list whose items all look like "key — description" into a two-column table.
    static func keyValueTable(from list: ListBlock) -> CheetTable? {
        guard list.items.count >= 2,
              list.items.allSatisfy({ ListBlock.depthAndText($0).depth == 0 }) else { return nil }

        for pattern in [codeKeyPattern, boldKeyPattern, separatorPattern, colonPattern] {
            var rows: [[String]] = []
            for item in list.items {
                let text = item.trimmed
                let range = NSRange(text.startIndex..., in: text)
                guard let m = pattern.firstMatch(in: text, range: range),
                      let keyRange = Range(m.range(at: 1), in: text),
                      let valueRange = Range(m.range(at: 2), in: text) else { rows = []; break }
                var key = String(text[keyRange]).trimmed
                if pattern === boldKeyPattern { key = "**\(key)**" }
                let value = String(text[valueRange]).trimmed
                guard !key.isEmpty, !value.isEmpty else { rows = []; break }
                rows.append([key, value])
            }
            if !rows.isEmpty {
                return CheetTable(headers: nil, rows: rows)
            }
        }
        return nil
    }
}

extension OutlineEvent {
    var headingLevel: Int? {
        if case .heading(let level, _) = self { return level }
        return nil
    }
}

extension CheetBlock {
    public var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }
}
