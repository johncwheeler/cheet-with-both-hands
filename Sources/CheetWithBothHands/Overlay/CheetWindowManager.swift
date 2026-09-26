import AppKit
import CheetCore

/// Owns every cheet window: which one is active, where new ones open, what cheet hotkeys do, hiding
/// and bringing back the whole set. (Tiling, stashing and workspaces arrive in later changes.)
@MainActor
final class CheetWindowManager {
    let model: AppModel
    /// Visible cheet windows, back to front; the last is the active window.
    private(set) var windows: [CheetWindowController] = []
    /// Windows fading out, kept alive until their animation finishes.
    private var closing: [CheetWindowController] = []
    private var outsideClickMonitor: Any?

    init(model: AppModel) {
        self.model = model
        model.addSettingsObserver { [weak self] old, new in
            guard let self else { return }
            for window in self.windows { window.applyWindowProperties() }
            if old.layout != new.layout { self.relayoutIfVisible() }
            if old.behavior.dismissOnOutsideClick != new.behavior.dismissOnOutsideClick { self.updateOutsideClickMonitor() }
        }
    }

    var isVisible: Bool { !windows.isEmpty }
    var activeWindow: CheetWindowController? { windows.last }
    func window(showing cheetID: UUID) -> CheetWindowController? { windows.first { $0.cheetID == cheetID } }
    func isShowing(_ cheetID: UUID) -> Bool { window(showing: cheetID) != nil }

    // MARK: Showing

    /// A cheet shown from the picker, menus, Settings or a URL: replaces the active window's cheet,
    /// or opens alongside. A cheet that's already open just comes forward.
    func show(cheetID: UUID, alongside: Bool = false, focus: Bool? = nil) {
        guard model.cheet(id: cheetID) != nil else { return }
        if isStashed { unstash() }
        hiddenSet = []
        if let existing = window(showing: cheetID) {
            existing.focus(focus ?? model.settings.behavior.takeFocus)
            windowDidBecomeActive(existing)
        } else if alongside || windows.isEmpty {
            open(cheetID, at: newWindowFrame(for: cheetID), focus: focus)
        } else if let active = activeWindow {
            open(cheetID, at: active.frame, focus: focus)
            active.close() // cross-fades under the new window
        }
    }

    func toggle(cheetID: UUID) {
        if let existing = window(showing: cheetID) { existing.close() } else { show(cheetID: cheetID) }
    }

    /// A window closed by "hide all", remembered for toggle last.
    private struct HiddenWindow { var cheetID: UUID?; var frame: NSRect; var query: String }
    /// The set toggle last brings back: the last hide-all, or the last window closed on its own.
    private var hiddenSet: [HiddenWindow] = []
    private var isHidingAll = false

    /// Closes every cheet window, remembering them for toggle last.
    func hide() {
        guard !windows.isEmpty else { return }
        hiddenSet = windows.map { HiddenWindow(cheetID: $0.cheetID, frame: $0.frame, query: $0.state.query) }
        isHidingAll = true
        for window in windows { window.close() }
        isHidingAll = false
    }

    func toggleLast() {
        if isStashed { unstash(); return }
        if isVisible { hide(); return }
        let set = hiddenSet.filter { $0.cheetID.map { model.cheet(id: $0) != nil } ?? true }
        hiddenSet = []
        if !set.isEmpty {
            for item in set {
                open(item.cheetID, at: item.frame, focus: false).state.query = item.query
            }
            activeWindow?.focus(model.settings.behavior.takeFocus)
        } else if let id = model.cheet(id: model.viewState.lastCheetID)?.id ?? model.cheets.first?.id {
            show(cheetID: id)
        } else {
            open(nil, at: presetFrame(for: nil), focus: true) // the empty-library state
        }
    }

    /// Where a new window goes: the cheet's own remembered frame (per-cheet positions), the preset
    /// frame when it's the only window, otherwise offset from the active window.
    func newWindowFrame(for cheetID: UUID?) -> NSRect {
        let layout = model.settings.layout
        if layout.rememberFrame, layout.perCheetFrames, let id = cheetID, model.viewState[cheet: id].frame != nil {
            return presetFrame(for: id)
        }
        guard let active = activeWindow, let screen = active.window.screen ?? NSScreen.main else { return presetFrame(for: cheetID) }
        return active.frame.offsetBy(dx: 28, dy: -28).clamped(to: screen.visibleFrame, minSize: OverlayPanel.minimumSize)
    }

