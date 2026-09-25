import AppKit
import CheetCore
import SwiftUI

/// Borderless, non-activating floating panel: it can take keyboard focus for filtering without
/// stealing activation from the app you're working in.
final class OverlayPanel: NSPanel {
    var onCancel: (() -> Void)?
    /// Called while the user drags the resize grip.
    var onUserResize: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovable = true
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        minSize = NSSize(width: 360, height: 220)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Shows, hides, positions and animates the cheet overlay, and implements the
/// tap-to-toggle / hold-to-peek trigger behaviour.
@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    let model: AppModel
    let state = OverlayState()
    let editState = LayoutEditState()

    private let panel = OverlayPanel()
    private var hideGeneration = 0
    private var isAnimatingFrame = false
    /// Set when the user drags or resizes the overlay; only then is the frame remembered.
    private var userAdjustedFrame = false
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var toastTask: Task<Void, Never>?
    private var frameSaveTask: Task<Void, Never>?
    private var searchIndexes: [UUID: (updatedAt: Date, index: CheetSearchIndex)] = [:]

    /// The in-flight hotkey press, for hold-to-peek.
    private var activePress: (cheetID: UUID, time: Date, hidOnPress: Bool)?

    /// The cheet's outer scroll view (not the scroll views inside fixed-height cards).
    private weak var outerScrollView: NSScrollView?
    /// Where an in-flight keyboard scroll is heading, so key repeat accumulates smoothly.
    private var scrollTargetY: CGFloat?

    /// Layout-editing history for the current cheet.
    private var undoStack: [Cheet] = []
    private var redoStack: [Cheet] = []
    private var dragWatchTask: Task<Void, Never>?

    var isVisible: Bool { state.isVisible }
    var window: NSWindow { panel }

    init(model: AppModel) {
        self.model = model
        super.init()

        let root = OverlayRootView(model: model, state: state, controller: self)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.handleEscape() }
        panel.onUserResize = { [weak self] in self?.userAdjustedFrame = true }

