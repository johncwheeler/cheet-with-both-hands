import AppKit
import CheetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        let controller = AppController()
        AppController.shared = controller
        controller.launch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppController.shared?.model.flushSaves()
    }

    /// Re-launching the app (e.g. double-clicking it in Finder) opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppController.shared?.openSettings() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                AppController.shared?.openImporter(.file(url))
            } else {
                URLCommands.handle(url)
            }
        }
    }
}

/// `cheetwithbothhands://show/2`, `…/toggle/git`, `…/picker`, `…/hide`, `…/import`, `…/settings`,
/// `…/import-url?url=…`, `…/browse?q=…`.
enum URLCommands {
    @MainActor
    static func handle(_ url: URL) {
        guard let controller = AppController.shared else { return }
        let command = (url.host ?? "").lowercased()
        let argument = url.pathComponents.dropFirst().joined(separator: "/").removingPercentEncoding
            ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        let target = argument.flatMap { $0.isEmpty ? nil : controller.cheet(matching: $0) }

        switch command {
        case "show", "open":
            if let target { controller.overlay.show(cheetID: target.id) } else { controller.overlay.toggleLast() }
        case "toggle":
            if let target { controller.overlay.toggle(cheetID: target.id) } else { controller.overlay.toggleLast() }
        case "hide":
            controller.overlay.hide()
        case "picker":
            controller.showPicker()
        case "import", "new":
            controller.newCheetFromClipboard()
        case "import-url", "url":
            // cheetwithbothhands://import-url?url=<encoded>  (what the browser bookmarklet sends)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value
            controller.openWebImport((query ?? argument).flatMap(WebFetcher.normalizedURL))
        case "browse", "cheatography":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
            controller.openCheatographyBrowser(query.map { .search($0) })
        case "settings", "preferences":
            controller.openSettings()
        case "ghost":
            controller.toggleGhostMode()
        default:
            NSSound.beep()
        }
    }
}

enum MainMenu {
    /// Accessory apps still need a main menu so ⌘C/⌘V/⌘A/⌘Z work in text fields.
    @MainActor
    static func install() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Cheet with Both Hands")
        appMenu.addItem(ActionMenuItem("About Cheet with Both Hands", modifiers: []) { AppController.shared?.showAbout() })
        appMenu.addItem(.separator())
        appMenu.addItem(ActionMenuItem("Settings…", key: ",") { AppController.shared?.openSettings() })
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Cheet with Both Hands", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Cheet with Both Hands", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(ActionMenuItem("New Cheet…", key: "n") { AppController.shared?.openImporter() })
        fileMenu.addItem(ActionMenuItem("New Cheet from Clipboard", key: "n", modifiers: [.command, .shift]) { AppController.shared?.newCheetFromClipboard() })
        fileMenu.addItem(ActionMenuItem("Import from URL…", key: "u", modifiers: [.command, .shift]) { AppController.shared?.openWebImport() })
        fileMenu.addItem(ActionMenuItem("Browse Cheatography…", key: "b", modifiers: [.command, .shift]) { AppController.shared?.openCheatographyBrowser() })
        fileMenu.addItem(ActionMenuItem("Import Files…", key: "o") { AppController.shared?.importFiles() })
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pasteMatch = editMenu.addItem(withTitle: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        pasteMatch.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f").tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }
}
