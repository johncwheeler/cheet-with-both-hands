import AppKit
import CheetCore
import Observation
import SwiftUI

enum PickerItem: Identifiable {
    case workspace(Workspace)
    case cheet(index: Int, cheet: Cheet)

    var id: UUID {
        switch self {
        case .workspace(let workspace): workspace.id
        case .cheet(_, let cheet): cheet.id
        }
    }
}

@MainActor @Observable
final class PickerState {
    var query = ""
    var selection = 0
    var focusRequest = 0
}

/// Spotlight-style palette for jumping to any cheet by name.
@MainActor
final class PickerController: NSObject, NSWindowDelegate {
    let model: AppModel
    let state = PickerState()
    var onChoose: ((UUID, _ alongside: Bool) -> Void)?
    var onRecall: ((UUID) -> Void)?

    private let panel = OverlayPanel()
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    var isVisible: Bool { panel.isVisible }
    var window: NSWindow { panel }

    init(model: AppModel) {
        self.model = model
        super.init()
        let hosting = NSHostingView(rootView: PickerView(model: model, state: state, controller: self))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.delegate = self
        panel.minSize = NSSize(width: 420, height: 200)
        panel.onCancel = { [weak self] in self?.hide() }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show(focus: Bool = true) {
        state.query = ""
        state.selection = model.workspaces.count + max(0, model.index(of: model.viewState.lastCheetID) ?? 0)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = NSSize(width: 560, height: min(460, visible.height * 0.6))
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.62 - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size).integral, display: false)
        panel.appearance = model.settings.appearance.nsAppearance
        panel.alphaValue = 0
        if focus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        if focus { state.focusRequest += 1 }
        installMonitors()
    }

    func hide() {
        removeMonitors()
        panel.orderOut(nil)
    }

    /// Matching workspaces first, then cheets (best title matches first).
    func results() -> [PickerItem] {
        let tokens = CheetSearchIndex.tokens(for: state.query)
        let workspaces = model.workspaces.filter { workspace in
            tokens.allSatisfy { workspace.name.searchFolded.contains($0) }
        }.map(PickerItem.workspace)
        let all = model.cheets.enumerated().map { (index: $0.offset, cheet: $0.element) }
        guard !tokens.isEmpty else { return workspaces + all.map { .cheet(index: $0.index, cheet: $0.cheet) } }
        let scored = all.compactMap { item -> (Int, (index: Int, cheet: Cheet))? in
            let title = item.cheet.title.searchFolded
            let sections = item.cheet.sections.map { $0.title.searchFolded }.joined(separator: " ")
            let haystack = title + " " + sections
            guard tokens.allSatisfy({ haystack.contains($0) }) else { return nil }
            var score = 0
            if title.hasPrefix(tokens[0]) { score += 100 }
            if tokens.allSatisfy({ title.contains($0) }) { score += 50 }
            return (score, item)
        }
        let cheets = scored.sorted { $0.0 > $1.0 || ($0.0 == $1.0 && $0.1.index < $1.1.index) }
            .map { PickerItem.cheet(index: $0.1.index, cheet: $0.1.cheet) }
        return workspaces + cheets
    }

    /// The row selected when the query changes: the first matching cheet, so typing a cheet's name and
    /// pressing Return opens it even when a workspace (listed first) also matches.
    func defaultSelection() -> Int {
        guard !state.query.trimmingCharacters(in: .whitespaces).isEmpty else { return 0 }
        return results().firstIndex { if case .cheet = $0 { return true } else { return false } } ?? 0
    }

    func choose(_ item: PickerItem, alongside: Bool = false) {
        hide()
        switch item {
        case .workspace(let workspace): onRecall?(workspace.id)
        case .cheet(_, let cheet): onChoose?(cheet.id, alongside)
        }
    }

    func chooseSelection(alongside: Bool = false) {
        let list = results()
        guard list.indices.contains(state.selection) else { NSSound.beep(); return }
        choose(list[state.selection], alongside: alongside)
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let count = self.results().count
            switch UInt32(event.keyCode) {
            case KeyCodes.escape:
                self.hide()
            case KeyCodes.downArrow:
                if count > 0 { self.state.selection = (self.state.selection + 1) % count }
            case KeyCodes.upArrow:
                if count > 0 { self.state.selection = (self.state.selection - 1 + count) % count }
            case KeyCodes.returnKey, KeyCodes.keypadEnter:
                self.chooseSelection(alongside: event.modifierFlags.contains(.shift))
            default:
                return event
            }
            return nil
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

struct PickerView: View {
    let model: AppModel
    @Bindable var state: PickerState
    let controller: PickerController
    @FocusState private var focused: Bool

    var body: some View {
        let appearance = model.settings.appearance
        let results = controller.results()
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Jump to a cheet…", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .regular))
                    .focused($focused)
                    .onChange(of: state.query) { state.selection = controller.defaultSelection() }
                Text("\(model.cheets.count) cheets")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if model.settings.branding.pickerMascotEnabled, let head = Mascot.head {
                    Image(nsImage: head)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 60, height: 57)
                        .padding(.vertical, -12) // overhangs the row instead of making it taller
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(WindowDragArea())

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { position, item in
                            Group {
                                switch item {
                                case .workspace(let workspace):
                                    WorkspacePickerRow(workspace: workspace, cheets: model.cheets,
                                                       combo: model.hotkeyPlan.combo(for: .recallWorkspace(workspace.id)),
                                                       isSelected: position == state.selection, accent: appearance.accent.color)
                                case .cheet(let index, let cheet):
                                    PickerRow(number: index + 1, cheet: cheet, combo: model.combo(forCheet: cheet.id),
                                              isSelected: position == state.selection, accent: appearance.accent.color)
                                }
                            }
                            .id(item.id)
                            .onTapGesture { controller.choose(item, alongside: NSEvent.modifierFlags.contains(.shift)) }
                            .onHover { if $0 { state.selection = position } }
                        }
                        if results.isEmpty {
                            Text(model.cheets.isEmpty ? "No cheets yet" : "No cheets match “\(state.query)”")
                                .foregroundStyle(.secondary)
                                .padding(.top, 30)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: state.selection) {
                    if results.indices.contains(state.selection) {
                        proxy.scrollTo(results[state.selection].id)
                    }
                }
            }

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
            HStack(spacing: 14) {
                Label("open", systemImage: "return")
                Label("alongside", systemImage: "shift")
                Label("move", systemImage: "arrow.up.arrow.down")
                Label("close", systemImage: "escape")
                Spacer()
                Button("New Cheet…") {
                    controller.hide()
                    AppController.shared.openImporter()
                }
                .buttonStyle(.plain)
                .foregroundStyle(appearance.accent.color)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .foregroundStyle(appearance.textColor?.color ?? Color.primary)
        .background(GlassBackground(appearance: appearance))
        .environment(\.colorScheme, appearance.swiftUIScheme ?? .dark)
        .onChange(of: state.focusRequest) {
            DispatchQueue.main.async { focused = true }
        }
    }
}

private struct WorkspacePickerRow: View {
    let workspace: Workspace
    let cheets: [Cheet]
    let combo: KeyCombo?
    let isSelected: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(accent.opacity(isSelected ? 0.35 : 0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(workspace.windows.compactMap { window in cheets.first { $0.id == window.cheetID }?.title }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let combo {
                Text(combo.displayString)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? Color.primary.opacity(0.12) : .clear))
        .contentShape(Rectangle())
    }
}

private struct PickerRow: View {
    let number: Int
    let cheet: Cheet
    let combo: KeyCombo?
    let isSelected: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(accent.opacity(isSelected ? 0.35 : 0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(cheet.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(cheet.sections.prefix(4).map(\.title).filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let combo {
                Text(combo.displayString)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? Color.primary.opacity(0.12) : .clear))
        .contentShape(Rectangle())
    }
}
