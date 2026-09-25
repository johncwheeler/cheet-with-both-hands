import AppKit
import CheetCore
import CryptoKit

/// Downloads and caches cheet images in the library's `images` folder, so cheets work offline and
/// the overlay never waits on the network twice. Embedded `data:` images are moved into files too.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    private(set) var directory = LibraryStore.defaultDirectory.appendingPathComponent("images", isDirectory: true)
    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var failed: Set<String> = []
    private let maxBytes = 20_000_000

    func configure(libraryDirectory: URL) {
        directory = libraryDirectory.appendingPathComponent("images", isDirectory: true)
    }

    // MARK: Lookup

    static func fileName(for source: String) -> String {
        if source.hasPrefix("asset:") { return String(source.dropFirst("asset:".count)) }
        let digest = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        return String(digest.prefix(40))
    }

    func fileURL(for source: String) -> URL {
        directory.appendingPathComponent(Self.fileName(for: source))
    }

    /// Memory or disk, without touching the network.
    func cached(_ source: String) -> NSImage? {
        if let image = memory.object(forKey: source as NSString) { return image }
        let url = fileURL(for: source)
        guard FileManager.default.fileExists(atPath: url.path), let image = NSImage(contentsOf: url) else { return nil }
        memory.setObject(image, forKey: source as NSString)
        return image
    }

    func image(for source: String) async -> NSImage? {
        if let image = cached(source) { return image }
        guard source.hasPrefix("http://") || source.hasPrefix("https://"), !failed.contains(source) else { return nil }
        if let task = inFlight[source] { return await task.value }
        let task = Task { await self.download(source) }
        inFlight[source] = task
        let image = await task.value
        inFlight[source] = nil
        if image == nil { failed.insert(source) }
        return image
    }

    private func download(_ source: String) async -> NSImage? {
        guard let url = URL(string: source) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(WebFetcher.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/*, */*;q=0.5", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard data.count <= maxBytes, let image = NSImage(data: data), image.isValid else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: source), options: .atomic)
        memory.setObject(image, forKey: source as NSString)
        return image
    }

    // MARK: Library maintenance

    private static let inlineImagePattern = try! NSRegularExpression(pattern: #"!\[(?:\\.|[^\]])*\]\(([^)\s]+)"#)

    /// Every image a cheet refers to: image blocks plus inline `![…](…)` in cells, items and text.
    static func sources(in cheet: Cheet) -> [String] {
        var result: [String] = []
        func scan(_ text: String) {
            guard text.contains("![") else { return }
            for match in inlineImagePattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { result.append(String(text[range])) }
            }
        }
        for section in cheet.sections {
            for block in section.blocks {
                switch block {
                case .image(let image): result.append(image.source)
                case .table(let table): (table.headers ?? []).forEach(scan); table.rows.joined().forEach(scan)
                case .list(let list): list.items.forEach(scan)
                case .text(let text), .heading(let text): scan(text)
                case .code: break
                }
            }
        }
        return result
    }

    /// Moves embedded `data:` images into asset files, so library.json stays small.
    func localize(_ cheet: Cheet) -> Cheet {
        guard Self.sources(in: cheet).contains(where: { $0.hasPrefix("data:") }) else { return cheet }
        var copy = cheet
        copy.sections = cheet.sections.map { section in
            var s = section
            s.blocks = section.blocks.map { block in
                if case .image(var image) = block, image.source.hasPrefix("data:") {
                    image.source = storeDataURI(image.source) ?? image.source
                    return .image(image)
                }
                return block.replacingInlineDataImages { self.storeDataURI($0) }
            }
            return s
        }
        return copy
    }

    private func storeDataURI(_ uri: String) -> String? {
        guard let comma = uri.firstIndex(of: ","), uri[..<comma].contains(";base64"),
              let data = Data(base64Encoded: String(uri[uri.index(after: comma)...]), options: .ignoreUnknownCharacters),
              data.count <= maxBytes, NSImage(data: data) != nil else { return nil }
        let name = Self.fileName(for: uri)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return "asset:\(name)"
    }

    /// Downloads any images of these cheets that aren't cached yet.
    func prefetch(_ cheets: [Cheet]) {
        let missing = Set(cheets.flatMap(Self.sources(in:))).filter {
            ($0.hasPrefix("http://") || $0.hasPrefix("https://")) && !FileManager.default.fileExists(atPath: fileURL(for: $0).path)
        }
        guard !missing.isEmpty else { return }
        Task(priority: .utility) {
            for source in missing { _ = await image(for: source) }
        }
    }

    /// Deletes cached files no cheet refers to anymore.
    func prune(keeping cheets: [Cheet]) {
        let keep = Set(cheets.flatMap(Self.sources(in:)).map(Self.fileName(for:)))
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func copyToPasteboard(_ source: String) -> Bool {
        guard let image = cached(source) else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([image])
    }
}

private extension CheetBlock {
    func replacingInlineDataImages(_ store: (String) -> String?) -> CheetBlock {
        func fix(_ text: String) -> String {
            guard text.contains("](data:") else { return text }
            var out = text
            let pattern = try! NSRegularExpression(pattern: #"\]\((data:[^)\s]+)\)"#)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let range = Range(match.range(at: 1), in: out), let asset = store(String(out[range])) else { continue }
                out.replaceSubrange(range, with: asset)
            }
            return out
        }
        switch self {
        case .table(let table): return .table(CheetTable(headers: table.headers?.map(fix), rows: table.rows.map { $0.map(fix) }))
        case .list(let list): return .list(ListBlock(items: list.items.map(fix), ordered: list.ordered))
        case .text(let text): return .text(fix(text))
        default: return self
        }
    }
}