        model.addSettingsObserver { [weak self] old, new in
            guard let self else { return }
            self.applyWindowProperties()
            if old.layout != new.layout { self.relayoutIfVisible() }
            if old.behavior.dismissOnOutsideClick != new.behavior.dismissOnOutsideClick, self.state.isVisible {
                self.installMonitors()
            }
        }
    }

    // MARK: - Hotkey trigger behaviour

    func hotkeyPressed(cheetID: UUID) {
        guard activePress?.cheetID != cheetID else { return } // ignore key repeat
        let sameCheetVisible = state.isVisible && state.cheetID == cheetID
        switch model.settings.behavior.trigger {
        case .toggle:
            sameCheetVisible ? hide() : show(cheetID: cheetID)
            activePress = (cheetID, Date(), sameCheetVisible)
        case .hold:
            show(cheetID: cheetID, focus: false)
            activePress = (cheetID, Date(), false)
        case .smart:
            if sameCheetVisible { hide() } else { show(cheetID: cheetID) }
            activePress = (cheetID, Date(), sameCheetVisible)
        }
    }

    func hotkeyReleased(cheetID: UUID) {
        guard let press = activePress, press.cheetID == cheetID else { return }
        activePress = nil
        let held = Date().timeIntervalSince(press.time)
        switch model.settings.behavior.trigger {
        case .toggle:
            break
        case .hold:
            if state.cheetID == cheetID { hide() }
        case .smart:
            // A long press was a peek: put it away on release. A tap leaves it pinned.
            if !press.hidOnPress, held >= model.settings.behavior.holdThreshold, state.cheetID == cheetID { hide() }
        }
    }

    func toggle(cheetID: UUID) {
        if state.isVisible && state.cheetID == cheetID { hide() } else { show(cheetID: cheetID) }
    }

    func toggleLast() {
        if state.isVisible { hide(); return }
        let id = model.cheet(id: model.viewState.lastCheetID)?.id ?? model.cheets.first?.id
        if let id { show(cheetID: id) } else { showEmpty() }
    }

    // MARK: - Show / hide

    func show(cheetID: UUID, focus: Bool? = nil) {
        guard model.cheet(id: cheetID) != nil else { return }
        let wasVisible = state.isVisible
        let previous = state.cheetID
        if previous != cheetID {
            state.query = ""
            state.showControls = false
            resetEditHistory()
            editState.selectedID = nil
        }
        state.cheetID = cheetID
        model.viewState.lastCheetID = cheetID
        present(wasVisible: wasVisible, cheetChanged: previous != cheetID, focus: focus)
    }

    /// Shows the overlay's empty state (no cheets in the library).
    func showEmpty() {
        state.cheetID = nil
        present(wasVisible: state.isVisible, cheetChanged: true, focus: true)
    }

    private func present(wasVisible: Bool, cheetChanged: Bool, focus: Bool?) {
        applyWindowProperties()
        let behavior = model.settings.behavior
        let takeFocus = (editState.isEditing || ((focus ?? behavior.takeFocus) && !behavior.ghostMode)) && !DebugSnapshots.isRequested

        if !wasVisible {
            hideGeneration += 1
            let target = targetFrame(for: state.cheetID)
            let opacity = model.appearance(for: state.cheetID).windowOpacity
            let fade = behavior.fadeDuration

            isAnimatingFrame = true
            panel.setFrame(fade > 0 ? target.offsetBy(dx: 0, dy: -10) : target, display: false)
            panel.alphaValue = fade > 0 ? 0 : opacity
            if takeFocus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
            state.isVisible = true
            installMonitors()

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = fade
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = opacity
                if fade > 0 { panel.animator().setFrame(target, display: true) }
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.isAnimatingFrame = false
                    self?.panel.invalidateShadow()
                }
            })
        } else {
            if cheetChanged, model.settings.layout.perCheetFrames, model.settings.layout.rememberFrame {
                setFrame(targetFrame(for: state.cheetID), animate: true)
            }
            if takeFocus, !panel.isKeyWindow { panel.makeKeyAndOrderFront(nil) }
            panel.invalidateShadow()
        }
        if takeFocus, !editState.isEditing { state.focusSearchRequest += 1 }
    }

    func hide(animated: Bool = true) {
        guard state.isVisible else { return }
        if editState.isEditing { endEditing() }
        state.isVisible = false
        state.showControls = false
        activePress = nil
        hideGeneration += 1
        let generation = hideGeneration
        removeMonitors()
        flushFrameSave()

        let fade = animated ? model.settings.behavior.fadeDuration : 0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fade
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.state.query = ""
            }
        })
    }

    // MARK: - Navigation & actions (used by the view and keyboard handling)

    func step(_ delta: Int) {
        guard !model.cheets.isEmpty else { return }
        let current = model.index(of: state.cheetID) ?? 0
        let next = (current + delta + model.cheets.count) % model.cheets.count
        show(cheetID: model.cheets[next].id)
    }

    func select(index: Int) {
        guard model.cheets.indices.contains(index) else { NSSound.beep(); return }
        show(cheetID: model.cheets[index].id)
    }

    func adjustFontSize(_ delta: Double) {
        var appearance = model.appearance(for: state.cheetID)
        let range = Appearance.fontSizeRange
        appearance.fontSize = delta == 0 ? Appearance().fontSize : min(range.upperBound, max(range.lowerBound, appearance.fontSize + delta))
        model.setAppearance(appearance, for: state.cheetID)
        showToast("Text size \(Int(appearance.fontSize)) pt")
    }

    func toggleSection(_ sectionID: UUID, in cheetID: UUID) {
        var viewState = model.viewState[cheet: cheetID]
        if viewState.collapsedSections.contains(sectionID) {
            viewState.collapsedSections.remove(sectionID)
        } else {
            viewState.collapsedSections.insert(sectionID)
        }
        model.viewState[cheet: cheetID] = viewState
    }

    func copy(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        let preview = trimmed.count > 42 ? String(trimmed.prefix(40)) + "…" : trimmed
        showToast("Copied  \(preview)")
    }

    func copyImage(_ source: String) {
        showToast(ImageStore.shared.copyToPasteboard(source) ? "Copied image" : "The image hasn't loaded yet")
    }

    func showToast(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        state.toast = Toast(text: message, actionTitle: actionTitle, action: action)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(action == nil ? 1.4 : 5))
            guard !Task.isCancelled else { return }
            self?.state.toast = nil
        }
    }

    func openPicker() { AppController.shared.showPicker() }
    func openSettings() { AppController.shared.openSettings() }
    func newCheet() { AppController.shared.openImporter() }
    func editCheet(_ id: UUID) { AppController.shared.editCheet(id) }

    /// Visible (non-hidden) sections, narrowed by the filter query.
    func filteredSections(for cheet: Cheet, query: String) -> [CheetSection] {
        let visible = cheet.visibleSections
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return visible }
        var visibleCheet = cheet
        visibleCheet.sections = visible
        let index: CheetSearchIndex
        if let cached = searchIndexes[cheet.id], cached.updatedAt == cheet.updatedAt, cached.index.cheet == visibleCheet {
            index = cached.index
        } else {
            index = CheetSearchIndex(cheet: visibleCheet)
            searchIndexes[cheet.id] = (cheet.updatedAt, index)
        }
        return index.filter(query)
    }

    /// Forget the remembered frame and snap back to the preset position.
    func resetFrame() {
        if model.settings.layout.perCheetFrames, let id = state.cheetID {
            model.viewState[cheet: id].frame = nil
        } else {
            model.viewState.globalFrame = nil
        }
        setFrame(targetFrame(for: state.cheetID), animate: true)
    }

    func relayoutIfVisible() {
        guard state.isVisible else { return }
        setFrame(targetFrame(for: state.cheetID), animate: true)
    }

    // MARK: - Window properties & geometry

    func applyWindowProperties() {
        let appearance = model.appearance(for: state.cheetID)
        let behavior = model.settings.behavior
        panel.appearance = appearance.nsAppearance
        panel.ignoresMouseEvents = behavior.ghostMode && !editState.isEditing
        panel.collectionBehavior = behavior.showOnAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            : [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        if state.isVisible, !isAnimatingFrame {
            panel.alphaValue = appearance.windowOpacity
        }
        panel.invalidateShadow()
    }

    private func screenForPresentation() -> NSScreen {
        switch model.settings.layout.screen {
        case .mouse:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        case .focused:
            return NSScreen.main ?? NSScreen.screens[0]
        case .primary:
            return NSScreen.screens.first ?? NSScreen.main!
        }
    }

    func targetFrame(for cheetID: UUID?) -> NSRect {
        let visible = screenForPresentation().visibleFrame
        let layout = model.settings.layout

        if layout.rememberFrame {
            let saved = layout.perCheetFrames ? cheetID.flatMap { model.viewState[cheet: $0].frame } : model.viewState.globalFrame
            if let saved {
                return clamp(saved.denormalized(in: visible), to: visible)
            }
        }

        let margin = CGFloat(layout.margin)
        let width = min(max(panel.minSize.width, visible.width * layout.widthFraction), visible.width - 2 * margin)
        let height = min(max(panel.minSize.height, visible.height * layout.heightFraction), visible.height - 2 * margin)
        let unit = layout.anchor.unitPosition
        let x = visible.minX + margin + (visible.width - 2 * margin - width) * unit.x
        let y = visible.minY + margin + (visible.height - 2 * margin - height) * unit.y
        return NSRect(x: x, y: y, width: width, height: height).integral
    }

    private func clamp(_ rect: NSRect, to container: NSRect) -> NSRect {
        var r = rect
        r.size.width = min(max(r.width, panel.minSize.width), container.width)
        r.size.height = min(max(r.height, panel.minSize.height), container.height)
        r.origin.x = min(max(r.minX, container.minX), container.maxX - r.width)
        r.origin.y = min(max(r.minY, container.minY), container.maxY - r.height)
        return r.integral
    }

    private func setFrame(_ frame: NSRect, animate: Bool) {
        isAnimatingFrame = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animate ? 0.2 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isAnimatingFrame = false
                self?.panel.invalidateShadow()
            }
        })
    }

    // MARK: - NSWindowDelegate (remember user moves/resizes)

    func windowWillMove(_ notification: Notification) { userAdjustedFrame = true }
    func windowWillStartLiveResize(_ notification: Notification) { userAdjustedFrame = true }
    func windowDidMove(_ notification: Notification) { scheduleFrameSave() }
    func windowDidResize(_ notification: Notification) {
        scheduleFrameSave()
        panel.invalidateShadow()
    }

    private func scheduleFrameSave() {
        guard userAdjustedFrame, !isAnimatingFrame, state.isVisible, model.settings.layout.rememberFrame else { return }
        frameSaveTask?.cancel()
        frameSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.saveFrame()
        }
    }

    private func flushFrameSave() {
        guard frameSaveTask != nil else { return }
        frameSaveTask?.cancel()
        frameSaveTask = nil
        saveFrame()
    }

    private func saveFrame() {
        frameSaveTask = nil
        guard userAdjustedFrame, model.settings.layout.rememberFrame, let screen = panel.screen else { return }
        userAdjustedFrame = false
        let normalized = NormalizedRect(rect: panel.frame, in: screen.visibleFrame)
        if model.settings.layout.perCheetFrames, let id = state.cheetID {
            model.viewState[cheet: id].frame = normalized
        } else {
            model.viewState.globalFrame = normalized
        }
    }

    // MARK: - Keyboard & mouse monitors

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
        if model.settings.behavior.dismissOnOutsideClick {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.editState.isEditing else { return }
                    self.hide()
                }
            }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        keyMonitor = nil
        outsideClickMonitor = nil
    }

    private func handleEscape() {
        if editState.isEditing {
            if editState.selectedID != nil { editState.selectedID = nil } else { endEditing() }
        } else if !state.query.isEmpty {
            state.query = ""
        } else {
            hide()
        }
    }

    // MARK: - Keyboard scrolling

    enum ScrollAmount: Equatable {
        case lines(Int)
        case pages(Int)
        case top
        case bottom
    }

    func attachScrollView(_ scrollView: NSScrollView) {
        outerScrollView = scrollView
        scrollTargetY = nil
    }

    /// ↑↓ scroll, ⌥↑↓ / Page Up·Down / Space page, ⌘↑↓ / Home·End jump to the ends.
    private func handleScrollKey(keyCode: UInt32, flags: NSEvent.ModifierFlags) -> Bool {
        let typing = panel.firstResponder is NSTextView
        // While renaming a card, leave the keys to the text field.
        if editState.isEditing && typing { return false }

        let amount: ScrollAmount?
        switch (keyCode, flags) {
        case (KeyCodes.downArrow, []): amount = .lines(1)
        case (KeyCodes.upArrow, []): amount = .lines(-1)
        case (KeyCodes.downArrow, .option), (KeyCodes.pageDown, []): amount = .pages(1)
        case (KeyCodes.upArrow, .option), (KeyCodes.pageUp, []): amount = .pages(-1)
        case (KeyCodes.downArrow, .command), (KeyCodes.end, []): amount = .bottom
        case (KeyCodes.upArrow, .command), (KeyCodes.home, []): amount = .top
        case (KeyCodes.space, []) where !typing: amount = .pages(1)
        case (KeyCodes.space, .shift) where !typing: amount = .pages(-1)
        default: amount = nil
        }
        guard let amount else { return false }
        scroll(amount)
        return true
    }

    func scroll(_ amount: ScrollAmount, animated: Bool = true) {
        guard let scrollView = outerScrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let down: CGFloat = document.isFlipped ? 1 : -1
        let current = scrollTargetY ?? clip.bounds.origin.y
        let visible = clip.bounds.height
        let line = max(36, CGFloat(model.appearance(for: state.cheetID).fontSize) * 3.2)

        var target: CGFloat
        switch amount {
        case .lines(let n): target = current + CGFloat(n) * line * down
        case .pages(let n): target = current + CGFloat(n) * max(visible - 56, visible * 0.8) * down
        case .top: target = -1_000_000 * down
        case .bottom: target = 1_000_000 * down
        }
        let origin = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: clip.bounds.origin.x, y: target), size: clip.bounds.size)).origin
        guard abs(origin.y - clip.bounds.origin.y) > 0.5 || scrollTargetY != nil else { return }
        scrollTargetY = origin.y

        let duration: TimeInterval
        switch amount {
        case .lines: duration = 0.12
        case .pages: duration = 0.22
        case .top, .bottom: duration = 0.3
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animated ? duration : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clip.animator().setBoundsOrigin(origin)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                scrollView.reflectScrolledClipView(clip)
                if self?.scrollTargetY == origin.y { self?.scrollTargetY = nil }
            }
        })
        scrollView.reflectScrolledClipView(clip)
    }

    /// Current scroll offset from the top (for tests/diagnostics).
    var scrollOffset: CGFloat {
        guard let scrollView = outerScrollView, let document = scrollView.documentView else { return 0 }
        let clip = scrollView.contentView
        return document.isFlipped ? clip.bounds.minY : document.frame.height - clip.bounds.maxY
    }

    /// Returns true when the event was handled (and should be swallowed).
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = UInt32(event.keyCode)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if keyCode == KeyCodes.escape && flags.isEmpty {
            handleEscape()
            return true
        }
        if handleScrollKey(keyCode: keyCode, flags: flags) { return true }
        if editState.isEditing, !(panel.firstResponder is NSTextView) {
            if flags.isEmpty, keyCode == KeyCodes.delete || keyCode == KeyCodes.forwardDelete, let id = editState.selectedID {
                deleteSection(id)
                return true
            }
            if flags.isEmpty, chars == "h", let id = editState.selectedID {
                toggleHidden(id)
                return true
            }
            if flags == .command, chars == "z" { undo(); return true }
            if flags == [.command, .shift], chars == "z" { redo(); return true }
            if flags == .command, keyCode == KeyCodes.returnKey { endEditing(); return true }
        }
        guard flags.contains(.command) else { return false }

        if flags == [.command, .option] {
            if keyCode == KeyCodes.leftArrow { step(-1); return true }
            if keyCode == KeyCodes.rightArrow { step(1); return true }
            if keyCode == KeyCodes.e { // ⌥⌘E edits the content (matched by key code since ⌥ changes the character)
                if let id = state.cheetID { editCheet(id) }
                return true
            }
        }
        guard flags == .command || flags == [.command, .shift] else { return false }

        switch chars {
        case "f":
            state.focusSearchRequest += 1
        case "w", "q", "h":
            hide() // never quit/hide the app from inside the overlay — just put it away
        case "[", "{":
            step(-1)
        case "]", "}":
            step(1)
        case "=", "+":
            adjustFontSize(1)
        case "-", "_":
            adjustFontSize(-1)
        case "0":
            adjustFontSize(0)
        case "p":
            openPicker()
        case ",":
            openSettings()
        case "e":
            toggleEditing()
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            select(index: Int(chars)! - 1)
        default:
            return false
        }
        return true
    }
}

