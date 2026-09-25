import AppKit
import CheetCore
import Observation
import UniformTypeIdentifiers

enum ImportRequest {
    case blank
    case clipboard
    case file(URL)
    case edit(UUID)
    case text(String)
}

/// State behind the import / edit window: source text, parse options, and the live parse result.
@MainActor @Observable
final class ImportModel {
    let appModel: AppModel
    let editingID: UUID?

    var source = ""
    var format: ImportFormat = .auto
    var delimiter: Delimiter? = nil
    var header: HeaderMode = .auto
    var keepParagraphs = true
    var title = ""
    var fallbackTitle: String?
    var origin: String?
    var hotkey = HotkeyAssignment.automatic

    /// Typed into the importer's URL field; handed to "Import from URL".
    var urlString = ""

    private(set) var result: ImportResult?
    private(set) var errorMessage: String?
    var notice: String?

    var isEditing: Bool { editingID != nil }

    init(appModel: AppModel, request: ImportRequest) {
        self.appModel = appModel
        switch request {
        case .edit(let id):
            editingID = id
            if let cheet = appModel.cheet(id: id) {
                source = MarkdownExporter.markdown(for: cheet)
                format = .markdown
                hotkey = cheet.hotkey
                origin = cheet.source?.origin
            }
        case .clipboard:
            editingID = nil
            pasteFromClipboard()
        case .file(let url):
            editingID = nil
            load(file: url)
        case .text(let text):
            editingID = nil
            source = text
        case .blank:
            editingID = nil
        }
        reparse()
    }

    /// Everything that affects the parse, so the view can debounce re-parsing on change.
    var parseKey: [String] {
        [source, format.rawValue, delimiter?.rawValue ?? "-", header.rawValue, title, fallbackTitle ?? "", keepParagraphs ? "1" : "0"]
    }

    /// What the cheet will look like: when editing, the new content with the existing card layout carried over.
    var previewCheet: Cheet? {
        guard let parsed = result?.cheet else { return nil }
        guard let id = editingID, var existing = appModel.cheet(id: id) else { return parsed }
        existing.replaceContent(with: parsed)
        return existing
    }

    var effectiveFormat: ImportFormat { result?.detectedFormat ?? (format == .auto ? ImportFormat.detect(source) : format) }

    func reparse() {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result = nil
            errorMessage = nil
            return
        }
        do {
            result = try CheetImporter.importCheet(source, options: ImportOptions(
                format: format,
                title: title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : title,
                fallbackTitle: fallbackTitle,
                delimiter: delimiter,
                header: header,
                origin: origin,
                keepParagraphs: keepParagraphs
            ))
            errorMessage = nil
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sources

    func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let file = urls.first {
            load(file: file)
            return
        }
        let plain = pasteboard.string(forType: .string)
        let html = pasteboard.string(forType: .html)

        // Browsers put rich HTML on the clipboard; prefer it when it carries real structure
        // and the plain text doesn't (editors also put styled HTML there for plain code/Markdown).
        if let html, Self.htmlHasStructure(html), !(plain.map(Self.plainHasStructure) ?? false) {
            source = html
            format = .html
            notice = "Pasted rich HTML from the clipboard."
        } else if let plain, !plain.isEmpty {
            source = plain
            format = .auto
            notice = "Pasted text from the clipboard."
        } else {
            notice = "The clipboard doesn't contain text."
        }
        origin = nil
        fallbackTitle = nil
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = AppController.importableTypes
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Markdown, HTML, CSV/TSV or JSON file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(file: url)
    }

    func load(file url: URL) {
        do {
            source = try FileReading.readText(url)
            let byExtension = ImportFormat.from(fileExtension: url.pathExtension)
            format = byExtension == .markdown ? .auto : byExtension
            fallbackTitle = CheetImporter.title(fromFileName: url.lastPathComponent)
            origin = url.path
            notice = "Loaded \(url.lastPathComponent)."
            reparse()
        } catch {
            notice = nil
            errorMessage = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: - Commit

    @discardableResult
    func commit() -> UUID? {
        guard var cheet = result?.cheet else { return nil }
        if let id = editingID, var existing = appModel.cheet(id: id) {
            existing.replaceContent(with: cheet)
            existing.hotkey = hotkey
            appModel.update(existing)
            return id
        }
        cheet.hotkey = hotkey
        return appModel.add(cheet)
    }

    // MARK: - Helpers

    static func htmlHasStructure(_ html: String) -> Bool {
        html.range(of: #"<(table|ul|ol|dl|h[1-6])\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func plainHasStructure(_ text: String) -> Bool {
        let format = ImportFormat.detect(text)
        if format == .json || format == .delimited || format == .html { return true }
        return text.components(separatedBy: .newlines).contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("#") || t.hasPrefix("|") || t.hasPrefix("```")
        }
    }
}
