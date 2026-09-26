import AppKit
import CheetCore

/// NSMenuItem that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [.command], handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        keyEquivalentModifierMask = modifiers
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not supported") }

    @objc private func fire() { handler() }
}

/// The menu bar icon and its menu: every cheet (with its shortcut), plus app commands.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let controller: AppController

    /// Cheets beyond this count move into a "More Cheets" submenu.
    private let inlineLimit = 25

    init(controller: AppController) {
        self.controller = controller
        super.init()
        statusItem.button?.toolTip = "Cheet with Both Hands"
        refreshIcon()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    /// The menu bar button (for snapshots).
    var button: NSStatusBarButton? { statusItem.button }

    /// Shows the icon for the current icon scheme.
    func refreshIcon() {
        statusItem.button?.image = switch controller.model.settings.branding.iconScheme {
        case .classic: Self.makeIcon()
        case .cheeter: Mascot.makeHammerIcon()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        let model = controller.model
        let overlay = controller.overlay

        menu.addItem(NSMenuItem.sectionHeader(title: model.cheets.isEmpty ? "No Cheets Yet" : "Cheets"))

        func cheetItem(index: Int, cheet: Cheet) -> NSMenuItem {
            let title = "\(index + 1)   \(cheet.title)"
            let item = ActionMenuItem(title, key: "", modifiers: []) { [weak controller] in
                controller?.overlay.toggle(cheetID: cheet.id)
            }
            if let combo = model.combo(forCheet: cheet.id), let equivalent = combo.menuKeyEquivalent {
                item.keyEquivalent = equivalent.key
                item.keyEquivalentModifierMask = equivalent.modifiers
            }
            item.state = overlay.isVisible && overlay.state.cheetID == cheet.id ? .on : .off
            item.toolTip = "\(cheet.sections.count) sections · \(cheet.entryCount) entries"
            return item
        }

        for (index, cheet) in model.cheets.enumerated().prefix(inlineLimit) {
            menu.addItem(cheetItem(index: index, cheet: cheet))
        }
        if model.cheets.count > inlineLimit {
            let more = NSMenuItem(title: "More Cheets (\(model.cheets.count - inlineLimit))", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for (index, cheet) in model.cheets.enumerated().dropFirst(inlineLimit) {
                submenu.addItem(cheetItem(index: index, cheet: cheet))
            }
            more.submenu = submenu
            menu.addItem(more)
        }

        menu.addItem(.separator())

        let picker = ActionMenuItem("Cheet Picker…", modifiers: []) { [weak controller] in controller?.showPicker() }
        apply(model.hotkeyPlan.combo(for: .showPicker), to: picker)
        menu.addItem(picker)

        let last = ActionMenuItem("Toggle Last Cheet", modifiers: []) { [weak controller] in controller?.overlay.toggleLast() }
        apply(model.hotkeyPlan.combo(for: .toggleLastCheet), to: last)
        menu.addItem(last)

        if overlay.isVisible {
            menu.addItem(ActionMenuItem("Hide Overlay", modifiers: []) { [weak controller] in controller?.overlay.hide() })
        }

        let ghost = ActionMenuItem("Ghost Mode (Click-Through)", modifiers: []) { [weak controller] in controller?.toggleGhostMode() }
        ghost.state = model.settings.behavior.ghostMode ? .on : .off
        apply(model.hotkeyPlan.combo(for: .toggleGhostMode), to: ghost)
        menu.addItem(ghost)

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("New Cheet…", key: "n") { [weak controller] in controller?.openImporter() })
        menu.addItem(ActionMenuItem("New Cheet from Clipboard", modifiers: []) { [weak controller] in controller?.newCheetFromClipboard() })
        menu.addItem(ActionMenuItem("Import from URL…", modifiers: []) { [weak controller] in controller?.openWebImport() })
        menu.addItem(ActionMenuItem("Browse Cheatography…", modifiers: []) { [weak controller] in controller?.openCheatographyBrowser() })
        menu.addItem(ActionMenuItem("Import Files…", key: "o") { [weak controller] in controller?.importFiles() })
        menu.addItem(ActionMenuItem("Manage Cheets…", modifiers: []) { [weak controller] in controller?.openSettings(.cheets) })

        menu.addItem(.separator())
        let enabled = ActionMenuItem("Global Hotkeys Enabled", modifiers: []) { [weak controller] in
            controller?.model.settings.hotkeys.enabled.toggle()
        }
        enabled.state = model.settings.hotkeys.enabled ? .on : .off
        menu.addItem(enabled)

        let login = ActionMenuItem("Launch at Login", modifiers: []) { [weak controller] in controller?.toggleLaunchAtLogin() }
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(ActionMenuItem("Settings…", key: ",") { [weak controller] in controller?.openSettings() })

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("About Cheet with Both Hands", modifiers: []) { [weak controller] in controller?.showAbout() })
        menu.addItem(ActionMenuItem("Quit", key: "q") { NSApp.terminate(nil) })
    }

    private func apply(_ combo: KeyCombo?, to item: NSMenuItem) {
        guard let combo, let equivalent = combo.menuKeyEquivalent else { return }
        item.keyEquivalent = equivalent.key
        item.keyEquivalentModifierMask = equivalent.modifiers
    }

    /// Template icon: a little cheet with key/description rows.
    static func makeIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let card = NSBezierPath(roundedRect: NSRect(x: 2, y: 2.5, width: 14, height: 13), xRadius: 2.6, yRadius: 2.6)
            card.lineWidth = 1.4
            card.stroke()
            for (i, y) in [5.6, 8.6, 11.6].enumerated() {
                NSBezierPath(roundedRect: NSRect(x: 4.4, y: y, width: 3.2, height: 1.8), xRadius: 0.8, yRadius: 0.8).fill()
                let width = [6.0, 4.4, 5.4][i]
                NSBezierPath(roundedRect: NSRect(x: 8.6, y: y + 0.25, width: width, height: 1.3), xRadius: 0.65, yRadius: 0.65).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cheet with Both Hands"
        return image
    }
}
