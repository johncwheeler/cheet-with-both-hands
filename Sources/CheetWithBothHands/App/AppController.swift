import AppKit
import CheetCore
import UniformTypeIdentifiers

/// Wires the model, hotkeys, overlay, picker, menu bar and windows together.
@MainActor
final class AppController {
    static var shared: AppController!

    let model: AppModel
    let overlay: CheetWindowManager
    let picker: PickerController
    let windows: WindowManager
    private(set) var statusMenu: StatusMenuController!
    /// The launch splash, while it's on screen.
    private var splash: SplashController?

    init() {
        // CWBH_DATA_DIR points the app at an alternate library (handy for testing).
        let store: LibraryStore
        if let custom = ProcessInfo.processInfo.environment["CWBH_DATA_DIR"] {
            store = LibraryStore(directory: URL(fileURLWithPath: custom))
        } else {
            LibraryStore.migrateLegacyDirectory() // data from before the "Cheets" rename
            store = LibraryStore()
        }
        model = AppModel(store: store)
        overlay = CheetWindowManager(model: model)
        picker = PickerController(model: model)
        windows = WindowManager(model: model)
    }

    /// Shows the splash screen if it's enabled, then starts the app underneath it.
    func launch() {
        Mascot.applyAppIcon(for: model.settings.branding.iconScheme)
        guard model.settings.branding.splashEnabled, !DebugSnapshots.isRequested,
              let splash = SplashController.show(Mascot.character) else {
            start()
            return
        }
        self.splash = splash
        splash.whenFinished { [weak self] in self?.splash = nil }
        // Let the splash reach the screen before the startup work runs on the main thread.
        DispatchQueue.main.async { [weak self] in
            self?.start()
            splash.markReady()
        }
    }

