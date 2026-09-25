import AppKit
import CheetCore
import Observation

/// State behind "Import from URL": the fetched page, the extracted elements, and which are selected.
@MainActor @Observable
final class WebImportModel {
    let appModel: AppModel

    var urlString: String
    private(set) var isFetching = false
    private(set) var errorMessage: String?
    private(set) var page: WebFetcher.Page?
    private(set) var document: WebDocument?

    var selection = ElementSelection()
    /// Sections whose element rows are expanded in the picker.
    var expanded: Set<UUID> = []
    var title = ""
    var hotkey = HotkeyAssignment.automatic
    /// Update the cheet previously imported from this page instead of adding a new one.
    var replaceExisting = true

    /// For generic pages: only the `<main>`/`<article>` region, or the whole page.
    var mainContentOnly = true {
        didSet { if oldValue != mainContentOnly { extract() } }
    }

    init(appModel: AppModel, url: URL?) {
        self.appModel = appModel
        urlString = url?.absoluteString ?? ""
    }

    // MARK: Fetching

    func fetch() async {
        guard let url = WebFetcher.normalizedURL(urlString) else {
            errorMessage = WebFetcher.FetchError.invalidURL.localizedDescription
            return
        }
        urlString = url.absoluteString
        isFetching = true
        errorMessage = nil
        defer { isFetching = false }
        do {
            page = try await WebFetcher.fetch(url)
            extract()
        } catch {
            errorMessage = "Couldn't load the page: \(error.localizedDescription)"
        }
    }

    private func extract() {
        guard let page else { return }
        let doc = WebExtractor.extract(text: page.text, url: page.url, mimeType: page.mimeType, mainContentOnly: mainContentOnly)
        document = doc
        selection = doc.suggestedSelection()
        if !appModel.settings.behavior.importImages {
            for section in doc.sections {
                for (index, block) in section.blocks.enumerated() {
                    if case .image = block { selection.excluded.insert(ElementRef(section: section.id, block: index)) }
                }
            }
        }
        title = doc.title ?? page.url.host ?? ""
        expanded = doc.elementCount <= 80 ? Set(doc.sections.map(\.id)) : []
        if doc.sections.isEmpty {
            errorMessage = CheatographyCatalog.isCheatSheetURL(page.url)
                ? "This Cheatography entry has no text content to import (it's probably a PDF or image upload)."
                : "No headings, tables, lists or code were found on this page."
        } else {
            errorMessage = nil
        }
    }

    // MARK: Selection

    var previewCheet: Cheet? {
        document?.cheet(selection: selection, title: title)
    }

    var totalCount: Int { document?.elementCount ?? 0 }

    var selectedCount: Int {
        guard let document else { return 0 }
        return document.sections.reduce(0) { total, section in
            total + section.blocks.indices.filter { selection.includes(section.id, block: $0) }.count
        }
    }

    func setAll(_ included: Bool) {
        guard let document else { return }
        var next = ElementSelection()
        if !included {
            for section in document.sections { next.excluded.insert(ElementRef(section: section.id)) }
        }
        selection = next
    }

    /// Keep tables, lists and code; drop loose text.
    func selectStructured() {
        guard let document else { return }
        var next = ElementSelection()
        for section in document.sections {
            for (index, block) in section.blocks.enumerated() {
                switch block {
                case .text: next.excluded.insert(ElementRef(section: section.id, block: index))
                default: break
                }
            }
        }
        selection = next
    }

    func useSuggestions() {
        if let document { selection = document.suggestedSelection() }
    }

    func toggle(section: CheetSection) {
        selection.setSection(section, included: selection.state(of: section) != .on)
    }

    func toggle(block index: Int, in section: CheetSection) {
        selection.setBlock(index, in: section, included: !selection.includes(section.id, block: index))
    }

    // MARK: Library

    /// A cheet previously imported from this page.
    var existingCheet: Cheet? {
        guard let key = WebFetcher.libraryKey(document?.sourceURL?.absoluteString ?? page?.url.absoluteString) else { return nil }
        return appModel.cheets.first { WebFetcher.libraryKey($0.source?.origin) == key }
    }

    @discardableResult
    func commit() -> UUID? {
        guard var cheet = previewCheet, !cheet.sections.isEmpty else { return nil }
        if replaceExisting, var existing = existingCheet {
            existing.replaceContent(with: cheet)
            existing.hotkey = hotkey.mode == .automatic ? existing.hotkey : hotkey
            appModel.update(existing)
            return existing.id
        }
        cheet.sections = cheet.sections.map { CheetSection(title: $0.title, blocks: $0.blocks, layout: $0.layout) }
        cheet.hotkey = hotkey
        return appModel.add(cheet)
    }

    /// Lets the user send any page they're viewing in their browser here.
    static let bookmarklet = "javascript:location.href='cheetwithbothhands://import-url?url='+encodeURIComponent(location.href)"
}
