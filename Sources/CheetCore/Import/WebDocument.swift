import Foundation

/// Content extracted from a web page, before the user picks which elements become the cheet.
public struct WebDocument: Sendable, Equatable {
    public var title: String?
    public var summary: String?
    public var author: String?
    public var siteName: String?
    public var sourceURL: URL?
    public var sections: [CheetSection]
    /// Which extraction path produced this ("Cheatography", "Main content", "Whole page", "Markdown"…).
    public var extractorName: String
    /// Whether the page has a main-content region the user can toggle between.
    public var hasMainContent: Bool

    public init(title: String? = nil, summary: String? = nil, author: String? = nil, siteName: String? = nil,
                sourceURL: URL? = nil, sections: [CheetSection], extractorName: String, hasMainContent: Bool = false) {
        self.title = title
        self.summary = summary
        self.author = author
        self.siteName = siteName
        self.sourceURL = sourceURL
        self.sections = sections
        self.extractorName = extractorName
        self.hasMainContent = hasMainContent
    }

    /// "by DaveChild · Cheatography"
    public var attribution: String? {
        let parts = [author.map { "by \($0)" }, siteName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public var elementCount: Int { sections.reduce(0) { $0 + $1.blocks.count } }

    /// Builds the cheet from the selected elements.
    public func cheet(selection: ElementSelection, title override: String? = nil) -> Cheet {
        var result: [CheetSection] = []
        for section in sections where selection.includes(section.id) {
            var blocks: [CheetBlock] = []
            for (index, block) in section.blocks.enumerated() where selection.includes(section.id, block: index) {
                blocks.append(block)
            }
            blocks = Self.droppingDanglingHeadings(blocks)
            if !blocks.isEmpty {
                result.append(CheetSection(id: section.id, title: section.title, blocks: blocks, layout: section.layout))
            }
        }
        let name = [override, title].compactMap { $0?.trimmed }.first { !$0.isEmpty } ?? "Untitled Cheet"
        return Cheet(
            title: name,
            sections: result,
            source: CheetSource(format: .html, origin: sourceURL?.absoluteString, attribution: attribution)
        )
    }

    private static func droppingDanglingHeadings(_ blocks: [CheetBlock]) -> [CheetBlock] {
        var kept: [CheetBlock] = []
        for (index, block) in blocks.enumerated() {
            if block.isHeading {
                let next = blocks[(index + 1)...].first
                if next == nil || next!.isHeading { continue }
            }
            kept.append(block)
        }
        return kept
    }

    // MARK: - Suggested selection

    private static let boilerplateTitles = try! NSRegularExpression(
        pattern: #"^(comments?|leave a (comment|reply)|related( (posts|articles|cheat ?sheets|cheets))?|share( this)?|newsletter|subscribe|"#
            + #"footer|navigation|menu|table of contents|contents|on this page|about( the)? author|advertisement|sponsored|"#
            + #"you (may|might) also like|popular (posts|articles)|recent (posts|articles)|tags|categories|follow us|"#
            + #"sign up|log ?in|download|downloads|metadata|favourited by|comments & ratings)\b"#,
        options: [.caseInsensitive]
    )
    private static let boilerplateText = try! NSRegularExpression(
        pattern: #"(cookie|©|copyright|all rights reserved|subscribe|newsletter|sign up|privacy policy|terms of (use|service)|"#
            + #"advertis|sponsored|share on|follow us)"#,
        options: [.caseInsensitive]
    )

    /// Pre-deselects elements that look like page chrome: navigation link lists, boilerplate text,
    /// long prose, and sections such as "Comments" or "Related posts".
    public func suggestedSelection() -> ElementSelection {
        var selection = ElementSelection()
        for section in sections {
            let plainTitle = InlineMarkdown.plainText(section.title).trimmed
            if Self.matches(Self.boilerplateTitles, plainTitle) {
                selection.excluded.insert(ElementRef(section: section.id))
                continue
            }
            for (index, block) in section.blocks.enumerated() where Self.looksLikeChrome(block) {
                selection.excluded.insert(ElementRef(section: section.id, block: index))
            }
        }
        // Never suggest an empty cheet.
        if cheet(selection: selection).sections.isEmpty { return ElementSelection() }
        return selection
    }

    static func looksLikeChrome(_ block: CheetBlock) -> Bool {
        switch block {
        case .list(let list):
            let linkOnly = list.items.filter { item in
                let t = ListBlock.depthAndText(item).text.trimmed
                return t.hasPrefix("[") && t.hasSuffix(")") && t.contains("](")
            }
            return !list.items.isEmpty && Double(linkOnly.count) / Double(list.items.count) >= 0.8
        case .text(let text):
            let plain = InlineMarkdown.plainText(text)
            return plain.count > 500 || matches(boilerplateText, plain)
        case .image(let image):
            // Tracking pixels, spacers and avatars rarely matter on a cheet.
            let s = image.source.lowercased()
            if s.contains("avatar") || s.contains("gravatar") || s.contains("pixel") || s.contains("spacer") || s.contains("/ads/") || s.contains("logo") {
                return true
            }
            // Wikimedia-style thumbnails narrower than 60px are icons.
            if let range = s.range(of: #"/(\d{1,2})px-"#, options: .regularExpression) {
                return Int(s[range].filter(\.isNumber)).map { $0 < 60 } ?? false
            }
            return false
        case .table, .code, .heading:
            return false
        }
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - Describing elements

    public struct ElementSummary: Sendable, Equatable {
        public var kind: Kind
        public var detail: String
        public var count: Int?

        public enum Kind: String, Sendable {
            case table, list, text, code, heading, image
            public var label: String { rawValue.capitalized }
        }
    }

    /// One-line description of a block for the element picker.
    public static func summary(of block: CheetBlock) -> ElementSummary {
        func clip(_ s: String, _ n: Int = 90) -> String {
            let flat = InlineMarkdown.collapseWhitespace(s).trimmed
            return flat.count > n ? String(flat.prefix(n - 1)) + "…" : flat
        }
        switch block {
        case .table(let table):
            let first = (table.headers ?? table.rows.first ?? []).map(InlineMarkdown.plainText).filter { !$0.isEmpty }
            return ElementSummary(kind: .table, detail: clip(first.joined(separator: " · ")), count: table.rows.count)
        case .list(let list):
            let first = list.items.first.map { InlineMarkdown.plainText(ListBlock.depthAndText($0).text) } ?? ""
            return ElementSummary(kind: .list, detail: clip(first), count: list.items.count)
        case .text(let text):
            return ElementSummary(kind: .text, detail: clip(InlineMarkdown.plainText(text)), count: nil)
        case .code(let code):
            let lines = code.code.components(separatedBy: "\n")
            return ElementSummary(kind: .code, detail: clip(lines.first ?? ""), count: lines.count)
        case .heading(let text):
            return ElementSummary(kind: .heading, detail: clip(InlineMarkdown.plainText(text)), count: nil)
        case .image(let image):
            let label = [image.alt, image.caption.map(InlineMarkdown.plainText) ?? ""].first { !$0.isEmpty }
                ?? URL(string: image.source)?.lastPathComponent ?? "Image"
            return ElementSummary(kind: .image, detail: clip(label), count: nil)
        }
    }

    /// Strips a trailing "Cheat Sheet" / "Cheatsheet" from page titles.
    public static func cleanTitle(_ raw: String?) -> String? {
        guard var title = raw.map({ HTMLImporter.decodeEntities($0).trimmed }), !title.isEmpty else { return nil }
        title = title.replacingOccurrences(of: #"\s*[-–—:|]?\s*cheat ?sheets?$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return title.trimmed.isEmpty ? raw : title.trimmed
    }
}

/// Identifies a section (`block == nil`) or one block inside it.
public struct ElementRef: Hashable, Sendable {
    public var section: UUID
    public var block: Int?

    public init(section: UUID, block: Int? = nil) {
        self.section = section
        self.block = block
    }
}

/// Which extracted elements are left out. Everything not excluded is included.
public struct ElementSelection: Sendable, Equatable {
    public var excluded: Set<ElementRef> = []

    public init() {}

    public func includes(_ section: UUID) -> Bool {
        !excluded.contains(ElementRef(section: section))
    }

    public func includes(_ section: UUID, block: Int) -> Bool {
        includes(section) && !excluded.contains(ElementRef(section: section, block: block))
    }

    public enum State: Sendable { case on, off, mixed }

    /// Tri-state for a section row: all, none, or some of its blocks included.
    public func state(of section: CheetSection) -> State {
        guard includes(section.id) else { return .off }
        let included = section.blocks.indices.filter { includes(section.id, block: $0) }.count
        if included == section.blocks.count { return .on }
        return included == 0 ? .off : .mixed
    }

    public mutating func setSection(_ section: CheetSection, included: Bool) {
        let ref = ElementRef(section: section.id)
        for index in section.blocks.indices { excluded.remove(ElementRef(section: section.id, block: index)) }
        if included { excluded.remove(ref) } else { excluded.insert(ref) }
    }

    public mutating func setBlock(_ index: Int, in section: CheetSection, included: Bool) {
        let ref = ElementRef(section: section.id, block: index)
        if included {
            excluded.remove(ref)
            excluded.remove(ElementRef(section: section.id)) // re-including a block re-includes its section
        } else {
            excluded.insert(ref)
        }
    }
}

// MARK: - Extraction entry point

public enum WebExtractor {
    /// Turns a fetched page into selectable content. HTML goes through the Cheatography extractor
    /// when it recognises the page, otherwise the generic HTML reader; other text formats
    /// (Markdown, CSV, JSON served from a URL) go through the normal importer.
    public static func extract(text: String, url: URL?, mimeType: String? = nil, mainContentOnly: Bool = true) -> WebDocument {
        let mime = (mimeType ?? "").lowercased()
        let pathFormat = url.map { ImportFormat.from(fileExtension: $0.pathExtension) } ?? .auto
        let detected = ImportFormat.detect(text)
        let isHTML = mime.contains("html") || (pathFormat == .html) || (detected == .html && !mime.contains("markdown"))

        if isHTML {
            if CheatographyExtractor.canHandle(html: text) {
                return CheatographyExtractor.extract(html: text, url: url)
            }
            return genericHTML(text, url: url, mainContentOnly: mainContentOnly)
        }

        let format: ImportFormat = mime.contains("csv") || mime.contains("tab-separated") ? .delimited
            : mime.contains("json") ? .json
            : (pathFormat == .markdown || pathFormat == .auto) ? .auto : pathFormat
        let fallbackTitle = url.flatMap { $0.lastPathComponent.isEmpty ? nil : CheetImporter.title(fromFileName: $0.lastPathComponent) }
        guard let result = try? CheetImporter.importCheet(text, options: ImportOptions(format: format, fallbackTitle: fallbackTitle)) else {
            return WebDocument(sourceURL: url, sections: [], extractorName: "Text")
        }
        return WebDocument(
            title: result.documentTitle ?? fallbackTitle,
            siteName: url?.host,
            sourceURL: url,
            sections: result.cheet.sections,
            extractorName: result.detectedFormat.label
        )
    }

    static func genericHTML(_ html: String, url: URL?, mainContentOnly: Bool) -> WebDocument {
        let meta = HTMLMetadata(html: html)
        let main = HTMLImporter.mainContent(html)
        let scoped = mainContentOnly ? main : nil
        let parsed = HTMLImporter.parse(scoped ?? html, baseURL: HTMLImporter.documentBase(html) ?? url)
        let built = SectionBuilder.build(events: parsed.events)
        let title = WebDocument.cleanTitle(meta.title ?? built.title.map(InlineMarkdown.plainText) ?? parsed.documentTitle)
        return WebDocument(
            title: title,
            summary: meta.description,
            author: meta.author,
            siteName: meta.siteName ?? url?.host,
            sourceURL: meta.canonicalURL ?? url,
            sections: built.sections,
            extractorName: scoped != nil ? "Main content" : "Whole page",
            hasMainContent: main != nil
        )
    }
}

/// `<meta>` / `<title>` values from a page.
struct HTMLMetadata {
    var title: String?
    var description: String?
    var author: String?
    var siteName: String?
    var canonicalURL: URL?

    init(html: String) {
        let head = String(html.prefix(200_000))
        var values: [String: String] = [:]
        let metaRegex = try! NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: .caseInsensitive)
        let attrRegex = try! NSRegularExpression(pattern: #"([a-zA-Z:-]+)\s*=\s*("([^"]*)"|'([^']*)')"#)
        for match in metaRegex.matches(in: head, range: NSRange(head.startIndex..., in: head)) {
            guard let range = Range(match.range, in: head) else { continue }
            let tag = String(head[range])
            var attrs: [String: String] = [:]
            for a in attrRegex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                guard let k = Range(a.range(at: 1), in: tag) else { continue }
                let v = Range(a.range(at: 3), in: tag) ?? Range(a.range(at: 4), in: tag)
                attrs[tag[k].lowercased()] = v.map { String(tag[$0]) } ?? ""
            }
            if let key = (attrs["property"] ?? attrs["name"])?.lowercased(), let content = attrs["content"], !content.isEmpty {
                values[key] = HTMLImporter.decodeEntities(content)
            }
        }
        title = values["og:title"] ?? values["twitter:title"]
        if title == nil, let range = head.range(of: #"<title[^>]*>([\s\S]*?)</title>"#, options: [.regularExpression, .caseInsensitive]) {
            let raw = head[range].replacingOccurrences(of: #"</?title[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
            var clean = InlineMarkdown.collapseWhitespace(HTMLImporter.decodeEntities(raw)).trimmed
            for separator in [" | ", " — ", " – ", " · ", " - "] {
                if let r = clean.range(of: separator) { clean = String(clean[..<r.lowerBound]).trimmed }
            }
            title = clean.isEmpty ? nil : clean
        }
        description = values["og:description"] ?? values["description"] ?? values["twitter:description"]
        author = values["author"] ?? values["article:author"]
        siteName = values["og:site_name"] ?? values["application-name"]
        canonicalURL = values["og:url"].flatMap(URL.init(string:))
    }
}