    func start() {
        ImageStore.shared.configure(libraryDirectory: model.store.directory)
        ImageStore.shared.prune(keeping: model.cheets)
        ImageStore.shared.prefetch(model.cheets)
        statusMenu = StatusMenuController(controller: self)
        picker.onChoose = { [weak self] id, alongside in self?.overlay.show(cheetID: id, alongside: alongside) }

        let hotkeys = HotkeyCenter.shared
        hotkeys.install()
        hotkeys.onPress = { [weak self] action in self?.handlePress(action) }
        hotkeys.onRelease = { [weak self] action in self?.handleRelease(action) }
        model.onHotkeyPlanChanged = { [weak self] in self?.refreshHotkeys() }
        model.addSettingsObserver { [weak self] old, new in
            if old.hotkeys.enabled != new.hotkeys.enabled { self?.refreshHotkeys() }
            if old.branding.iconScheme != new.branding.iconScheme {
                Mascot.applyAppIcon(for: new.branding.iconScheme)
                self?.statusMenu.refreshIcon()
            }
        }
        refreshHotkeys()

        if DebugSnapshots.isRequested {
            DebugSnapshots.run(self)
            return
        }
        if model.isFirstLaunch, let welcome = model.cheets.first {
            if let splash {
                splash.whenFinished { [weak self] in self?.overlay.show(cheetID: welcome.id) }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.overlay.show(cheetID: welcome.id)
                }
            }
        }
    }

    // MARK: - Hotkeys

    func refreshHotkeys() {
        let bindings = model.settings.hotkeys.enabled ? model.hotkeyPlan.bindings : []
        if let failures = HotkeyCenter.shared.register(bindings) {
            model.hotkeyFailures = failures
        }
    }

    private func handlePress(_ action: HotkeyAction) {
        switch action {
        case .showCheet(let id):
            if picker.isVisible { picker.hide() }
            overlay.hotkeyPressed(cheetID: id, alongside: false)
        case .showCheetAlongside(let id):
            if picker.isVisible { picker.hide() }
            overlay.hotkeyPressed(cheetID: id, alongside: true)
        case .showPicker:
            picker.toggle()
        case .toggleLastCheet:
            overlay.toggleLast()
        case .toggleGhostMode:
            toggleGhostMode()
        }
    }

    private func handleRelease(_ action: HotkeyAction) {
        switch action {
        case .showCheet(let id), .showCheetAlongside(let id): overlay.hotkeyReleased(cheetID: id)
        default: break
        }
    }

    // MARK: - Commands

    func showPicker() {
        picker.show()
    }

    func toggleGhostMode() {
        model.settings.behavior.ghostMode.toggle()
        let on = model.settings.behavior.ghostMode
        if overlay.isVisible { overlay.showToast(on ? "Ghost mode on — clicks pass through" : "Ghost mode off") }
    }

    func openSettings(_ pane: SettingsPane? = nil) {
        windows.showSettings(pane)
    }

    func openImporter(_ request: ImportRequest = .blank) {
        windows.showImporter(request)
    }

    func editCheet(_ id: UUID) {
        overlay.hide()
        windows.showImporter(.edit(id))
    }

    /// "Import from URL" with element selection. Pass a URL to fetch it straight away.
    func openWebImport(_ url: URL? = nil) {
        windows.showWebImport(url: url, autoFetch: url != nil)
    }

    func openCheatographyBrowser(_ source: CheatographyCatalog.Source? = nil) {
        windows.showCheatographyBrowser(source)
    }

    func newCheetFromClipboard() {
        windows.showImporter(.clipboard)
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Cheet with Both Hands",
            .credits: NSAttributedString(
                string: "Cheets on a hotkey, for every app.\nData lives in ~/Library/Application Support/Cheet with Both Hands.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }

    func toggleLaunchAtLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
            if LoginItem.needsApproval {
                showAlert("Approve in System Settings",
                          "macOS needs you to allow Cheet with Both Hands under System Settings › General › Login Items.")
            }
        } catch {
            showAlert("Couldn't change the login item", error.localizedDescription)
        }
    }

    /// Resolves "3" (position) or a title fragment to a cheet.
    func cheet(matching token: String) -> Cheet? {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        if let number = Int(trimmed) {
            let index = number == 0 ? 9 : number - 1
            return model.cheets.indices.contains(index) ? model.cheets[index] : nil
        }
        let folded = trimmed.searchFolded
        return model.cheets.first { $0.title.searchFolded == folded }
            ?? model.cheets.first { $0.title.searchFolded.hasPrefix(folded) }
            ?? model.cheets.first { $0.title.searchFolded.contains(folded) }
    }

    // MARK: - Files

    static let importableTypes: [UTType] = [
        .plainText, .html, .commaSeparatedText, .tabSeparatedText, .json, .utf8PlainText,
        UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText,
    ]

    /// Bulk-imports files straight into the library (no review step).
    func importFiles() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.importableTypes
        panel.message = "Choose Markdown, HTML, CSV/TSV or JSON files to turn into cheets"
        guard panel.runModal() == .OK else { return }

        var failures: [String] = []
        var added = 0
        for url in panel.urls {
            do {
                let text = try FileReading.readText(url)
                let format = ImportFormat.from(fileExtension: url.pathExtension)
                let result = try CheetImporter.importCheet(text, options: ImportOptions(
                    format: format == .markdown ? .auto : format,
                    fallbackTitle: CheetImporter.title(fromFileName: url.lastPathComponent),
                    origin: url.path
                ))
                model.add(result.cheet)
                added += 1
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            showAlert("Imported \(added) of \(panel.urls.count) files", failures.joined(separator: "\n"))
        }
    }

    func exportMarkdown(_ cheet: Cheet) {
        save(data: Data(MarkdownExporter.markdown(for: cheet).utf8), suggestedName: "\(cheet.title).md", type: UTType(filenameExtension: "md") ?? .plainText)
    }

    func exportJSON(_ cheet: Cheet) {
        guard let data = try? LibraryStore.encodeCheet(cheet) else { return }
        save(data: data, suggestedName: "\(cheet.title).json", type: .json)
    }

    func exportLibrary() {
        guard let data = try? LibraryStore.encodeLibrary(Library(cheets: model.cheets, workspaces: model.workspaces)) else { return }
        save(data: data, suggestedName: "Cheets Library.json", type: .json)
    }

    func importLibrary() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try LibraryStore.decodeLibrary(from: Data(contentsOf: url))
            let existing = Set(model.cheets.map(\.id))
            var renamed: [UUID: UUID] = [:]
            for var cheet in incoming.cheets {
                if existing.contains(cheet.id) {
                    let fresh = UUID()
                    renamed[cheet.id] = fresh
                    cheet.id = fresh
                }
                model.add(cheet)
            }
            let known = Set(model.cheets.map(\.id))
            for var workspace in incoming.workspaces {
                workspace.id = UUID()
                workspace.hotkey = nil // don't steal combos on import
                workspace.windows = workspace.windows.map { var w = $0; w.cheetID = renamed[w.cheetID] ?? w.cheetID; return w }
                model.workspaces.append(workspace.pruned(keeping: known))
            }
            let added = incoming.cheets.count
            showAlert("Imported \(added) cheet\(added == 1 ? "" : "s")", "They've been added to the end of your library.")
        } catch {
            showAlert("Couldn't read that library", error.localizedDescription)
        }
    }

    private func save(data: Data, suggestedName: String, type: UTType) {
        NSApp.activate()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: "/", with: "-")
        panel.allowedContentTypes = [type]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            showAlert("Couldn't save the file", error.localizedDescription)
        }
    }

    func showAlert(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

enum FileReading {
    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8) { return text }
        var converted: NSString?
        let encoding = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil)
        if encoding != 0, let converted { return converted as String }
        if let latin = String(data: data, encoding: .isoLatin1) { return latin }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