    func closeWindow(showing cheetID: UUID) { window(showing: cheetID)?.close() }

    func editLayout(cheetID: UUID) {
        show(cheetID: cheetID, focus: true)
        window(showing: cheetID)?.beginEditing()
    }

    func showToast(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        activeWindow?.showToast(message, actionTitle: actionTitle, action: action)
    }

    /// Copying from an image in a cheet: clicking a window makes it the active one, so its toast shows there.
    func copy(_ text: String) { activeWindow?.copy(text) }
    func copyImage(_ source: String) { activeWindow?.copyImage(source) }

    func relayoutIfVisible() {
        guard let active = activeWindow else { return }
        active.setFrame(presetFrame(for: active.cheetID), animate: true, remember: false)
    }

    @discardableResult
    private func open(_ cheetID: UUID?, at frame: NSRect, focus: Bool?) -> CheetWindowController {
        let window = CheetWindowController(model: model, manager: self)
        windows.append(window)
        window.open(cheetID: cheetID, at: frame, focus: focus)
        updateOutsideClickMonitor()
        return window
    }

    // MARK: Hotkeys

    /// A press waiting for its release to learn whether it was a tap or a hold.
    private struct PendingPress {
        var cheetID: UUID
        var time: Date
        var action: PressDecision.OnPress
        weak var opened: CheetWindowController?
        weak var replaced: CheetWindowController?
    }
    private var pendingPress: PendingPress?

    func hotkeyPressed(cheetID: UUID, alongside: Bool) {
        guard pendingPress?.cheetID != cheetID, model.cheet(id: cheetID) != nil else { return } // ignore key repeat
        if isStashed, let existing = window(showing: cheetID) {
            unstash() // its window is a sliver: bring everything back rather than closing it
            existing.focus(model.settings.behavior.takeFocus)
            return
        }
        hiddenSet = []
        let situation: PressDecision.Situation = isShowing(cheetID) ? .cheetVisible : (windows.isEmpty ? .noWindows : .othersVisible)
        let action = PressDecision.onPress(situation, alongside: alongside)
        let focus = model.settings.behavior.trigger != .hold
        var press = PendingPress(cheetID: cheetID, time: Date(), action: action)
        switch action {
        case .close:
            window(showing: cheetID)?.close()
        case .open:
            press.opened = open(cheetID, at: newWindowFrame(for: cheetID), focus: focus)
        case .openOver:
            press.replaced = activeWindow
            press.opened = open(cheetID, at: activeWindow?.frame ?? newWindowFrame(for: cheetID), focus: focus)
        }
        pendingPress = press
    }

    func hotkeyReleased(cheetID: UUID) {
        guard let press = pendingPress, press.cheetID == cheetID else { return }
        pendingPress = nil
        let behavior = model.settings.behavior
        let release = PressDecision.onRelease(after: press.action, trigger: behavior.trigger,
                                              heldFor: Date().timeIntervalSince(press.time), holdThreshold: behavior.holdThreshold)
        // A tap or an alongside press brings the stash back; a peek leaves it alone.
        if isStashed, press.action != .close, release != .closeOpened { unstash() }
        switch release {
        case .nothing: break
        case .closeOpened: press.opened?.close()
        case .closeReplaced: press.replaced?.close()
        }
    }

    // MARK: Tiling

    /// Tiles the visible windows onto the active window's screen, keeping their reading order.
    func tile() {
        guard let active = activeWindow, let screen = active.window.screen ?? NSScreen.main else { return }
        let margin = CGFloat(model.settings.layout.margin)
        let container = screen.visibleFrame.insetBy(dx: margin, dy: margin)
        let frames = TileLayout.tile(windows.map(\.frame), in: container, gap: 12, minWidth: OverlayPanel.minimumSize.width)
        if isStashed { unstash() } // frames above come from the home frames
        for (window, frame) in zip(windows, frames) {
            window.setFrame(frame, animate: true, remember: true)
        }
    }

    // MARK: Stashing

    private(set) var isStashed = false

    func toggleStash() { isStashed ? unstash() : stash() }

