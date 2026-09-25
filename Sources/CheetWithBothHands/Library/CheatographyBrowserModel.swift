import AppKit
import CheetCore
import Observation

/// Browses cheatography.com's catalog (search, categories, tags, explore feeds) and imports from it.
@MainActor @Observable
final class CheatographyBrowserModel {
    typealias Source = CheatographyCatalog.Source

    let appModel: AppModel

    private(set) var source: Source = .feed(.popular)
    var searchText = ""
    private(set) var heading: String?
    private(set) var items: [CatalogItem] = []
    private(set) var nextPageURL: URL?
    private(set) var tagGroups: [(title: String, tags: [CatalogTag])] = []
    private(set) var popularTags: [CatalogTag] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?

    /// Items ticked for bulk import.
    var checked: Set<String> = []
    private(set) var bulkProgress: (done: Int, total: Int)?
    private(set) var statusMessage: String?

    private var cache: [URL: CatalogPage] = [:]
    private var generation = 0
    /// Pause between requests during bulk import, to be a polite client.
    private let politeDelay: Duration = .milliseconds(700)

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    // MARK: Loading

    func load(_ source: Source) async {
        self.source = source
        if case .search(let query) = source { searchText = query }
        generation += 1
        let current = generation
        isLoading = true
        errorMessage = nil
        items = []
        checked = []
        nextPageURL = nil
        defer { if current == generation { isLoading = false } }
        do {
            let page = try await page(at: source.url)
            guard current == generation else { return }
            heading = page.heading
            items = page.items
            nextPageURL = page.nextPageURL
            if !page.tagGroups.isEmpty { tagGroups = page.tagGroups } else if case .category = source { tagGroups = [] }
            if case .search = source { tagGroups = [] }
            if case .feed = source { tagGroups = [] }
        } catch {
            guard current == generation else { return }
            errorMessage = "Couldn't reach Cheatography: \(error.localizedDescription)"
        }
        if popularTags.isEmpty { await loadPopularTags() }
    }

    func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        await load(.search(query))
    }

    func loadMore() async {
        guard let url = nextPageURL, !isLoadingMore, !isLoading else { return }
        let current = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await page(at: url)
            guard current == generation else { return }
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            nextPageURL = page.nextPageURL
        } catch {
            errorMessage = "Couldn't load more: \(error.localizedDescription)"
        }
    }

    private func loadPopularTags() async {
        let url = CheatographyCatalog.baseURL.appendingPathComponent("explore/")
        if let fetched = try? await WebFetcher.fetch(url) {
            popularTags = Array(CheatographyCatalog.popularTags(fetched.text).prefix(24))
        }
    }

    private func page(at url: URL) async throws -> CatalogPage {
        if let cached = cache[url] { return cached }
        let fetched = try await WebFetcher.fetch(url)
        let page = CheatographyCatalog.parseListing(fetched.text)
        cache[url] = page
        return page
    }

    // MARK: Library status

    func isInLibrary(_ item: CatalogItem) -> Bool {
        guard let key = WebFetcher.libraryKey(item.url.absoluteString) else { return false }
        return appModel.cheets.contains { WebFetcher.libraryKey($0.source?.origin) == key }
    }

    // MARK: Importing

    /// Opens the element picker for one cheat sheet.
    func openImporter(for item: CatalogItem) {
        AppController.shared.openWebImport(item.url)
    }

    func toggleChecked(_ item: CatalogItem) {
        if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) }
    }

    /// Imports every ticked cheat sheet with all of its elements, one request at a time.
    func importChecked() async {
        let queue = items.filter { checked.contains($0.id) && !isInLibrary($0) }
        guard !queue.isEmpty else {
            statusMessage = "Those are already in your library."
            checked = []
            return
        }
        bulkProgress = (0, queue.count)
        statusMessage = nil
        var added = 0
        var failures: [String] = []
        for (index, item) in queue.enumerated() {
            if index > 0 { try? await Task.sleep(for: politeDelay) }
            do {
                let fetched = try await WebFetcher.fetch(item.url)
                let document = WebExtractor.extract(text: fetched.text, url: fetched.url, mimeType: fetched.mimeType)
                var selection = document.suggestedSelection()
                if !appModel.settings.behavior.importImages {
                    for section in document.sections {
                        for (index, block) in section.blocks.enumerated() {
                            if case .image = block { selection.excluded.insert(ElementRef(section: section.id, block: index)) }
                        }
                    }
                }
                var cheet = document.cheet(selection: selection, title: item.displayTitle)
                if cheet.sections.isEmpty {
                    failures.append("\(item.displayTitle) (no text content)")
                } else {
                    cheet.sections = cheet.sections.map { CheetSection(title: $0.title, blocks: $0.blocks) }
                    appModel.add(cheet)
                    added += 1
                }
            } catch {
                failures.append("\(item.displayTitle) (\(error.localizedDescription))")
            }
            checked.remove(item.id)
            bulkProgress = (index + 1, queue.count)
        }
        bulkProgress = nil
        statusMessage = "Imported \(added) cheet\(added == 1 ? "" : "s")"
            + (failures.isEmpty ? "." : ". Skipped: " + failures.joined(separator: ", "))
    }
}
