import Foundation

// Cheatography (cheatography.com) support: extracting a cheat sheet page's blocks precisely,
// and reading the catalog's listing pages (search, categories, tags, explore feeds).

/// Reads a Cheatography cheat-sheet page into a `WebDocument`, block by block:
/// key/value tables (including side-by-side "pair" rows), one-column lists, free text, code, and notes.
public enum CheatographyExtractor {
    public static func canHandle(html: String) -> Bool {
        html.contains("cheat_sheet_output_block") && html.contains("cheat_sheet_output_title")
    }

    public static func extract(html: String, url: URL?) -> WebDocument {
        let meta = HTMLMetadata(html: html)
        var region = html
        if let start = html.range(of: "<article", options: .caseInsensitive),
           let end = html.range(of: "</article>", options: [.caseInsensitive, .backwards]),
           start.lowerBound < end.upperBound {
            region = String(html[start.lowerBound..<end.upperBound])
        }
        var math = MathPrepass()
        let cleaned = HTMLImporter.preClean(math.process(region))
        let base = HTMLImporter.documentBase(html) ?? url ?? CheatographyCatalog.baseURL
        guard let document = try? XMLDocument(xmlString: "<html><body>\(cleaned)</body></html>", options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let root = document.rootElement(),
              let nodes = try? root.nodes(forXPath: "//*[contains(@class,'cheat_sheet_output_title') or contains(@class,'cheat_sheet_output_block')]")
        else {
            return WebExtractor.genericHTML(html, url: url, mainContentOnly: true)
        }

        var events: [OutlineEvent] = []
        for node in nodes {
            guard let element = node as? XMLElement else { continue }
            let classes = element.attribute(forName: "class")?.stringValue ?? ""
            if classes.contains("cheat_sheet_output_title") {
                events.append(.heading(level: 2, text: HTMLImporter.inlineText(of: element, baseURL: base)))
            } else if classes.contains("cheat_sheet_output_block") {
                events.append(contentsOf: Reader(base: base).blockEvents(element))
            }
        }

        let built = SectionBuilder.build(events: math.resolve(events))
        return WebDocument(
            title: WebDocument.cleanTitle(meta.title),
            summary: meta.description,
            author: author(in: html),
            siteName: "Cheatography",
            sourceURL: meta.canonicalURL ?? url,
            sections: built.sections,
            extractorName: "Cheatography"
        )
    }

    static func author(in html: String) -> String? {
        guard let range = html.range(of: #"itemprop="author"[\s\S]{0,400}?itemprop="name">([^<]+)<"#, options: .regularExpression) else { return nil }
        let snippet = String(html[range])
        guard let name = snippet.range(of: #"itemprop="name">[^<]+"#, options: .regularExpression) else { return nil }
        return HTMLImporter.decodeEntities(String(snippet[name].dropFirst(#"itemprop="name">"#.count))).trimmed
    }

    /// Reads blocks, resolving images and links against the page.
    struct Reader {
        let base: URL?

        func inline(_ node: XMLNode) -> String { HTMLImporter.inlineText(of: node, baseURL: base) }
        func rich(_ node: XMLNode) -> String { HTMLImporter.richText(of: node, baseURL: base) }

    func blockEvents(_ block: XMLElement) -> [OutlineEvent] {
        var events: [OutlineEvent] = []
        for child in (block.children ?? []).compactMap({ $0 as? XMLElement }) {
            let name = CheatographyExtractor.localName(child)
            let classes = child.attribute(forName: "class")?.stringValue ?? ""
            if name == "table" {
                events.append(contentsOf: tableEvents(child, kind: classes))
            } else if classes.contains("cheat_sheet_note") {
                let text = rich(child)
                if !text.isEmpty { events.append(.block(.text(text))) }
            } else if let pre = CheatographyExtractor.descendants(child, named: "pre").first {
                events.append(.block(.code(CodeBlock(code: CheatographyExtractor.codeText(pre)))))
            }
        }
        return events
    }

    func tableEvents(_ table: XMLElement, kind: String) -> [OutlineEvent] {
        let rows = CheatographyExtractor.tableRows(table)
        if kind.contains("cheat_sheet_output_image") {
            return CheatographyExtractor.descendants(table, named: "img").compactMap { image -> OutlineEvent? in
                let walker = HTMLImporter.Walker()
                walker.baseURL = base
                guard let parts = walker.imageMarkdown(image).flatMap(InlineMarkdown.soleImage) else { return nil }
                return .block(.image(ImageBlock(source: parts.source, alt: parts.alt)))
            }
        }
        if kind.contains("cheat_sheet_output_code") {
            return rows.compactMap { row in
                guard let pre = CheatographyExtractor.descendants(row, named: "pre").first else {
                    let text = rich(row)
                    return text.isEmpty ? nil : .block(.code(CodeBlock(code: text)))
                }
                let code = CheatographyExtractor.codeText(pre)
                return code.isEmpty ? nil : .block(.code(CodeBlock(code: code)))
            }
        }
        if kind.contains("cheat_sheet_output_text") {
            return rows.flatMap { CheatographyExtractor.cells($0) }.compactMap { cell in
                let text = rich(cell)
                return text.isEmpty ? nil : .block(.text(text))
            }
        }
        if kind.contains("cheat_sheet_output_onecol") {
            let items = rows.compactMap { CheatographyExtractor.cells($0).first.map { inline($0) } }.filter { !$0.isEmpty }
            return items.isEmpty ? [] : [.block(.list(ListBlock(items: items)))]
        }

        // Key/value tables. In Cheatography's two- and four-column blocks, four-cell rows are two
        // key/value pairs side by side (unless there's a real four-column header); single spanning
        // cells are keys without a value. Other tables keep their columns, colspans expanded.
        let pairs = kind.contains("cheat_sheet_output_twocol") || kind.contains("cheat_sheet_output_fourcol")
        var events: [OutlineEvent] = []
        var headers: [String]?
        var body: [[String]] = []
        func flush() {
            guard !body.isEmpty else { return }
            if headers == nil, body.allSatisfy({ $0.dropFirst().allSatisfy(\.isEmpty) }) {
                events.append(.block(.list(ListBlock(items: body.map { $0[0] }))))
            } else {
                events.append(.block(.table(CheetTable(headers: headers, rows: body.map { $0.count == 1 ? [$0[0], ""] : $0 }))))
            }
            body = []
        }
        for row in rows {
            let rowCells = CheatographyExtractor.cells(row)
            var texts: [String] = []
            for cell in rowCells {
                texts.append(inline(cell))
                if !pairs, let span = cell.attribute(forName: "colspan")?.stringValue.flatMap({ Int($0) }), span > 1 {
                    texts.append(contentsOf: Array(repeating: "", count: min(span, 8) - 1))
                }
            }
            if texts.allSatisfy(\.isEmpty) { continue }
            if body.isEmpty, headers == nil, HTMLImporter.isHeaderRow(rowCells, texts: texts) {
                headers = texts.map(HTMLImporter.unbolded)
                continue
            }
            switch texts.count {
            case 1:
                body.append([texts[0]])
            case 4 where pairs && (headers?.count ?? 0) != 4:
                body.append([texts[0], texts[1]])
                if !(texts[2].isEmpty && texts[3].isEmpty) { body.append([texts[2], texts[3]]) }
            default:
                body.append(texts)
            }
        }
        flush()
        return events
    }
    }

    // MARK: DOM helpers

    fileprivate static func localName(_ element: XMLElement) -> String {
        (element.localName ?? element.name ?? "").lowercased()
    }

    fileprivate static func tableRows(_ table: XMLElement) -> [XMLElement] {
        (table.children ?? []).compactMap { $0 as? XMLElement }.flatMap { child -> [XMLElement] in
            switch localName(child) {
            case "tr": return [child]
            case "thead", "tbody", "tfoot": return (child.children ?? []).compactMap { $0 as? XMLElement }.filter { localName($0) == "tr" }
            default: return []
            }
        }
    }

    fileprivate static func cells(_ row: XMLElement) -> [XMLElement] {
        (row.children ?? []).compactMap { $0 as? XMLElement }.filter { ["td", "th"].contains(localName($0)) }
    }

    fileprivate static func descendants(_ element: XMLElement, named name: String) -> [XMLElement] {
        ((try? element.nodes(forXPath: ".//*[local-name()='\(name)']")) ?? []).compactMap { $0 as? XMLElement }
    }

    fileprivate static func codeText(_ pre: XMLElement) -> String {
        var text = (pre.stringValue ?? "").replacingOccurrences(of: "\u{00AD}", with: "").replacingOccurrences(of: "\u{00A0}", with: " ")
        while text.hasPrefix("\n") { text.removeFirst() }
        while text.hasSuffix("\n") || text.hasSuffix(" ") { text.removeLast() }
        return text
    }
}

// MARK: - Catalog

public struct CatalogItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var url: URL
    public var title: String
    /// "Cheat Sheet", "Keyboard Shortcuts", …
    public var kind: String
    public var summary: String
    public var author: String
    public var thumbnailURL: URL?
    public var rating: Double?
    public var ratingCount: Int
    public var pageCount: Int?
    public var tags: [CatalogTag]
    public var updated: String?

    /// The title without Cheatography's "Cheat Sheet" suffix.
    public var displayTitle: String { WebDocument.cleanTitle(title) ?? title }
}

public struct CatalogTag: Hashable, Sendable {
    public var slug: String
    public var name: String
    public var count: Int?
}

public struct CatalogPage: Sendable {
    public var heading: String?
    public var items: [CatalogItem]
    public var nextPageURL: URL?
    /// Tag groups shown on category pages ("Top Tags in Programming", "Languages", …).
    public var tagGroups: [(title: String, tags: [CatalogTag])]
}

public enum CheatographyCatalog {
    public static let baseURL = URL(string: "https://cheatography.com/")!

    public enum Category: String, CaseIterable, Sendable {
        case programming, software, business, education, home, games

        public var label: String {
            switch self {
            case .programming: "Programming"
            case .software: "Software"
            case .business: "Business & Marketing"
            case .education: "Education"
            case .home: "Home & Health"
            case .games: "Games & Hobbies"
            }
        }

        public var symbol: String {
            switch self {
            case .programming: "chevron.left.forwardslash.chevron.right"
            case .software: "macwindow"
            case .business: "briefcase"
            case .education: "graduationcap"
            case .home: "house"
            case .games: "gamecontroller"
            }
        }
    }

    public enum Feed: String, CaseIterable, Sendable {
        case new, popular, top, downloaded

        public var label: String {
            switch self {
            case .new: "Newest"
            case .popular: "Popular"
            case .top: "Top Rated"
            case .downloaded: "Most Downloaded"
            }
        }

        public var symbol: String {
            switch self {
            case .new: "sparkles"
            case .popular: "flame"
            case .top: "star"
            case .downloaded: "arrow.down.circle"
            }
        }
    }

    public enum Source: Hashable, Sendable {
        case search(String)
        case category(Category)
        case feed(Feed)
        case tag(slug: String, name: String)

        public var url: URL {
            switch self {
            case .search(let query):
                var components = URLComponents(url: baseURL.appendingPathComponent("explore/search/"), resolvingAgainstBaseURL: false)!
                components.queryItems = [URLQueryItem(name: "q", value: query)]
                return components.url!
            case .category(let category):
                return baseURL.appendingPathComponent("\(category.rawValue)/")
            case .feed(let feed):
                return baseURL.appendingPathComponent("explore/\(feed.rawValue)/")
            case .tag(let slug, _):
                return baseURL.appendingPathComponent("tag/\(slug)/cheat-sheets/")
            }
        }

        public var title: String {
            switch self {
            case .search(let query): "“\(query)”"
            case .category(let category): category.label
            case .feed(let feed): feed.label
            case .tag(_, let name): "#\(name)"
            }
        }
    }

    /// Whether a URL points at a single Cheatography cheat sheet.
    public static func isCheatSheetURL(_ url: URL) -> Bool {
        (url.host ?? "").hasSuffix("cheatography.com") && url.path.contains("/cheat-sheets/")
    }

    // MARK: Listing parser

    private static func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    private static func allMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { i in Range(match.range(at: i), in: text).map { String(text[$0]) } ?? "" }
        }
    }

    private static func plain(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return InlineMarkdown.collapseWhitespace(HTMLImporter.decodeEntities(stripped)).trimmed
    }

    private static func absolute(_ href: String, relativeTo base: URL = baseURL) -> URL? {
        let decoded = HTMLImporter.decodeEntities(href)
        let fixed = decoded.hasPrefix("//") ? "https:" + decoded : decoded
        return URL(string: fixed, relativeTo: base)?.absoluteURL
    }

    /// Parses a listing page (search results, category, tag or explore feed).
    public static func parseListing(_ html: String) -> CatalogPage {
        // The sidebar's "Latest" / "Random" cheat sheets use the same markup — cut them off.
        var main = html
        for marker in ["<div class=\"biptychl\">", "<h2>Latest Cheat Sheet</h2>"] {
            if let range = main.range(of: marker) { main = String(main[..<range.lowerBound]) }
        }

        var items: [CatalogItem] = []
        var positions: [(String.Index, String)] = []
        if let regex = try? NSRegularExpression(pattern: #"<div[^>]*id="cheat_sheet_(\d+)"[^>]*>"#) {
            for match in regex.matches(in: main, range: NSRange(main.startIndex..., in: main)) {
                if let r = Range(match.range, in: main), let idRange = Range(match.range(at: 1), in: main) {
                    positions.append((r.lowerBound, String(main[idRange])))
                }
            }
        }
        for (index, (start, id)) in positions.enumerated() {
            let end = index + 1 < positions.count ? positions[index + 1].0 : main.endIndex
            let chunk = String(main[start..<end])
            guard let href = firstMatch(#"href="(/[^"/]+/cheat-sheets/[^"/]+/)"\s+itemprop="url""#, in: chunk)
                    ?? firstMatch(#"href="(/[^"/]+/cheat-sheets/[^"/]+/)""#, in: chunk),
                  let url = absolute(href) else { continue }
            let nameHTML = firstMatch(#"<span itemprop="name">(.*?)<span style="font-weight: normal"#, in: chunk)
                ?? firstMatch(#"<span itemprop="name">(.*?)</span>"#, in: chunk) ?? ""
            let kind = firstMatch(#"<span style="font-weight: normal[^"]*">([^<]+)</span>\s*</span>"#, in: chunk).map(plain) ?? "Cheat Sheet"
            let summary = firstMatch(#"<div style="padding: 5px 0 15px;">(.*?)</div>"#, in: chunk).map(plain) ?? ""
            let author = firstMatch(#"class="user_hover">([^<]+)</a>"#, in: chunk).map(plain) ?? ""
            let thumb = firstMatch(#"data-original="([^"]+)""#, in: chunk).flatMap { absolute($0) }
            let rating = firstMatch(#"<!--\s*Average:\s*([\d.]+)\s*-->"#, in: chunk).flatMap(Double.init)
            let ratingCount = firstMatch(#"&nbsp;\s*\((\d+)\)"#, in: chunk).flatMap { Int($0) } ?? 0
            let pages = firstMatch(#"(\d+)\s+Pages?</span>"#, in: chunk).flatMap { Int($0) }
            let updated = firstMatch(#"fa-calendar[^"]*"[^>]*></i>([^<]+)</div>"#, in: chunk).map(plain)
            let tags = allMatches(#"href="/tag/([^/"]+)/cheat-sheets/"[^>]*>([^<]+)</a>"#, in: chunk).map {
                CatalogTag(slug: $0[1], name: plain($0[2]), count: nil)
            }
            items.append(CatalogItem(
                id: id, url: url, title: plain(nameHTML), kind: kind, summary: summary, author: author,
                thumbnailURL: thumb, rating: rating, ratingCount: ratingCount, pageCount: pages, tags: tags, updated: updated
            ))
        }

        var next: URL?
        if let href = firstMatch(#"<a class="next" href="([^"]+)""#, in: html) {
            next = absolute(href)
        } else {
            // Search results paginate with ?page=N links.
            let pages = allMatches(#"href="([^"]*[?&](?:amp;)?page=(\d+)[^"]*)""#, in: html)
            let currentPage = firstMatch(#"<li class="active">\s*<a[^>]*>(\d+)</a>"#, in: html).flatMap { Int($0) } ?? 1
            if let candidate = pages.first(where: { Int($0[2]) == currentPage + 1 }) {
                next = absolute(candidate[1])
            }
        }

        let heading = firstMatch(#"<h2[^>]*>(.*?)</h2>"#, in: main).map(plain)
        return CatalogPage(heading: heading, items: items, nextPageURL: next, tagGroups: tagGroups(in: html))
    }

    /// Tag groups: `<h2>Group</h2><ul><li><a href="/tag/slug/">Name</a> (12)</li>…</ul>`.
    static func tagGroups(in html: String) -> [(title: String, tags: [CatalogTag])] {
        var groups: [(title: String, tags: [CatalogTag])] = []
        for match in allMatches(#"<h2[^>]*>([^<]+)</h2>\s*<ul>(.*?)</ul>"#, in: html) {
            let tags = allMatches(#"<a href="/tag/([^/"]+)/(?:cheat-sheets/)?">([^<]+)</a>\s*(?:\((\d+)\))?"#, in: match[2]).map {
                CatalogTag(slug: $0[1], name: plain($0[2]), count: Int($0[3]))
            }
            if !tags.isEmpty { groups.append((plain(match[1]), tags)) }
        }
        return groups
    }

    /// The popular tags listed on the explore page.
    public static func popularTags(_ html: String) -> [CatalogTag] {
        guard let range = html.range(of: "Most Popular Tags") else { return [] }
        let chunk = String(html[range.upperBound...].prefix(20_000))
        var seen = Set<String>()
        return allMatches(#"<a[^>]*href="/tag/([^/"]+)/(?:cheat-sheets/)?"[^>]*>([^<]+)</a>"#, in: chunk).compactMap { match in
            guard seen.insert(match[1]).inserted else { return nil }
            // Link text reads "linux (240)".
            let text = plain(match[2])
            if let count = firstMatch(#"\((\d+)\)\s*$"#, in: text).flatMap({ Int($0) }),
               let paren = text.range(of: "(", options: .backwards) {
                return CatalogTag(slug: match[1], name: String(text[..<paren.lowerBound]).trimmed, count: count)
            }
            return CatalogTag(slug: match[1], name: text, count: nil)
        }
    }
}
