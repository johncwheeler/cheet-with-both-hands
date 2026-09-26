import AppKit
import CheetCore
import Observation
import SwiftUI

struct Toast: Equatable {
    let id = UUID()
    var text: String
    var actionTitle: String?
    var action: (() -> Void)?

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

@MainActor @Observable
final class OverlayState {
    var cheetID: UUID?
    var query = ""
    var toast: Toast?
    var focusSearchRequest = 0
    var isVisible = false
    var showControls = false
    /// The window is stashed at a screen edge.
    var isStashed = false
}

struct OverlayRootView: View {
    let model: AppModel
    @Bindable var state: OverlayState
    let controller: CheetWindowController

    @FocusState private var searchFocused: Bool

    var body: some View {
        let cheet = model.cheet(id: state.cheetID)
        let appearance = model.appearance(for: cheet?.id)

        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if appearance.showHeader {
                    header(cheet: cheet, appearance: appearance)
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                } else {
                    // Keep a slim drag strip when the header is hidden.
                    WindowDragArea().frame(height: 10)
                }
                content(cheet: cheet, appearance: appearance)
            }

            if let toast = state.toast {
                HStack(spacing: 10) {
                    Text(toast.text)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if let title = toast.actionTitle, let action = toast.action {
                        Button(title) {
                            action()
                            state.toast = nil
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appearance.accent.color)
                    }
                }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.regularMaterial))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            ZStack {
                GripGlyph()
                ResizeGrip()
            }
            .frame(width: 18, height: 18)
            .padding(4)
        }
        .overlay {
            // A stashed window is a sliver at the screen edge: any click brings every window back.
            if state.isStashed {
                Color.clear.contentShape(Rectangle()).onTapGesture { controller.manager.toggleStash() }
            }
        }
        .foregroundStyle(appearance.textColor?.color ?? Color.primary)
        .background(GlassBackground(appearance: appearance))
        .environment(\.colorScheme, appearance.swiftUIScheme ?? systemScheme)
        .animation(.easeOut(duration: 0.18), value: state.toast)
        .onChange(of: state.focusSearchRequest) {
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private var systemScheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    // MARK: Header

    @ViewBuilder
    private func header(cheet: Cheet?, appearance: Appearance) -> some View {
        if controller.editState.isEditing {
            editHeader(cheet: cheet, appearance: appearance)
        } else {
            viewHeader(cheet: cheet, appearance: appearance)
        }
    }

    private func editHeader(cheet: Cheet?, appearance: Appearance) -> some View {
        let edit = controller.editState
        let hidden = cheet?.hiddenSectionCount ?? 0
        return HStack(spacing: 10) {
            Label("Editing Layout", systemImage: "rectangle.3.group")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(appearance.accent.color)
            Text(cheet?.title ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("Drag titles to reorder · drag edges to resize (⌥ for free width) · double-click a title to rename")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                HeaderButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)") { controller.undo() }
                    .disabled(!edit.canUndo)
                    .opacity(edit.canUndo ? 1 : 0.35)
                HeaderButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)") { controller.redo() }
                    .disabled(!edit.canRedo)
                    .opacity(edit.canRedo ? 1 : 0.35)
                HeaderButton(symbol: edit.showHidden ? "eye" : "eye.slash",
                             help: edit.showHidden ? "Hide hidden cards while editing" : "Show hidden cards (\(hidden))") {
                    edit.showHidden.toggle()
                }
                Menu {
                    Button("Show All Hidden Cards") { controller.resetLayout(sizes: false, styles: false, visibility: true) }
                        .disabled(hidden == 0)
                    Button("Reset All Sizes") { controller.resetLayout(sizes: true, styles: false, visibility: false) }
                    Button("Reset All Card Styles") { controller.resetLayout(sizes: false, styles: true, visibility: false) }
                    Divider()
                    Button("Reset Entire Layout") { controller.resetLayout(sizes: true, styles: true, visibility: true) }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help("Reset layout")
            }
            Button("Done") { controller.endEditing() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WindowDragArea())
    }

    private func viewHeader(cheet: Cheet?, appearance: Appearance) -> some View {
        HStack(spacing: 10) {
            cheetMenu(cheet: cheet, appearance: appearance)

            Spacer(minLength: 8)

            searchField(appearance: appearance)

            HStack(spacing: 2) {
                if model.settings.behavior.ghostMode {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondary)
                        .help("Ghost mode is on — the overlay ignores the mouse")
                }
                HeaderButton(symbol: "textformat.size.smaller", help: "Smaller text (⌘-)") { controller.adjustFontSize(-1) }
                HeaderButton(symbol: "textformat.size.larger", help: "Larger text (⌘+)") { controller.adjustFontSize(1) }
                HeaderButton(symbol: "rectangle.3.group", help: "Edit layout — hide, delete, resize and style cards (⌘E)") {
                    controller.beginEditing()
                }
                .disabled(cheet == nil)
                HeaderButton(symbol: "circle.lefthalf.filled", help: "Opacity, tint & layout") { state.showControls.toggle() }
                    .popover(isPresented: $state.showControls, arrowEdge: .bottom) {
                        QuickControls(model: model, cheetID: cheet?.id)
                    }
                HeaderButton(symbol: "square.grid.2x2", help: "Cheet picker (⌘P)") { controller.openPicker() }
                HeaderButton(symbol: "gearshape", help: "Settings (⌘,)") { controller.openSettings() }
                HeaderButton(symbol: "xmark", help: "Close (Esc)") { controller.close() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WindowDragArea(onDoubleClick: { controller.resetFrame() }))
    }

    private func cheetMenu(cheet: Cheet?, appearance: Appearance) -> some View {
        Menu {
            ForEach(Array(model.cheets.enumerated()), id: \.element.id) { index, item in
                Button {
                    controller.switchTo(cheetID: item.id)
                } label: {
                    let combo = model.combo(forCheet: item.id)?.displayString
                    Text("\(index + 1).  \(item.title)" + (combo.map { "   \($0)" } ?? ""))
                }
            }
            Divider()
            Button("Edit Layout") { controller.beginEditing() }
            Button("Tile Cheet Windows") { controller.manager.tile() }
            Button("Save Workspace…") { controller.manager.promptSaveWorkspace() }
            if let workspace = controller.manager.currentWorkspace {
                Button("Update “\(workspace.name)”") { controller.manager.updateCurrentWorkspace() }
            }
            Button("Edit Content…") { if let id = cheet?.id { controller.editCheet(id) } }
            Button("New Cheet…") { controller.newCheet() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "hands.and.sparkles.fill")
                    .foregroundStyle(appearance.accent.color)
                Text(cheet?.title ?? "Cheet with Both Hands")
                    .font(appearance.font(size: 14, weight: .semibold))
                    .lineLimit(1)
                if let cheet, let combo = model.combo(forCheet: cheet.id) {
                    Text(combo.displayString)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
    }

    private func searchField(appearance: Appearance) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Filter", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
            if !state.query.isEmpty {
                Button {
                    state.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: 210)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.08)))
    }

    // MARK: Content

    @ViewBuilder
    private func content(cheet: Cheet?, appearance: Appearance) -> some View {
        if let cheet {
            let editing = controller.editState.isEditing
            let sections = editing
                ? (controller.editState.showHidden ? cheet.sections : cheet.visibleSections)
                : controller.filteredSections(for: cheet, query: state.query)
            let style = RenderStyle(
                appearance: appearance,
                tokens: editing ? [] : CheetSearchIndex.tokens(for: state.query),
                copyOnClick: model.settings.behavior.copyOnClick && !editing
            )
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                if sections.isEmpty {
                    VStack(spacing: 6) {
                        if state.query.isEmpty {
                            Image(systemName: "eye.slash").font(.system(size: 22)).foregroundStyle(.tertiary)
                            Text("Every card on this cheet is hidden.").foregroundStyle(.secondary)
                            Button("Edit Layout") { controller.beginEditing() }
                        } else {
                            Image(systemName: "magnifyingglass").font(.system(size: 22)).foregroundStyle(.tertiary)
                            Text("Nothing matches “\(state.query)”").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    CheetContentView(
                        sections: sections,
                        style: style,
                        maxColumns: max(1, editing ? sections.count : cheet.visibleSections.count),
                        collapsed: model.viewState[cheet: cheet.id].collapsedSections,
                        editor: editing ? controller : nil,
                        onToggleSection: { controller.toggleSection($0, in: cheet.id) },
                        onCopy: { controller.copy($0) }
                    )
                    .padding(16)
                    .padding(.bottom, 10)

                    if !editing, state.query.isEmpty, cheet.hiddenSectionCount > 0 {
                        Button {
                            controller.beginEditing()
                        } label: {
                            Label("\(cheet.hiddenSectionCount) hidden card\(cheet.hiddenSectionCount == 1 ? "" : "s") · Edit Layout",
                                  systemImage: "eye.slash")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 16)
                    }
                }
                }
                // Hands the outer NSScrollView to the controller for keyboard scrolling.
                .background(EnclosingScrollViewReader { controller.attachScrollView($0) })
                .hairlineScroller()
            }
            .scrollIndicators(.automatic)
            .background {
                if editing {
                    Color.clear.contentShape(Rectangle()).onTapGesture { controller.select(nil) }
                }
            }
            .id(cheet.id)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "hands.and.sparkles").font(.system(size: 34)).foregroundStyle(.secondary)
                Text("No cheets yet").font(.title3.weight(.semibold))
                Text("Paste Markdown, HTML, CSV or JSON to create your first cheet.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("New Cheet…") { controller.newCheet() }
                    .controlSize(.large)
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Popover with the most-used visual knobs, applied live to the visible cheet.
struct QuickControls: View {
    let model: AppModel
    let cheetID: UUID?

    var body: some View {
        let binding = model.appearanceBinding(for: cheetID)
        let hasOverride = model.cheet(id: cheetID)?.appearance != nil
        VStack(alignment: .leading, spacing: 10) {
            Text(hasOverride ? "This cheet's appearance" : "Appearance (all cheets)")
                .font(.headline)
            LabeledSlider(title: "Window opacity", value: binding.windowOpacity, range: 0.25...1, format: .percent)
            LabeledSlider(title: "Background", value: binding.backgroundOpacity, range: 0...1, format: .percent)
            LabeledSlider(title: "Tint strength", value: binding.tintStrength, range: 0...1, format: .percent)
            HStack {
                ColorPicker("Tint", selection: binding.tint.color, supportsOpacity: false)
                Spacer()
                ColorPicker("Accent", selection: binding.accent.color, supportsOpacity: false)
            }
            LabeledSlider(title: "Text size", value: binding.fontSize, range: Appearance.fontSizeRange, format: .points)
            Picker("Columns", selection: binding.columns) {
                Text("Auto").tag(0)
                ForEach(1...6, id: \.self) { Text("\($0)").tag($0) }
            }
            Picker("Material", selection: binding.material) {
                ForEach(MaterialStyle.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Divider()
            if let cheetID {
                Toggle("Custom look for this cheet", isOn: Binding(
                    get: { model.cheet(id: cheetID)?.appearance != nil },
                    set: { on in
                        guard var cheet = model.cheet(id: cheetID) else { return }
                        cheet.appearance = on ? model.settings.appearance : nil
                        model.update(cheet)
                    }
                ))
            }
            Button("More Appearance Settings…") {
                AppController.shared.openSettings(.appearance)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct LabeledSlider: View {
    enum Format { case percent, points, seconds, degrees, plain }

    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: Format = .plain
    var step: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(formatted).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.callout)
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
    }

    private var formatted: String {
        switch format {
        case .percent: "\(Int((value * 100).rounded()))%"
        case .points: String(format: "%.0f pt", value)
        case .seconds: String(format: "%.2f s", value)
        case .degrees: String(format: "%.0f°", value)
        case .plain: String(format: "%.0f", value)
        }
    }
}
