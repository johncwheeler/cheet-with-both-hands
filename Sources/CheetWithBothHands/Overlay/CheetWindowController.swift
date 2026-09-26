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
        minSize = Self.minimumSize
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    static let minimumSize = NSSize(width: 360, height: 220)
    /// Stashed windows don't take keyboard focus.
    var acceptsKey = true
    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    /// AppKit keeps windows below the menu bar; stashing slides one past the top edge on purpose.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        acceptsKey ? super.constrainFrameRect(frameRect, to: screen) : frameRect
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// One cheet window: shows, positions and animates it, and handles its keyboard, scrolling and
/// layout editing. `CheetWindowManager` decides which windows exist.
@MainActor
final class CheetWindowController: NSObject, NSWindowDelegate {
    let model: AppModel
    unowned let manager: CheetWindowManager
    let state = OverlayState()
    let editState = LayoutEditState()

    private let panel = OverlayPanel()
    private var hideGeneration = 0
    private var isAnimatingFrame = false
    /// Set when the user drags or resizes the overlay; only then is the frame remembered.
    private var userAdjustedFrame = false
    private var keyMonitor: Any?
    private var toastTask: Task<Void, Never>?
    private var frameSaveTask: Task<Void, Never>?
    private var searchIndexes: [UUID: (updatedAt: Date, index: CheetSearchIndex)] = [:]

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

