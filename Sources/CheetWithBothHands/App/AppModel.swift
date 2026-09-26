import AppKit
import CheetCore
import Observation
import SwiftUI

/// Central, observable app state: the cheet library, settings and remembered view state.
/// Every mutation is persisted (debounced) and hotkeys are re-resolved when relevant inputs change.
@MainActor @Observable
final class AppModel {
    var cheets: [Cheet] {
        didSet {
            scheduleSave(.cheets)
            recomputeHotkeys()
        }
    }

    var workspaces: [Workspace] = [] {
        didSet {
            scheduleSave(.cheets) // workspaces live in library.json with the cheets
            recomputeHotkeys()
        }
    }

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            scheduleSave(.settings)
            if settings.hotkeys != oldValue.hotkeys { recomputeHotkeys() }
            for observer in settingsObservers { observer(oldValue, settings) }
        }
    }

    var viewState: ViewState {
        didSet { if viewState != oldValue { scheduleSave(.viewState) } }
    }

    private(set) var hotkeyPlan = HotkeyPlan()
    /// Combos the system refused to register (usually taken by another app).
    var hotkeyFailures: Set<KeyCombo> = []

    @ObservationIgnored let store: LibraryStore
    @ObservationIgnored private(set) var isFirstLaunch = false
    @ObservationIgnored var onHotkeyPlanChanged: (() -> Void)?
    @ObservationIgnored private var settingsObservers: [(AppSettings, AppSettings) -> Void] = []
    @ObservationIgnored private var pendingSaves: Set<SaveKind> = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    enum SaveKind { case cheets, settings, viewState }

    init(store: LibraryStore = LibraryStore()) {
        self.store = store
        store.backupLibrary()
        settings = store.loadSettings()
        viewState = store.loadViewState()

        var loaded: Library? = nil
        do {
            loaded = try store.loadLibrary()
        } catch {
            NSLog("Cheet with Both Hands: failed to read library: \(error)")
        }
        if let loaded {
            cheets = loaded.cheets
            workspaces = loaded.workspaces
        } else {
            cheets = SampleCheets.all()
            isFirstLaunch = !viewState.hasLaunchedBefore
            pendingSaves.insert(.cheets)
        }
        viewState.hasLaunchedBefore = true
        hotkeyPlan = HotkeyResolver.resolve(cheets: cheets, settings: settings.hotkeys)
        scheduleSave(.viewState)
    }

    // MARK: - Observation hooks

    func addSettingsObserver(_ observer: @escaping (AppSettings, AppSettings) -> Void) {
        settingsObservers.append(observer)
    }

    private func recomputeHotkeys() {
        let plan = HotkeyResolver.resolve(cheets: cheets, settings: settings.hotkeys)
        guard plan != hotkeyPlan else { return }
        hotkeyPlan = plan
        onHotkeyPlanChanged?()
    }

    // MARK: - Cheets

    func cheet(id: UUID?) -> Cheet? {
        guard let id else { return nil }
        return cheets.first { $0.id == id }
    }

    func index(of id: UUID?) -> Int? {
        guard let id else { return nil }
        return cheets.firstIndex { $0.id == id }
    }

    func combo(forCheet id: UUID) -> KeyCombo? { hotkeyPlan.cheetCombos[id] }

    @discardableResult
    func add(_ cheet: Cheet, at index: Int? = nil) -> UUID {
        let cheet = ImageStore.shared.localize(cheet)
        if let index, index <= cheets.count { cheets.insert(cheet, at: index) } else { cheets.append(cheet) }
        ImageStore.shared.prefetch([cheet])
        return cheet.id
    }

    func update(_ cheet: Cheet) {
        guard let i = index(of: cheet.id) else { return }
        var updated = ImageStore.shared.localize(cheet)
        if updated.sections != cheets[i].sections || updated.title != cheets[i].title { updated.updatedAt = Date() }
        let contentChanged = updated.sections.map(\.blocks) != cheets[i].sections.map(\.blocks)
        cheets[i] = updated
        if contentChanged { ImageStore.shared.prefetch([updated]) }
    }

    func delete(_ id: UUID) {
        cheets.removeAll { $0.id == id }
        let remaining = Set(cheets.map(\.id))
        if workspaces.contains(where: { $0.windows.contains { $0.cheetID == id } }) {
            workspaces = workspaces.map { $0.pruned(keeping: remaining) }
        }
        viewState.cheets[id.uuidString] = nil
        if viewState.lastCheetID == id { viewState.lastCheetID = nil }
    }

    @discardableResult
    func duplicate(_ id: UUID) -> UUID? {
        guard let i = index(of: id) else { return nil }
        var copy = cheets[i]
        copy.id = UUID()
        copy.title += " copy"
        copy.sections = copy.sections.map { CheetSection(title: $0.title, blocks: $0.blocks, layout: $0.layout) }
        if copy.hotkey.mode == .custom { copy.hotkey = .automatic }
        copy.createdAt = Date()
        copy.updatedAt = Date()
        cheets.insert(copy, at: i + 1)
        return copy.id
    }

    func move(from source: IndexSet, to destination: Int) {
        cheets.move(fromOffsets: source, toOffset: destination)
    }

    func restoreSamples() {
        let existing = Set(cheets.map(\.title))
        for sample in SampleCheets.all() where !existing.contains(sample.title) {
            cheets.append(sample)
        }
    }

    /// Binding to a cheet by identity (safe when the list changes underneath a view).
    func binding(forCheet id: UUID) -> Binding<Cheet> {
        Binding(
            get: { [weak self] in self?.cheet(id: id) ?? Cheet(id: id, title: "", sections: []) },
            set: { [weak self] in self?.update($0) }
        )
    }

    // MARK: - Appearance

    func appearance(for cheetID: UUID?) -> Appearance {
        cheet(id: cheetID)?.appearance ?? settings.appearance
    }

    /// Writes to the cheet's own override if it has one, otherwise to the global appearance.
    func setAppearance(_ appearance: Appearance, for cheetID: UUID?) {
        if let id = cheetID, let i = index(of: id), cheets[i].appearance != nil {
            cheets[i].appearance = appearance
        } else {
            settings.appearance = appearance
        }
    }

    func appearanceBinding(for cheetID: UUID?) -> Binding<Appearance> {
        Binding(
            get: { [weak self] in self?.appearance(for: cheetID) ?? Appearance() },
            set: { [weak self] in self?.setAppearance($0, for: cheetID) }
        )
    }

    // MARK: - Persistence

    private func scheduleSave(_ kind: SaveKind) {
        pendingSaves.insert(kind)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flushSaves()
        }
    }

    func flushSaves() {
        let kinds = pendingSaves
        pendingSaves.removeAll()
        do {
            if kinds.contains(.cheets) { try store.saveLibrary(Library(cheets: cheets, workspaces: workspaces)) }
            if kinds.contains(.settings) { try store.saveSettings(settings) }
            if kinds.contains(.viewState) { try store.saveViewState(viewState) }
        } catch {
            NSLog("Cheet with Both Hands: save failed: \(error)")
        }
    }
}