    /// Slides every window to the nearest free screen edge, leaving a 20pt sliver.
    func stash() {
        guard !windows.isEmpty, !isStashed else { return }
        isStashed = true
        pendingPress = nil
        for window in windows {
            guard let screen = window.window.screen ?? NSScreen.main else { continue }
            let others = NSScreen.screens.filter { $0 !== screen }.map(\.frame)
            let target = StashGeometry.stash(window.frame, visibleFrame: screen.visibleFrame, screenFrame: screen.frame,
                                             otherScreens: others, sliver: 20)
            window.stash(to: target.frame)
        }
    }

    /// Brings every stashed window back to where it was (onto a remaining screen if its display is gone).
    func unstash() {
        guard isStashed else { return }
        isStashed = false
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        for window in windows {
            guard let home = window.homeFrame else { continue }
            let stillOnAScreen = NSScreen.screens.contains { $0.frame.intersects(home) }
            let target = stillOnAScreen || mouseScreen == nil ? home
                : home.clamped(to: mouseScreen!.visibleFrame, minSize: OverlayPanel.minimumSize)
            window.unstash(to: target)
        }
        activeWindow?.focus(model.settings.behavior.takeFocus)
    }

    // MARK: Window callbacks

    func windowDidBecomeActive(_ window: CheetWindowController) {
        guard let index = windows.firstIndex(where: { $0 === window }), index != windows.count - 1 else { return }
        windows.append(windows.remove(at: index))
        if let id = window.cheetID { model.viewState.lastCheetID = id }
    }

    func windowWillClose(_ window: CheetWindowController) {
        if !isHidingAll, windows.count == 1, windows.first === window {
            hiddenSet = [HiddenWindow(cheetID: window.cheetID, frame: window.frame, query: window.state.query)]
        }
        windows.removeAll { $0 === window }
        if isStashed, !windows.contains(where: \.isStashed) { isStashed = false }
        closing.append(window)
        if windows.isEmpty { pendingPress = nil }
        updateOutsideClickMonitor()
    }

    func windowDidFinishClosing(_ window: CheetWindowController) {
        closing.removeAll { $0 === window }
    }

    /// The next cheet in the library from `cheetID`, skipping cheets open in other windows.
    func neighbour(of cheetID: UUID?, delta: Int, for window: CheetWindowController) -> UUID? {
        let cheets = model.cheets
        guard !cheets.isEmpty else { return nil }
        var index = model.index(of: cheetID) ?? 0
        for _ in 0..<cheets.count {
            index = (index + delta + cheets.count) % cheets.count
            let candidate = cheets[index].id
            if candidate == cheetID { return nil }
            if let owner = self.window(showing: candidate), owner !== window { continue }
            return candidate
        }
        return nil
    }

    // MARK: Placement (moved from OverlayController)

    func screenForPresentation() -> NSScreen {
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

    /// A cheet's remembered frame (global or per cheet) or the preset from Position & Size.
    func presetFrame(for cheetID: UUID?) -> NSRect {
        let visible = screenForPresentation().visibleFrame
        let layout = model.settings.layout
        let minSize = OverlayPanel.minimumSize
        if layout.rememberFrame {
            let saved = layout.perCheetFrames ? cheetID.flatMap { model.viewState[cheet: $0].frame } : model.viewState.globalFrame
            if let saved { return saved.denormalized(in: visible).clamped(to: visible, minSize: minSize) }
        }
        let margin = CGFloat(layout.margin)
        let width = min(max(minSize.width, visible.width * layout.widthFraction), visible.width - 2 * margin)
        let height = min(max(minSize.height, visible.height * layout.heightFraction), visible.height - 2 * margin)
        let unit = layout.anchor.unitPosition
        let x = visible.minX + margin + (visible.width - 2 * margin - width) * unit.x
        let y = visible.minY + margin + (visible.height - 2 * margin - height) * unit.y
        return NSRect(x: x, y: y, width: width, height: height).integral
    }

    // MARK: Hide on outside click

    private func updateOutsideClickMonitor() {
        let wanted = model.settings.behavior.dismissOnOutsideClick && !windows.isEmpty
        if wanted, outsideClickMonitor == nil {
            // Global monitors only see clicks in other apps, so clicks in any cheet window don't count.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.windows.contains(where: { $0.editState.isEditing }) else { return }
                    self.hide()
                }
            }
        } else if !wanted, let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}
