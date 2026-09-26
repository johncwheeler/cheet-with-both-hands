import AppKit
import CheetCore
import Observation
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, hotkeys, appearance, layout, cheets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .hotkeys: "Hotkeys"
        case .appearance: "Appearance"
        case .layout: "Position & Size"
        case .cheets: "Cheets"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .hotkeys: "command"
        case .appearance: "paintpalette"
        case .layout: "rectangle.inset.filled.and.person.filled"
        case .cheets: "list.bullet.rectangle"
        }
    }
}

@MainActor @Observable
final class SettingsNavigation {
    var pane: SettingsPane = .general
    var selectedCheetID: UUID?
}

/// Owns the Settings and Import windows. While either is open the app becomes a regular app
/// (Dock icon, ⌘-Tab), and returns to a menu-bar-only app when they close.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    let model: AppModel
    let navigation = SettingsNavigation()

    private(set) var settingsWindow: NSWindow?
    private(set) var importerWindow: NSWindow?
    private(set) var webImportWindow: NSWindow?
    private(set) var browserWindow: NSWindow?
    private(set) var namingWindow: NSWindow?
    private(set) var browserModel: CheatographyBrowserModel?
    private(set) var webImportModel: WebImportModel?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func showSettings(_ pane: SettingsPane? = nil) {
        if let pane { navigation.pane = pane }
        if navigation.selectedCheetID == nil { navigation.selectedCheetID = model.cheets.first?.id }
        let window = settingsWindow ?? makeWindow(
            title: "Cheet with Both Hands",
            size: NSSize(width: 900, height: 640),
            autosave: "CWBHSettingsWindow",
            content: SettingsView(model: model, navigation: navigation)
        )
        settingsWindow = window
        present(window)
    }

    func showCheetInSettings(_ id: UUID) {
        navigation.selectedCheetID = id
        showSettings(.cheets)
    }

    func showImporter(_ request: ImportRequest) {
        let importModel = ImportModel(appModel: model, request: request)
        let title = importModel.isEditing ? "Edit Cheet" : "New Cheet"
        let view = ImportView(importModel: importModel) { [weak self] in
            self?.importerWindow?.performClose(nil)
        }
        if let window = importerWindow {
            window.contentViewController = hostingController(for: view)
            window.title = title
            present(window)
        } else {
            let window = makeWindow(title: title, size: NSSize(width: 1080, height: 700), autosave: "CWBHImportWindow", content: view)
            importerWindow = window
            present(window)
        }
    }

    /// The "Import from URL" element picker. Reuses the open window, swapping in the new page.
    func showWebImport(url: URL?, autoFetch: Bool) {
        let importModel = WebImportModel(appModel: model, url: url)
        webImportModel = importModel
        let view = WebImportView(model: importModel) { [weak self] in
            self?.webImportWindow?.performClose(nil)
        }
        if let window = webImportWindow {
            window.contentViewController = hostingController(for: view)
            present(window)
        } else {
            let window = makeWindow(title: "Import from URL", size: NSSize(width: 1120, height: 720), autosave: "CWBHWebImportWindow", content: view)
            webImportWindow = window
            present(window)
        }
        if autoFetch, url != nil {
            Task { await importModel.fetch() }
        }
    }

    func showCheatographyBrowser(_ source: CheatographyCatalog.Source? = nil) {
        let browser = browserModel ?? CheatographyBrowserModel(appModel: model)
        browserModel = browser
        if browserWindow == nil {
            browserWindow = makeWindow(title: "Browse Cheatography", size: NSSize(width: 1040, height: 720), autosave: "CWBHBrowserWindow",
                                       content: CheatographyBrowserView(model: browser))
        }
        present(browserWindow!)
        if let source {
            Task { await browser.load(source) }
        } else if browser.items.isEmpty, !browser.isLoading {
            Task { await browser.load(browser.source) }
        }
    }

    func showWorkspaceNaming(suggestedName: String, existingNames: [String], onSave: @escaping (String) -> Void) {
        namingWindow?.close()
        let view = WorkspaceNamingView(
            existingNames: existingNames,
            onSave: { [weak self] name in
                self?.namingWindow?.close()
                onSave(name)
            },
            onCancel: { [weak self] in self?.namingWindow?.close() },
            name: suggestedName
        )
        let window = makeWindow(title: "Save Workspace", size: NSSize(width: 380, height: 170), autosave: "CWBHWorkspaceNaming", content: view)
        window.styleMask.remove([.resizable, .miniaturizable])
        namingWindow = window
        present(window)
    }

    private var managedWindows: [NSWindow?] { [settingsWindow, importerWindow, webImportWindow, browserWindow, namingWindow] }

    private func hostingController<V: View>(for view: V) -> NSHostingController<V> {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.minSize]
        return hosting
    }

    private func makeWindow<V: View>(title: String, size: NSSize, autosave: String, content: V) -> NSWindow {
        let window = NSWindow(contentViewController: hostingController(for: content))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName(autosave)
        return window
    }

    private func present(_ window: NSWindow) {
        if DebugSnapshots.isRequested {
            window.orderFrontRegardless() // never steal focus during snapshot runs
            return
        }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let stillOpen = self.managedWindows.contains { window in
                guard let window, window !== closing else { return false }
                return window.isVisible
            }
            if !stillOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