    init(model: AppModel, manager: CheetWindowManager) {
        self.model = model
        self.manager = manager
        super.init()

        let root = OverlayRootView(model: model, state: state, controller: self)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.handleEscape() }
        panel.onUserResize = { [weak self] in self?.userAdjustedFrame = true }

    }

    // MARK: - Showing, switching and closing

    var cheetID: UUID? { state.cheetID }
    /// Where the window sits when it isn't stashed.
    private(set) var homeFrame: NSRect?
    var isStashed: Bool { homeFrame != nil }
    /// The window's frame, or its home frame while stashed (for tiling, workspaces and hide).
    var frame: NSRect { homeFrame ?? panel.frame }

    func stash(to stashed: NSRect) {
        guard !isStashed else { return }
        if editState.isEditing { endEditing() }
        homeFrame = panel.frame
        state.isStashed = true
        panel.acceptsKey = false
        if panel.isKeyWindow { panel.resignKey() }
        setFrame(stashed, animate: true, remember: false)
    }

    func unstash(to home: NSRect) {
        guard isStashed else { return }
        homeFrame = nil
        state.isStashed = false
        panel.acceptsKey = true
        setFrame(home, animate: true, remember: false)
    }

    /// Loads a cheet into this window, resetting per-cheet state when it changes.
    private func load(_ cheetID: UUID?) {
        guard state.cheetID != cheetID || cheetID == nil else { return }
        state.query = ""
        state.showControls = false
        resetEditHistory()
        editState.selectedID = nil
        state.cheetID = cheetID
        if let cheetID { model.viewState.lastCheetID = cheetID }
    }

    /// Shows the window for the first time with `cheetID` (nil = the empty-library state) at `frame`.
    func open(cheetID: UUID?, at frame: NSRect, focus: Bool?) {
        load(cheetID)
        applyWindowProperties()
        let behavior = model.settings.behavior
        let takeFocus = (focus ?? behavior.takeFocus) && !behavior.ghostMode && !DebugSnapshots.isRequested
        hideGeneration += 1
        let opacity = model.appearance(for: state.cheetID).windowOpacity
        let fade = behavior.fadeDuration
        isAnimatingFrame = true
        panel.setFrame(fade > 0 ? frame.offsetBy(dx: 0, dy: -10) : frame, display: false)
        panel.alphaValue = fade > 0 ? 0 : opacity
        if takeFocus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        state.isVisible = true
        installMonitors()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fade
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = opacity
            if fade > 0 { panel.animator().setFrame(frame, display: true) }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isAnimatingFrame = false
                self?.panel.invalidateShadow()
            }
        })
        if takeFocus { state.focusSearchRequest += 1 }
    }

    /// Swaps this window's cheet in place (header menu, ⌘[ ], ⇧←/⇧→, ⌘1–9).
    func switchTo(cheetID: UUID) {
        guard model.cheet(id: cheetID) != nil, cheetID != state.cheetID else { return }
        if let owner = manager.window(showing: cheetID), owner !== self {
            manager.show(cheetID: cheetID) // already open elsewhere: bring that window forward
            return
        }
        load(cheetID)
        applyWindowProperties()
        let layout = model.settings.layout
        if layout.perCheetFrames, layout.rememberFrame {
            setFrame(manager.presetFrame(for: cheetID), animate: true, remember: false)
        }
    }

    /// Brings the window forward, optionally taking keyboard focus for filtering.
    func focus(_ takeFocus: Bool) {
        let behavior = model.settings.behavior
        if takeFocus, !behavior.ghostMode, !DebugSnapshots.isRequested {
            panel.makeKeyAndOrderFront(nil)
            if !editState.isEditing { state.focusSearchRequest += 1 }
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Fades the window out and closes it. The manager forgets it straight away.
    func close(animated: Bool = true) {
        guard state.isVisible else { return }
        if editState.isEditing { endEditing() }
        state.isVisible = false
        state.showControls = false
        hideGeneration += 1
        let generation = hideGeneration
        removeMonitors()
        flushFrameSave()
        manager.windowWillClose(self)
        let fade = animated ? model.settings.behavior.fadeDuration : 0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fade
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.manager.windowDidFinishClosing(self)
            }
        })
    }

    // MARK: - Navigation & actions (used by the view and keyboard handling)

    func step(_ delta: Int) {
        if let next = manager.neighbour(of: state.cheetID, delta: delta, for: self) { switchTo(cheetID: next) }
    }

    func select(index: Int) {
        guard model.cheets.indices.contains(index) else { NSSound.beep(); return }
        switchTo(cheetID: model.cheets[index].id)
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
        setFrame(manager.presetFrame(for: state.cheetID), animate: true, remember: false)
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

    /// Moves the window. `remember` saves the result as a remembered position (like a user drag).
    func setFrame(_ frame: NSRect, animate: Bool, remember: Bool) {
        if remember { userAdjustedFrame = true }
        isAnimatingFrame = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animate ? 0.25 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isAnimatingFrame = false
                self.panel.invalidateShadow()
                if remember { self.saveFrame() }
            }
        })
    }

    // MARK: - NSWindowDelegate (remember user moves/resizes)

    func windowDidBecomeKey(_ notification: Notification) { manager.windowDidBecomeActive(self) }
    func windowWillMove(_ notification: Notification) { userAdjustedFrame = true }
    func windowWillStartLiveResize(_ notification: Notification) { userAdjustedFrame = true }
    func windowDidMove(_ notification: Notification) { scheduleFrameSave() }
    func windowDidResize(_ notification: Notification) {
        scheduleFrameSave()
        panel.invalidateShadow()
    }

    private func scheduleFrameSave() {
        guard userAdjustedFrame, !isAnimatingFrame, !isStashed, state.isVisible, model.settings.layout.rememberFrame else { return }
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
        guard !isStashed else { return }
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
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handleEscape() {
        if editState.isEditing {
            if editState.selectedID != nil { editState.selectedID = nil } else { endEditing() }
        } else if !state.query.isEmpty {
            state.query = ""
        } else {
            close()
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

    /// The outer scroll view's vertical scroller (for diagnostics).
    var outerScroller: NSScroller? { outerScrollView?.verticalScroller }

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
        // ⇧← / ⇧→ step through the cheets. With filter text they select text instead, and they're
        // left alone while editing the layout.
        if flags == .shift, keyCode == KeyCodes.leftArrow || keyCode == KeyCodes.rightArrow,
           !editState.isEditing, state.query.isEmpty {
            step(keyCode == KeyCodes.leftArrow ? -1 : 1)
            return true
        }
        guard flags.contains(.command) else { return false }

        if flags == [.command, .option] {
            if keyCode == KeyCodes.leftArrow { step(-1); return true }
            if keyCode == KeyCodes.rightArrow { step(1); return true }
            if keyCode == KeyCodes.t { manager.tile(); return true } // ⌥⌘T
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
            close() // never quit/hide the app from inside the overlay — just close this window
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

extension CheetWindowController: LayoutEditing {
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