// MARK: - Layout editing

extension OverlayController: LayoutEditing {
    private var currentCheet: Cheet? { model.cheet(id: state.cheetID) }

    func toggleEditing() {
        editState.isEditing ? endEditing() : beginEditing()
    }

    func beginEditing() {
        guard state.cheetID != nil else { return }
        state.query = ""
        state.showControls = false
        editState.isEditing = true
        editState.selectedID = nil
        applyWindowProperties()
        if !panel.isKeyWindow, !DebugSnapshots.isRequested { panel.makeKeyAndOrderFront(nil) }
    }

    func endEditing() {
        commitResize()
        editState.isEditing = false
        editState.selectedID = nil
        editState.draggingID = nil
        applyWindowProperties()
    }

    /// Opens a cheet straight into layout editing (from Settings).
    func editLayout(cheetID: UUID) {
        show(cheetID: cheetID, focus: true)
        beginEditing()
    }

    private func resetEditHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        syncUndoFlags()
    }

    private func syncUndoFlags() {
        editState.canUndo = !undoStack.isEmpty
        editState.canRedo = !redoStack.isEmpty
    }

    func beginChange() {
        guard let cheet = currentCheet else { return }
        undoStack.append(cheet)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        syncUndoFlags()
    }

    /// Drops the most recent snapshot if nothing actually changed since `beginChange()`.
    func endChange() {
        guard let last = undoStack.last, let cheet = currentCheet else { return }
        if last.sections == cheet.sections && last.title == cheet.title {
            undoStack.removeLast()
            syncUndoFlags()
        }
    }

    func undo() {
        guard let previous = undoStack.popLast(), let current = currentCheet else { NSSound.beep(); return }
        redoStack.append(current)
        withAnimation(.snappy(duration: 0.25)) { model.update(previous) }
        syncUndoFlags()
    }

    func redo() {
        guard let next = redoStack.popLast(), let current = currentCheet else { NSSound.beep(); return }
        undoStack.append(current)
        withAnimation(.snappy(duration: 0.25)) { model.update(next) }
        syncUndoFlags()
    }

    private func mutateCheet(undoable: Bool = true, animated: Bool = true, _ change: (inout Cheet) -> Void) {
        guard var cheet = currentCheet else { return }
        if undoable { beginChange() }
        change(&cheet)
        if animated {
            withAnimation(.snappy(duration: 0.25)) { model.update(cheet) }
        } else {
            model.update(cheet)
        }
    }

    private func mutateSection(_ id: UUID, undoable: Bool = true, animated: Bool = true, _ change: (inout CheetSection) -> Void) {
        mutateCheet(undoable: undoable, animated: animated) { cheet in
            guard let index = cheet.sections.firstIndex(where: { $0.id == id }) else { return }
            change(&cheet.sections[index])
        }
    }

    func select(_ id: UUID?) {
        editState.selectedID = id
    }

    func toggleHidden(_ id: UUID) {
        mutateSection(id) { $0.layout.isHidden.toggle() }
    }

    func deleteSection(_ id: UUID) {
        guard let title = currentCheet?.sections.first(where: { $0.id == id })?.title else { return }
        mutateCheet { $0.sections.removeAll { $0.id == id } }
        if editState.selectedID == id { editState.selectedID = nil }
        let name = title.isEmpty ? "untitled card" : "“\(InlineMarkdown.plainText(title))”"
        showToast("Deleted \(name)", actionTitle: "Undo") { [weak self] in self?.undo() }
    }

    func renameSection(_ id: UUID, to title: String) {
        mutateSection(id, animated: false) { $0.title = title }
    }

    func setLiveResize(_ live: LiveResize) {
        editState.liveResize = live
    }

    func commitResize() {
        guard let live = editState.liveResize else { return }
        editState.liveResize = nil
        mutateSection(live.id, undoable: false, animated: false) { section in
            section.layout.width = live.width
            section.layout.height = live.height
        }
    }

    func resetSize(_ id: UUID, width: Bool, height: Bool) {
        mutateSection(id) { section in
            if width { section.layout.width = .auto }
            if height { section.layout.height = nil }
        }
    }

    func cardStyle(for id: UUID) -> CardStyle {
        currentCheet?.sections.first { $0.id == id }?.layout.style ?? CardStyle()
    }

    func setCardStyle(_ style: CardStyle, for id: UUID) {
        mutateSection(id, undoable: false, animated: false) { $0.layout.style = style }
    }

    func applyStyleToAll(_ style: CardStyle) {
        mutateCheet(undoable: false) { cheet in
            for index in cheet.sections.indices { cheet.sections[index].layout.style = style }
        }
        showToast("Style applied to every card")
    }

    func resetCard(_ id: UUID) {
        mutateSection(id) { section in
            let hidden = section.layout.isHidden
            section.layout = SectionLayout()
            section.layout.isHidden = hidden
        }
    }

    func resetLayout(sizes: Bool, styles: Bool, visibility: Bool) {
        mutateCheet { cheet in
            for index in cheet.sections.indices {
                if sizes {
                    cheet.sections[index].layout.width = .auto
                    cheet.sections[index].layout.height = nil
                }
                if styles { cheet.sections[index].layout.style = CardStyle() }
                if visibility { cheet.sections[index].layout.isHidden = false }
            }
        }
    }

    func beginDrag(_ id: UUID) {
        beginChange()
        editState.draggingID = id
        editState.selectedID = id
        // SwiftUI doesn't report cancelled drags, so watch the mouse button to clear the drag state.
        dragWatchTask?.cancel()
        dragWatchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            while !Task.isCancelled, NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard let self, !Task.isCancelled else { return }
            if self.editState.draggingID != nil {
                self.editState.draggingID = nil
                self.endChange()
            }
        }
    }

    func moveSection(_ id: UUID, onto target: UUID) {
        mutateCheet(undoable: false, animated: false) { cheet in
            guard let from = cheet.sections.firstIndex(where: { $0.id == id }),
                  let to = cheet.sections.firstIndex(where: { $0.id == target }), from != to else { return }
            cheet.sections.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func moveSection(_ id: UUID, to position: MovePosition) {
        mutateCheet { cheet in
            guard let from = cheet.sections.firstIndex(where: { $0.id == id }) else { return }
            let section = cheet.sections.remove(at: from)
            let destination: Int
            switch position {
            case .start: destination = 0
            case .earlier: destination = max(0, from - 1)
            case .later: destination = min(cheet.sections.count, from + 1)
            case .end: destination = cheet.sections.count
            }
            cheet.sections.insert(section, at: destination)
        }
    }
}
