import AppKit
import CheetCore
import SwiftUI

/// Developer aid: renders the app's own windows to PNGs and quits. Nothing takes keyboard focus.
///   CWBH_SNAPSHOT_DIR=/tmp/shots CWBH_DATA_DIR=/tmp/data "…/Contents/MacOS/CheetWithBothHands"
@MainActor
enum DebugSnapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["CWBH_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static var isRequested: Bool { directory != nil }

    static func run(_ controller: AppController) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        Task { @MainActor in
            func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
            @MainActor func shot(_ window: NSWindow?, _ name: String) { capture(window, to: directory.appendingPathComponent("\(name).png")) }

            await pause(0.8)
            let overlay = controller.overlay
            for (index, cheet) in controller.model.cheets.enumerated() {
                overlay.show(cheetID: cheet.id, focus: false)
                await pause(0.7)
                shot(overlay.window, "overlay-\(index + 1)")
                if index >= 1 { break }
            }
            if controller.model.cheets.count > 1 {
                overlay.show(cheetID: controller.model.cheets[1].id, focus: false)
                overlay.state.query = "screen"
                await pause(0.6)
                shot(overlay.window, "overlay-filtered")
                overlay.state.query = ""
            }
            // Keyboard scrolling, driven through the real key-event path.
            if let first = controller.model.cheets.first {
                overlay.show(cheetID: first.id, focus: false)
                await pause(0.5)
                overlay.window.setFrame(NSRect(x: 160, y: 160, width: 820, height: 380), display: true)
                await pause(0.5)
                @MainActor func press(_ code: UInt32, _ function: Int, _ modifiers: NSEvent.ModifierFlags = []) async {
                    let chars = UnicodeScalar(UInt32(function)).map { String(Character($0)) } ?? ""
                    if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers.union([.function, .numericPad]),
                                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: overlay.window.windowNumber,
                                                    context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                                    isARepeat: false, keyCode: UInt16(code)) {
                        NSApp.postEvent(event, atStart: false)
                    }
                    await pause(0.5)
                }
                var log = ["start \(Int(overlay.scrollOffset))"]
                await press(KeyCodes.downArrow, NSDownArrowFunctionKey); log.append("↓ \(Int(overlay.scrollOffset))")
                await press(KeyCodes.downArrow, NSDownArrowFunctionKey); log.append("↓ \(Int(overlay.scrollOffset))")
                await press(KeyCodes.pageDown, NSPageDownFunctionKey); log.append("PgDn \(Int(overlay.scrollOffset))")
                await press(KeyCodes.downArrow, NSDownArrowFunctionKey, .command); log.append("⌘↓ \(Int(overlay.scrollOffset))")
                overlay.outerScroller?.enclosingScrollView?.flashScrollers() // overlay scrollers hide when idle
                await pause(0.15)
                shot(overlay.window, "overlay-scrolled-bottom")
                await press(KeyCodes.upArrow, NSUpArrowFunctionKey, .option); log.append("⌥↑ \(Int(overlay.scrollOffset))")
                await press(KeyCodes.upArrow, NSUpArrowFunctionKey); log.append("↑ \(Int(overlay.scrollOffset))")
                await press(KeyCodes.upArrow, NSUpArrowFunctionKey, .command); log.append("⌘↑ \(Int(overlay.scrollOffset))")
                print("keyboard scroll: " + log.joined(separator: " → "))
                print("outer scroller: \(overlay.outerScroller.map { String(describing: type(of: $0)) } ?? "none")")

                // ⇧→ / ⇧← step through the cheets.
                @MainActor func position() -> String { controller.model.index(of: overlay.state.cheetID).map { "\($0 + 1)" } ?? "-" }
                var steps = ["start \(position())"]
                await press(KeyCodes.rightArrow, NSRightArrowFunctionKey, .shift); steps.append("⇧→ \(position())")
                await press(KeyCodes.leftArrow, NSLeftArrowFunctionKey, .shift); steps.append("⇧← \(position())")
                await press(KeyCodes.leftArrow, NSLeftArrowFunctionKey, .shift); steps.append("⇧← \(position())")
                print("cheet stepping: " + steps.joined(separator: " → "))
                print("outer scroller after switching: \(overlay.outerScroller.map { String(describing: type(of: $0)) } ?? "none")")
                overlay.hide(animated: false)
                await pause(0.3)
            }

            if controller.model.cheets.count > 1, var cheet = controller.model.cheets.dropFirst().first, cheet.sections.count >= 5 {
                cheet.sections[0].layout.width = .columns(2)
                cheet.sections[0].layout.style.fill = .gradient
                cheet.sections[0].layout.style.effect = .glow
                cheet.sections[0].layout.style.fontSize = 15
                cheet.sections[1].layout.style.fill = .solid
                cheet.sections[1].layout.style.fillColor = RGBAColor(r: 0.9, g: 0.55, b: 0.2)
                cheet.sections[1].layout.style.titleColor = RGBAColor(r: 1, g: 0.85, b: 0.55)
                cheet.sections[2].layout.height = 150
                cheet.sections[2].layout.style.effect = .outline
                cheet.sections[3].layout.isHidden = true
                cheet.sections[4].layout.width = .fraction(0.5)
                cheet.sections[4].layout.style.fill = .frosted
                controller.model.update(cheet)
                overlay.show(cheetID: cheet.id, focus: false)
                await pause(0.6)
                shot(overlay.window, "overlay-custom")
                overlay.beginEditing()
                overlay.select(cheet.sections[2].id)
                await pause(0.6)
                shot(overlay.window, "overlay-editing")
                overlay.setLiveResize(LiveResize(id: cheet.sections[2].id, width: .columns(2), height: 220))
                await pause(0.6)
                shot(overlay.window, "overlay-resizing")
                overlay.commitResize()
                overlay.endEditing()
            }
            overlay.hide(animated: false)

            var sampleStyle = CardStyle()
            sampleStyle.fontSize = 15
            sampleStyle.titleColor = RGBAColor(r: 1, g: 0.8, b: 0.5)
            sampleStyle.fill = .gradient
            sampleStyle.effect = .glow
            let editorHost = NSHostingView(rootView: CardStyleEditor(
                title: "System", baseFontSize: 13, accent: controller.model.settings.appearance.accent,
                style: .constant(sampleStyle), onApplyToAll: {}
            ).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
            let editorWindow = NSWindow(contentRect: NSRect(origin: .zero, size: editorHost.fittingSize),
                                        styleMask: [.borderless], backing: .buffered, defer: false)
            editorWindow.appearance = NSAppearance(named: .darkAqua)
            editorWindow.contentView = editorHost
            editorWindow.orderFrontRegardless()
            await pause(0.5)
            shot(editorWindow, "card-style-editor")
            editorWindow.orderOut(nil)

            capture(controller.statusMenu.button?.image, to: directory.appendingPathComponent("menu-bar-icon.png"))
            if controller.model.settings.branding.iconScheme == .cheeter, let splash = SplashController.show(Mascot.character) {
                await pause(1.0)
                shot(splash.window, "splash")
                splash.markReady()
            }

            controller.picker.show(focus: false)
            await pause(0.6)
            shot(controller.picker.window, "picker")
            controller.picker.hide()

            for pane in SettingsPane.allCases {
                controller.openSettings(pane)
                await pause(0.8)
                shot(controller.windows.settingsWindow, "settings-\(pane.rawValue)")
            }
            controller.windows.settingsWindow?.close()

            let sample = """
            Category,Shortcut,Action
            Navigation,Ctrl+G,Go to line
            Navigation,Ctrl+P,"Quick open, fuzzy"
            Editing,Ctrl+Shift+K,Delete line
            Editing,Alt+Up,Move line up
            """
            controller.openImporter(.text(sample))
            await pause(1.0)
            shot(controller.windows.importerWindow, "importer")

            // Import from URL + Cheatography browser, against the live site.
            if ProcessInfo.processInfo.environment["CWBH_SNAPSHOT_WEB"] == "1" {
                @MainActor func waitFor(_ condition: () -> Bool, timeout: Double = 20) async {
                    let deadline = Date().addingTimeInterval(timeout)
                    while !condition(), Date() < deadline { await pause(0.25) }
                }
                controller.openWebImport(URL(string: "https://cheatography.com/davechild/cheat-sheets/regular-expressions/"))
                await waitFor { controller.windows.webImportModel?.document != nil }
                await pause(0.8)
                shot(controller.windows.webImportWindow, "web-import")
                if let web = controller.windows.webImportModel, let doc = web.document, doc.sections.count > 3 {
                    print("web import: \(doc.title ?? "-") \(doc.attribution ?? "-") \(web.selectedCount)/\(web.totalCount) elements")
                    web.toggle(section: doc.sections[2])
                    web.toggle(block: 1, in: doc.sections[4])
                    await pause(0.6)
                    shot(controller.windows.webImportWindow, "web-import-deselected")
                    print("after deselecting: \(web.selectedCount)/\(web.totalCount), preview sections \(web.previewCheet?.sections.count ?? 0)")
                }
                controller.windows.webImportWindow?.close()

                controller.openCheatographyBrowser(.feed(.popular))
                await waitFor { !(controller.windows.browserModel?.items.isEmpty ?? true) }
                await pause(1.5) // thumbnails
                shot(controller.windows.browserWindow, "browser-popular")
                if let browser = controller.windows.browserModel {
                    print("browser popular: \(browser.items.count) items, tags \(browser.popularTags.count)")
                    await browser.load(.category(.programming))
                    await pause(1.5)
                    shot(controller.windows.browserWindow, "browser-programming")
                    print("browser programming: \(browser.items.count) items, next \(browser.nextPageURL?.absoluteString ?? "nil"), groups \(browser.tagGroups.count)")
                    for item in browser.items.dropFirst(1).prefix(2) { browser.toggleChecked(item) }
                    let before = controller.model.cheets.count
                    await browser.importChecked()
                    print("bulk import: \(browser.statusMessage ?? "-") library \(before) → \(controller.model.cheets.count)")
                    for cheet in controller.model.cheets.suffix(2) {
                        print("   \(cheet.title): \(cheet.sections.count) sections, \(cheet.entryCount) entries, credit \(cheet.source?.attribution ?? "-")")
                    }
                    await pause(0.6)
                    shot(controller.windows.browserWindow, "browser-after-import")
                }
                controller.windows.browserWindow?.close()
            }

            // Formulas and images from real pages, rendered in the overlay.
            if ProcessInfo.processInfo.environment["CWBH_SNAPSHOT_MATH"] == "1" {
                @MainActor func waitFor(_ condition: () -> Bool, timeout: Double = 25) async {
                    let deadline = Date().addingTimeInterval(timeout)
                    while !condition(), Date() < deadline { await pause(0.25) }
                }
                let pages = [
                    ("math-calculus", "https://cheatography.com/crossant/cheat-sheets/calculus-ii/"),
                    ("math-wikipedia", "https://en.wikipedia.org/wiki/Quadratic_formula"),
                ]
                for (name, address) in pages {
                    controller.openWebImport(URL(string: address))
                    await waitFor { controller.windows.webImportModel?.document != nil }
                    await pause(0.5)
                    shot(controller.windows.webImportWindow, "\(name)-picker")
                    guard let web = controller.windows.webImportModel, let id = web.commit() else { continue }
                    controller.windows.webImportWindow?.close()
                    let sources = controller.model.cheet(id: id).map(ImageStore.sources(in:)) ?? []
                    await waitFor({ sources.allSatisfy { ImageStore.shared.cached($0) != nil } }, timeout: 20)
                    overlay.show(cheetID: id, focus: false)
                    await pause(1.2)
                    shot(overlay.window, name)
                    print("\(name): \(controller.model.cheet(id: id)?.sections.count ?? 0) sections, \(sources.count) images")
                    overlay.hide(animated: false)
                    await pause(0.3)
                }
            }

            print("hotkey bindings: \(controller.model.hotkeyPlan.bindings.map { $0.combo.displayString })")
            print("hotkey failures: \(controller.model.hotkeyFailures.map(\.displayString))")
            print("snapshots written to \(directory.path)")
            NSApp.terminate(nil)
        }
    }

    /// Renders an icon at 4× on white (template images don't draw when their window is captured offscreen).
    static func capture(_ image: NSImage?, to url: URL) {
        guard let image else { return }
        let size = NSSize(width: image.size.width * 4, height: image.size.height * 4)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    static func capture(_ window: NSWindow?, to url: URL) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
