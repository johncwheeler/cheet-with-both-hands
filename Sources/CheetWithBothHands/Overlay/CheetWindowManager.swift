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

    // Single-window hotkey state, as in the old OverlayController (replaced in the next change).
    private var activePress: (cheetID: UUID, time: Date, hidOnPress: Bool)?

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

    func show(cheetID: UUID, alongside: Bool = false, focus: Bool? = nil) {
        guard model.cheet(id: cheetID) != nil else { return }
        if let active = activeWindow {
            active.switchTo(cheetID: cheetID)
            active.focus(focus ?? model.settings.behavior.takeFocus)
        } else {
            open(cheetID, at: presetFrame(for: cheetID), focus: focus)
        }
    }

    func toggle(cheetID: UUID) {
        if isShowing(cheetID) { hide() } else { show(cheetID: cheetID) }
    }

    func hide() {
        for window in windows { window.close() }
    }

    func toggleLast() {
        if isVisible { hide(); return }
        if let id = model.cheet(id: model.viewState.lastCheetID)?.id ?? model.cheets.first?.id {
            show(cheetID: id)
        } else {
            open(nil, at: presetFrame(for: nil), focus: true)
        }
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

    // MARK: Hotkeys (today's single-window behavior)

    func hotkeyPressed(cheetID: UUID, alongside: Bool) {
        guard activePress?.cheetID != cheetID else { return } // ignore key repeat
        let sameCheetVisible = isShowing(cheetID)
        switch model.settings.behavior.trigger {
        case .toggle, .smart:
            if sameCheetVisible { hide() } else { show(cheetID: cheetID) }
            activePress = (cheetID, Date(), sameCheetVisible)
        case .hold:
            show(cheetID: cheetID, focus: false)
            activePress = (cheetID, Date(), false)
        }
    }

    func hotkeyReleased(cheetID: UUID) {
        guard let press = activePress, press.cheetID == cheetID else { return }
        activePress = nil
        let held = Date().timeIntervalSince(press.time)
        switch model.settings.behavior.trigger {
        case .toggle: break
        case .hold: if isShowing(cheetID) { hide() }
        case .smart:
            if !press.hidOnPress, held >= model.settings.behavior.holdThreshold, isShowing(cheetID) { hide() }
        }
    }

    // MARK: Window callbacks

    func windowDidBecomeActive(_ window: CheetWindowController) {
        guard let index = windows.firstIndex(where: { $0 === window }), index != windows.count - 1 else { return }
        windows.append(windows.remove(at: index))
        if let id = window.cheetID { model.viewState.lastCheetID = id }
    }

    func windowWillClose(_ window: CheetWindowController) {
        windows.removeAll { $0 === window }
        closing.append(window)
        if windows.isEmpty { activePress = nil }
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
