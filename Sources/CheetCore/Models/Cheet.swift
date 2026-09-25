import Foundation

/// A single cheet: a titled collection of sections, each holding renderable blocks.
public struct Cheet: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var sections: [CheetSection]
    public var hotkey: HotkeyAssignment
    /// Per-cheet appearance override. `nil` means "use the global appearance".
    public var appearance: Appearance?
    public var source: CheetSource?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        sections: [CheetSection],
        hotkey: HotkeyAssignment = .automatic,
        appearance: Appearance? = nil,
        source: CheetSource? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.sections = sections
        self.hotkey = hotkey
        self.appearance = appearance
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Number of "entries" (table rows, list items, text/code blocks) across all sections.
    public var entryCount: Int { sections.reduce(0) { $0 + $1.entryCount } }

    /// Sections that aren't hidden in the layout.
    public var visibleSections: [CheetSection] { sections.filter { !$0.layout.isHidden } }
    public var hiddenSectionCount: Int { sections.count - visibleSections.count }

    /// Replaces the content (title + sections) while keeping identity, hotkey and appearance.
    /// Sections are matched to the old ones by title so their layout, style and collapsed state survive.
    public mutating func replaceContent(with other: Cheet) {
        title = other.title
        var previous = sections
        sections = other.sections.map { incoming in
            var section = incoming
            if let match = previous.firstIndex(where: { $0.title == incoming.title }) {
                section.id = previous[match].id
                if incoming.layout.isDefault { section.layout = previous[match].layout }
                previous.remove(at: match)
            }
            return section
        }
        if let source = other.source { self.source = source }
        updatedAt = Date()
    }
}

extension Cheet: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, sections, hotkey, appearance, source, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Cheet"
        sections = try c.decodeIfPresent([CheetSection].self, forKey: .sections) ?? []
        hotkey = (try? c.decodeIfPresent(HotkeyAssignment.self, forKey: .hotkey)) ?? .automatic
        appearance = try? c.decodeIfPresent(Appearance.self, forKey: .appearance)
        source = try? c.decodeIfPresent(CheetSource.self, forKey: .source)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(sections, forKey: .sections)
        try c.encode(hotkey, forKey: .hotkey)
        try c.encodeIfPresent(appearance, forKey: .appearance)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct CheetSource: Codable, Hashable, Sendable {
    public var format: ImportFormat
    /// File path or URL the cheet was imported from, if any.
    public var origin: String?
    /// Credit for web imports, e.g. "by DaveChild · Cheatography".
    public var attribution: String?

    public init(format: ImportFormat, origin: String? = nil, attribution: String? = nil) {
        self.format = format
        self.origin = origin
        self.attribution = attribution
    }
}

public struct CheetSection: Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Empty string for an untitled (intro) section.
    public var title: String
    public var blocks: [CheetBlock]
    /// Card arrangement and styling in the overlay.
    public var layout: SectionLayout

    public init(id: UUID = UUID(), title: String, blocks: [CheetBlock], layout: SectionLayout = SectionLayout()) {
        self.id = id
        self.title = title
        self.blocks = blocks
        self.layout = layout
    }

    public var entryCount: Int {
        blocks.reduce(0) { total, block in
            switch block {
            case .heading: return total
            case .table(let t): return total + t.rows.count
            case .list(let l): return total + l.items.count
            case .text, .code, .image: return total + 1
            }
        }
    }

    /// True when the section contains a table wide enough that it reads better spanning the full overlay width.
    public var prefersFullWidth: Bool {
        blocks.contains { block in
            if case .table(let t) = block { return t.columnCount >= 4 }
            return false
        }
    }
}

extension CheetSection: Codable {
    private enum CodingKeys: String, CodingKey { case id, title, blocks, layout }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        blocks = try c.decodeIfPresent([CheetBlock].self, forKey: .blocks) ?? []
        layout = c.value(.layout, or: SectionLayout())
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(blocks, forKey: .blocks)
        if !layout.isDefault { try c.encode(layout, forKey: .layout) }
    }
}

