import Foundation

public enum ImportFormat: String, Codable, CaseIterable, Sendable {
    case auto, markdown, html, delimited, json

    public var label: String {
        switch self {
        case .auto: "Auto-detect"
        case .markdown: "Markdown"
        case .html: "HTML"
        case .delimited: "Table (CSV / TSV / columns)"
        case .json: "JSON"
        }
    }

    public var shortLabel: String {
        switch self {
        case .auto: "Auto"
        case .markdown: "Markdown"
        case .html: "HTML"
        case .delimited: "Table"
        case .json: "JSON"
        }
    }

    /// Guess a format from a file extension.
    public static func from(fileExtension ext: String) -> ImportFormat {
        switch ext.lowercased() {
        case "md", "markdown", "mdown", "mkd", "txt", "text": .markdown
        case "html", "htm", "xhtml", "webarchive": .html
        case "csv", "tsv", "tab", "psv": .delimited
        case "json": .json
        default: .auto
        }
    }

    /// Heuristic content sniffing.
    public static func detect(_ text: String) -> ImportFormat {
        let t = text.trimmed
        guard !t.isEmpty else { return .markdown }

        if (t.hasPrefix("{") && t.hasSuffix("}")) || (t.hasPrefix("[") && t.hasSuffix("]")),
           let data = t.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
            return .json
        }

        let lower = t.prefix(4000).lowercased()
        if lower.hasPrefix("<!doctype html") || lower.contains("<html") || lower.contains("<body") {
            return .html
        }
        let tagCount = t.prefix(20000).matches(of: /<\/?(table|tr|td|th|ul|ol|li|dl|dt|dd|h[1-6]|p|div|span|kbd|code|pre|section|article|br)\b[^>]*>/.ignoresCase()).count
        if tagCount >= 3 && t.hasPrefix("<") { return .html }

        let lines = t.components(separatedBy: .newlines)
        let markdownSignals = lines.filter { line in
            let l = line.trimmed
            return MarkdownImporter.atxHeading(l) != nil
                || MarkdownImporter.isTableDelimiter(l)
                || MarkdownImporter.fenceMarker(l) != nil
                || MarkdownImporter.listItem(line) != nil
        }.count
        if tagCount >= 6 && markdownSignals == 0 { return .html }
        if markdownSignals > 0 { return .markdown }

        if DelimitedImporter.tabularConfidence(t) >= 0.6 { return .delimited }
        return .markdown
    }
}

public struct ImportOptions: Sendable {
    public var format: ImportFormat
    /// Explicit title from the user; overrides anything found in the document.
    public var title: String?
    /// Used when the document has no title of its own (e.g. a file name).
    public var fallbackTitle: String?
    public var delimiter: Delimiter?
    public var header: HeaderMode
    public var origin: String?
    /// When false, loose paragraphs are dropped and only headings, tables, lists and code are kept
    /// (useful for web pages full of prose around the actual cheet).
    public var keepParagraphs: Bool

    public init(format: ImportFormat = .auto, title: String? = nil, fallbackTitle: String? = nil,
                delimiter: Delimiter? = nil, header: HeaderMode = .auto, origin: String? = nil,
                keepParagraphs: Bool = true) {
        self.format = format
        self.title = title
        self.fallbackTitle = fallbackTitle
        self.delimiter = delimiter
        self.header = header
        self.origin = origin
        self.keepParagraphs = keepParagraphs
    }
}

public struct ImportResult: Sendable {
    public var cheet: Cheet
    public var detectedFormat: ImportFormat
    /// The title found in the document itself (before user overrides).
    public var documentTitle: String?
}

public enum ImportError: LocalizedError, Equatable {
    case empty
    case nothingRecognized
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .empty: "There's nothing to import yet."
        case .nothingRecognized: "Couldn't find any headings, tables, lists or text to turn into a cheet."
        case .invalidJSON(let reason): "The JSON couldn't be read: \(reason)"
        }
    }
}

public enum CheetImporter {
    public static func importCheet(_ text: String, options: ImportOptions = ImportOptions()) throws -> ImportResult {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { throw ImportError.empty }

        let format = options.format == .auto ? ImportFormat.detect(trimmed) : options.format
        var documentTitle: String?
        var sections: [CheetSection] = []

        switch format {
        case .json:
            switch try JSONImporter.parse(trimmed) {
            case .cheet(let cheet):
                documentTitle = cheet.title
                sections = cheet.sections.map { CheetSection(title: $0.title, blocks: $0.blocks, layout: $0.layout) }
            case .events(let events):
                (documentTitle, sections) = SectionBuilder.build(events: filter(events, options))
            }
        case .html:
            let parsed = HTMLImporter.parse(trimmed, baseURL: options.origin.flatMap { URL(string: $0) }.flatMap { $0.scheme == nil ? nil : $0 })
            let built = SectionBuilder.build(events: filter(parsed.events, options))
            documentTitle = built.title ?? parsed.documentTitle
            sections = built.sections
        case .delimited:
            let events = DelimitedImporter.events(from: trimmed, delimiter: options.delimiter, header: options.header)
            (documentTitle, sections) = SectionBuilder.build(events: events)
        case .markdown, .auto:
            (documentTitle, sections) = SectionBuilder.build(events: filter(MarkdownImporter.events(from: trimmed), options))
        }

        guard !sections.isEmpty else { throw ImportError.nothingRecognized }

        let plainDocTitle = documentTitle.map(InlineMarkdown.plainText)
        let title = [options.title, plainDocTitle, options.fallbackTitle]
            .compactMap { $0?.trimmed }
            .first { !$0.isEmpty } ?? "Untitled Cheet"

        let cheet = Cheet(
            title: title,
            sections: sections,
            source: CheetSource(format: format, origin: options.origin)
        )
        return ImportResult(cheet: cheet, detectedFormat: format, documentTitle: plainDocTitle)
    }

    private static func filter(_ events: [OutlineEvent], _ options: ImportOptions) -> [OutlineEvent] {
        guard !options.keepParagraphs else { return events }
        return events.filter { event in
            if case .block(.text) = event { return false }
            return true
        }
    }

    /// Turns a file name like `git-cheat_sheet.md` into "Git Cheat Sheet".
    public static func title(fromFileName name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let spaced = base.replacingOccurrences(of: #"[-_.]+"#, with: " ", options: .regularExpression).trimmed
        guard spaced.lowercased() == spaced else { return spaced }
        return spaced.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
