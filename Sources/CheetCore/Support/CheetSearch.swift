import Foundation

/// Pre-folds a cheet's text once so filtering while typing stays cheap.
public final class CheetSearchIndex: @unchecked Sendable {
    public let cheet: Cheet
    private var foldedCache: [String: String] = [:]

    public init(cheet: Cheet) {
        self.cheet = cheet
    }

    private func folded(_ markdown: String) -> String {
        if let cached = foldedCache[markdown] { return cached }
        let value = InlineMarkdown.plainText(markdown).searchFolded
        foldedCache[markdown] = value
        return value
    }

    public static func tokens(for query: String) -> [String] {
        query.searchFolded.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Sections filtered to entries matching every token of the query.
    /// A section (or sub-heading group) whose title matches is kept whole.
    public func filter(_ query: String) -> [CheetSection] {
        let tokens = Self.tokens(for: query)
        guard !tokens.isEmpty else { return cheet.sections }

        func matches(_ haystacks: [String]) -> Bool {
            let joined = haystacks.joined(separator: " ")
            return tokens.allSatisfy { joined.contains($0) }
        }

        return cheet.sections.compactMap { section in
            let sectionTitle = folded(section.title)
            if matches([sectionTitle]) { return section }

            var kept: [CheetBlock] = []
            var groupHeading: String? = nil
            var groupHeadingKept = false
            var groupMatchesWhole = false

            for block in section.blocks {
                if case .heading(let text) = block {
                    groupHeading = text
                    groupHeadingKept = false
                    groupMatchesWhole = matches([sectionTitle, folded(text)])
                    if groupMatchesWhole {
                        kept.append(block)
                        groupHeadingKept = true
                    }
                    continue
                }
                let context = [sectionTitle, groupHeading.map(folded) ?? ""]
                var filtered: CheetBlock? = nil
                if groupMatchesWhole {
                    filtered = block
                } else {
                    switch block {
                    case .table(let table):
                        let rows = table.rows.filter { row in matches(context + row.map(folded)) }
                        if !rows.isEmpty { filtered = .table(CheetTable(headers: table.headers, rows: rows)) }
                    case .list(let list):
                        let items = list.items.filter { matches(context + [folded($0)]) }
                        if !items.isEmpty { filtered = .list(ListBlock(items: items, ordered: list.ordered)) }
                    case .text(let text):
                        if matches(context + [folded(text)]) { filtered = block }
                    case .code(let code):
                        if matches(context + [code.code.searchFolded]) { filtered = block }
                    case .image(let image):
                        if matches(context + [image.alt.searchFolded, folded(image.caption ?? "")]) { filtered = block }
                    case .heading:
                        break
                    }
                }
                if let filtered {
                    if let heading = groupHeading, !groupHeadingKept {
                        kept.append(.heading(heading))
                        groupHeadingKept = true
                    }
                    kept.append(filtered)
                }
            }
            guard !kept.isEmpty else { return nil }
            var result = section
            result.blocks = kept
            result.layout.height = nil // let filtered results fit
            return result
        }
    }
}