/// Renderable content inside a section. All text is stored as *inline* Markdown
/// (backticks, **bold**, *italic*, [links](…)) so styling survives import from any format.
public enum CheetBlock: Hashable, Sendable {
    case heading(String)
    case table(CheetTable)
    case list(ListBlock)
    case text(String)
    case code(CodeBlock)
    case image(ImageBlock)
}

extension CheetBlock: Codable {
    private enum CodingKeys: String, CodingKey { case type, text, headers, rows, items, ordered, language, code, source, alt, caption }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? "text"
        switch type {
        case "heading":
            self = .heading(try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "table":
            self = .table(CheetTable(
                headers: try c.decodeIfPresent([String].self, forKey: .headers),
                rows: try c.decodeIfPresent([[String]].self, forKey: .rows) ?? []
            ))
        case "list":
            self = .list(ListBlock(
                items: try c.decodeIfPresent([String].self, forKey: .items) ?? [],
                ordered: try c.decodeIfPresent(Bool.self, forKey: .ordered) ?? false
            ))
        case "code":
            self = .code(CodeBlock(
                code: try c.decodeIfPresent(String.self, forKey: .code) ?? "",
                language: try c.decodeIfPresent(String.self, forKey: .language)
            ))
        case "image":
            self = .image(ImageBlock(
                source: try c.decodeIfPresent(String.self, forKey: .source) ?? "",
                alt: try c.decodeIfPresent(String.self, forKey: .alt) ?? "",
                caption: try c.decodeIfPresent(String.self, forKey: .caption)
            ))
        default:
            self = .text(try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heading(let text):
            try c.encode("heading", forKey: .type)
            try c.encode(text, forKey: .text)
        case .table(let table):
            try c.encode("table", forKey: .type)
            try c.encodeIfPresent(table.headers, forKey: .headers)
            try c.encode(table.rows, forKey: .rows)
        case .list(let list):
            try c.encode("list", forKey: .type)
            try c.encode(list.items, forKey: .items)
            if list.ordered { try c.encode(true, forKey: .ordered) }
        case .text(let text):
            try c.encode("text", forKey: .type)
            try c.encode(text, forKey: .text)
        case .code(let code):
            try c.encode("code", forKey: .type)
            try c.encode(code.code, forKey: .code)
            try c.encodeIfPresent(code.language, forKey: .language)
        case .image(let image):
            try c.encode("image", forKey: .type)
            try c.encode(image.source, forKey: .source)
            if !image.alt.isEmpty { try c.encode(image.alt, forKey: .alt) }
            try c.encodeIfPresent(image.caption, forKey: .caption)
        }
    }
}

public struct CheetTable: Hashable, Sendable {
    public var headers: [String]?
    public var rows: [[String]]

    public init(headers: [String]? = nil, rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }

    public var columnCount: Int {
        max(headers?.count ?? 0, rows.map(\.count).max() ?? 0)
    }

    /// Rows padded so every row has `columnCount` cells.
    public var normalizedRows: [[String]] {
        let n = columnCount
        return rows.map { $0.count < n ? $0 + Array(repeating: "", count: n - $0.count) : $0 }
    }
}

public struct ListBlock: Hashable, Sendable {
    /// Nested items are stored with two leading spaces per nesting level.
    public var items: [String]
    public var ordered: Bool

    public init(items: [String], ordered: Bool = false) {
        self.items = items
        self.ordered = ordered
    }

    /// Splits a stored item into its nesting depth and its text.
    public static func depthAndText(_ item: String) -> (depth: Int, text: String) {
        let spaces = item.prefix { $0 == " " }.count
        return (spaces / 2, String(item.dropFirst(spaces)))
    }
}

public struct CodeBlock: Hashable, Sendable {
    public var code: String
    public var language: String?

    public init(code: String, language: String? = nil) {
        self.code = code
        self.language = language
    }
}

public struct ImageBlock: Hashable, Sendable {
    /// An http(s) URL, or `asset:<file>` for an image stored in the library's images folder.
    public var source: String
    public var alt: String
    /// Inline Markdown shown under the image.
    public var caption: String?

    public init(source: String, alt: String = "", caption: String? = nil) {
        self.source = source
        self.alt = alt
        self.caption = caption
    }

    public var isAsset: Bool { source.hasPrefix("asset:") }
}
