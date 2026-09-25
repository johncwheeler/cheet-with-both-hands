import AppKit
import CheetCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Editing state & protocol

struct LiveResize: Equatable {
    var id: UUID
    var width: CardWidth
    var height: Double?
}

enum MovePosition { case start, earlier, later, end }

/// Transient state of the layout editor (what's selected, being resized or dragged).
@MainActor @Observable
final class LayoutEditState {
    var isEditing = false
    var selectedID: UUID?
    var liveResize: LiveResize?
    var draggingID: UUID?
    var showHidden = true
    var canUndo = false
    var canRedo = false
}

/// Operations the card views call while the overlay is in layout-editing mode.
@MainActor
protocol LayoutEditing: AnyObject {
    var editState: LayoutEditState { get }
    func select(_ id: UUID?)
    func toggleHidden(_ id: UUID)
    func deleteSection(_ id: UUID)
    func renameSection(_ id: UUID, to title: String)
    func setLiveResize(_ live: LiveResize)
    func commitResize()
    func resetSize(_ id: UUID, width: Bool, height: Bool)
    func cardStyle(for id: UUID) -> CardStyle
    func setCardStyle(_ style: CardStyle, for id: UUID)
    func applyStyleToAll(_ style: CardStyle)
    func resetCard(_ id: UUID)
    func beginChange()
    func endChange()
    func beginDrag(_ id: UUID)
    func moveSection(_ id: UUID, onto target: UUID)
    func moveSection(_ id: UUID, to position: MovePosition)
}

// MARK: - Grid metrics

/// Column geometry for a given content width, shared by the layout and the resize handles.
struct GridMetrics: Equatable {
    var width: CGFloat
    var columns: Int
    var columnWidth: CGFloat
    var spacing: CGFloat
    var minCardWidth: CGFloat

    static func make(width: CGFloat, style: RenderStyle, maxColumns: Int?) -> GridMetrics {
        let width = max(width, 1)
        let spacing = 14 * style.scale
        let fontFactor = max(0.8, min(1.6, (CGFloat(style.appearance.fontSize) / 13).squareRoot()))
        let minColumn = CGFloat(style.appearance.minColumnWidth) * style.scale * fontFactor
        var columns = style.appearance.columns > 0
            ? style.appearance.columns
            : max(1, Int((width + spacing) / (minColumn + spacing)))
        if let maxColumns { columns = min(columns, max(1, maxColumns)) }
        let columnWidth = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        return GridMetrics(width: width, columns: columns, columnWidth: columnWidth, spacing: spacing,
                           minCardWidth: min(width, 140 * style.scale))
    }

    func span(_ count: Int) -> CGFloat {
        let k = min(max(1, count), columns)
        return CGFloat(k) * columnWidth + CGFloat(k - 1) * spacing
    }

    func resolve(_ cardWidth: CardWidth, prefersFullWidth: Bool) -> CGFloat {
        switch cardWidth {
        case .auto: prefersFullWidth && columns > 1 ? width : columnWidth
        case .columns(let k): span(k)
        case .fraction(let f): min(width, max(minCardWidth, CGFloat(f) * width))
        }
    }

    /// Snaps a dragged width to whole columns, or to a free fraction when `freeform`.
    func snap(_ proposed: CGFloat, freeform: Bool) -> CardWidth {
        if freeform {
            return .fraction(Double(min(1, max(minCardWidth / width, proposed / width))))
        }
        let k = Int(((proposed + spacing) / (columnWidth + spacing)).rounded())
        return .columns(min(max(1, k), columns))
    }

    func describe(_ cardWidth: CardWidth) -> String {
        switch cardWidth {
        case .auto: "Auto width"
        case .columns(let k): "\(min(k, columns)) of \(columns) column\(columns == 1 ? "" : "s")"
        case .fraction(let f): "\(Int((f * 100).rounded()))% width"
        }
    }
}

// MARK: - Card

/// One section card: per-card styling, and — while editing — a toolbar, resize handles,
/// drag-to-reorder and selection.
struct CardView: View {
    let section: CheetSection
    let style: RenderStyle
    let isCollapsed: Bool
    let metrics: GridMetrics
    let editor: LayoutEditing?
    let onToggle: () -> Void
    let onCopy: ((String) -> Void)?

    @State private var measured: CGSize = .zero
    @State private var dragStart: CGSize?
    @State private var showStyleEditor = false
    @State private var isRenaming = false
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool

    private var isEditing: Bool { editor?.editState.isEditing == true }
    private var live: LiveResize? {
        guard let live = editor?.editState.liveResize, live.id == section.id else { return nil }
        return live
    }
    private var isSelected: Bool { isEditing && editor?.editState.selectedID == section.id }
    private var isDragging: Bool { isEditing && editor?.editState.draggingID == section.id }

    var body: some View {
        let cardStyle = section.layout.style
        let renderStyle = style.applying(cardStyle)
        let height = live != nil ? live?.height : section.layout.height
        let radius = CGFloat(cardStyle.cornerRadius ?? 10) * style.scale

        VStack(alignment: .leading, spacing: 8 * style.scale) {
            titleRow(renderStyle)
            if !isCollapsed {
                if height != nil {
                    ScrollView(.vertical) {
                        SectionBlocksView(blocks: section.blocks, style: renderStyle, onCopy: onCopy)
                            .equatable()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.automatic)
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    SectionBlocksView(blocks: section.blocks, style: renderStyle, onCopy: onCopy)
                        .equatable()
                }
            }
        }
        .padding(hasCardChrome ? 12 * style.scale : 4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: isCollapsed ? nil : height.map { CGFloat($0) }, alignment: .top)
        .foregroundStyle(cardStyle.textColor?.color ?? style.appearance.textColor?.color ?? Color.primary)
        .background(CardBackgroundView(style: cardStyle, cornerRadius: radius, standardCards: style.appearance.sectionCards,
                                       accent: renderStyle.accent))
        .opacity(section.layout.isHidden ? 0.4 : (isDragging ? 0.55 : 1))
        .overlay { if isEditing { editChrome(radius: radius) } }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measured = proxy.size }
                    .onChange(of: proxy.size) { measured = proxy.size }
            }
        )
        .if(isEditing) { view in
            view
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { editor?.select(section.id) })
                .onDrop(of: [.text], delegate: CardDropDelegate(targetID: section.id, editor: editor))
        }
    }

    private var hasCardChrome: Bool {
        section.layout.style.fill != .standard || style.appearance.sectionCards || isEditing
    }

    // MARK: Title

    @ViewBuilder
    private func titleRow(_ renderStyle: RenderStyle) -> some View {
        if !section.title.isEmpty || isEditing {
            HStack(spacing: 6) {
                if isEditing {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: style.fontSize * 0.75, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .help("Drag to reorder")
                }
                if isRenaming {
                    TextField("Section title", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(renderStyle.font(0.8, weight: .bold))
                        .focused($titleFocused)
                        .onSubmit(commitRename)
                        .onChange(of: titleFocused) { if !titleFocused { commitRename() } }
                } else {
                    Text(section.title.isEmpty ? "Untitled" : InlineRenderer.shared.render(section.title, style: renderStyle, relative: 0.8, weight: .bold))
                        .font(renderStyle.font(0.8, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(section.title.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(renderStyle.accent))
                        .multilineTextAlignment(.leading)
                        .onTapGesture(count: 2) {
                            guard isEditing else { return }
                            titleDraft = section.title
                            isRenaming = true
                            DispatchQueue.main.async { titleFocused = true }
                        }
                }
                if isEditing, section.layout.isHidden {
                    Text("HIDDEN")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.primary.opacity(0.15)))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if isEditing {
                    // Room for the floating toolbar.
                    Color.clear.frame(width: 104, height: 1)
                } else {
                    Button(action: onToggle) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: style.fontSize * 0.65, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                            .frame(width: 18, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isCollapsed ? "Expand section" : "Collapse section")
                }
            }
            .contentShape(Rectangle())
            .if(!isEditing) { $0.onTapGesture(perform: onToggle) }
            .if(isEditing && !isRenaming) { view in
                view.onDrag {
                    editor?.beginDrag(section.id)
                    return NSItemProvider(object: section.id.uuidString as NSString)
                }
            }
        }
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        let trimmed = titleDraft.trimmingCharacters(in: .whitespaces)
        if trimmed != section.title { editor?.renameSection(section.id, to: trimmed) }
    }

    // MARK: Edit chrome

    @ViewBuilder
    private func editChrome(radius: CGFloat) -> some View {
        let accent = style.appearance.accent.color
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(isSelected ? accent : Color.primary.opacity(0.35),
                              style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isSelected ? [] : [5, 4]))
                .allowsHitTesting(false)

            if let live {
                Text(sizeReadout(live))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.9)))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }

            toolbar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(6)
        }
        .overlay(alignment: .trailing) {
            ResizeHandle(axis: .width, accent: accent, onChange: { resize(.width, $0) }, onEnd: endResize,
                         onDoubleClick: { editor?.resetSize(section.id, width: true, height: false) })
                .frame(width: 10)
                .padding(.vertical, 18)
                .offset(x: 5)
        }
        .overlay(alignment: .bottom) {
            ResizeHandle(axis: .height, accent: accent, onChange: { resize(.height, $0) }, onEnd: endResize,
                         onDoubleClick: { editor?.resetSize(section.id, width: false, height: true) })
                .frame(height: 10)
                .padding(.horizontal, 18)
                .offset(y: 5)
        }
        .overlay(alignment: .bottomTrailing) {
            ResizeHandle(axis: .both, accent: accent, onChange: { resize(.both, $0) }, onEnd: endResize,
                         onDoubleClick: { editor?.resetSize(section.id, width: true, height: true) })
                .frame(width: 16, height: 16)
                .offset(x: 4, y: 4)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 1) {
            ToolbarIcon(symbol: section.layout.isHidden ? "eye.slash" : "eye",
                        help: section.layout.isHidden ? "Show this card" : "Hide this card") {
                editor?.toggleHidden(section.id)
            }
            ToolbarIcon(symbol: "paintbrush", help: "Card style") { showStyleEditor.toggle() }
                .popover(isPresented: $showStyleEditor, arrowEdge: .bottom) {
                    if let editor {
                        CardStyleEditor(
                            title: section.title.isEmpty ? "Untitled" : InlineMarkdown.plainText(section.title),
                            baseFontSize: style.appearance.fontSize,
                            accent: style.appearance.accent,
                            style: Binding(get: { editor.cardStyle(for: section.id) },
                                           set: { editor.setCardStyle($0, for: section.id) }),
                            onApplyToAll: { editor.applyStyleToAll(editor.cardStyle(for: section.id)) }
                        )
                        .onAppear { editor.beginChange() }
                        .onDisappear { editor.endChange() }
                    }
                }
            Menu {
                Button("Move to Start") { editor?.moveSection(section.id, to: .start) }
                Button("Move Earlier") { editor?.moveSection(section.id, to: .earlier) }
                Button("Move Later") { editor?.moveSection(section.id, to: .later) }
                Button("Move to End") { editor?.moveSection(section.id, to: .end) }
                Divider()
                Button("Rename…") {
                    titleDraft = section.title
                    isRenaming = true
                    DispatchQueue.main.async { titleFocused = true }
                }
                Button("Fit Height to Content") { editor?.resetSize(section.id, width: false, height: true) }
                Button("Automatic Width") { editor?.resetSize(section.id, width: true, height: false) }
                Button("Reset Size & Style") { editor?.resetCard(section.id) }
                Divider()
                Button(section.layout.isHidden ? "Show Card" : "Hide Card") { editor?.toggleHidden(section.id) }
                Button("Delete Card", role: .destructive) { editor?.deleteSection(section.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            ToolbarIcon(symbol: "trash", help: "Delete this card (undo with ⌘Z)") {
                editor?.deleteSection(section.id)
            }
        }
        .padding(2)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }

    // MARK: Resizing

    private func resize(_ axis: ResizeHandle.Axis, _ translation: CGSize) {
        guard let editor else { return }
        if dragStart == nil {
            dragStart = measured
            editor.select(section.id)
            editor.beginChange()
        }
        let start = dragStart ?? measured
        var width = section.layout.width
        var height = section.layout.height
        if axis != .height {
            width = metrics.snap(start.width + translation.width, freeform: NSEvent.modifierFlags.contains(.option))
        }
        if axis != .width {
            height = max(56, (Double(start.height + translation.height)).rounded())
        }
        editor.setLiveResize(LiveResize(id: section.id, width: width, height: height))
    }

    private func endResize() {
        dragStart = nil
        editor?.commitResize()
        editor?.endChange()
    }

    private func sizeReadout(_ live: LiveResize) -> String {
        let width = metrics.describe(live.width)
        let height = live.height.map { "\(Int($0)) pt tall" } ?? "fit height"
        return "\(width) · \(height)"
    }
}

/// The blocks inside a card. Equatable so resizing a sibling doesn't re-render every table.
struct SectionBlocksView: View, Equatable {
    let blocks: [CheetBlock]
    let style: RenderStyle
    let onCopy: ((String) -> Void)?

    static func == (lhs: SectionBlocksView, rhs: SectionBlocksView) -> Bool {
        lhs.blocks == rhs.blocks && lhs.style == rhs.style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * style.scale) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block, style: style, onCopy: onCopy)
            }
        }
    }
}

extension RenderStyle {
    /// Applies a card's font-size and title-color overrides.
    func applying(_ card: CardStyle) -> RenderStyle {
        var copy = self
        if let size = card.fontSize { copy.appearance.fontSize = size }
        if let title = card.titleColor { copy.appearance.accent = title }
        if let text = card.textColor { copy.appearance.textColor = text }
        return copy
    }
}

// MARK: - Card background

struct CardBackgroundView: View {
    let style: CardStyle
    let cornerRadius: CGFloat
    let standardCards: Bool
    let accent: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let effectColor = style.effectColor?.color ?? accent
        fill(shape)
            .shadow(color: style.effect == .glow ? effectColor.opacity(0.85) : .clear, radius: 8)
            .shadow(color: style.effect == .glow ? effectColor.opacity(0.45) : .clear, radius: 20)
            .shadow(color: style.effect == .shadow ? .black.opacity(0.45) : .clear, radius: 10, x: 0, y: 6)
            .overlay {
                if style.effect == .outline {
                    shape.strokeBorder(effectColor, lineWidth: 1.5)
                }
            }
    }

    @ViewBuilder
    private func fill(_ shape: RoundedRectangle) -> some View {
        switch style.fill {
        case .standard:
            if standardCards {
                shape.fill(Color.primary.opacity(0.055))
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
            } else {
                shape.fill(Color.clear)
            }
        case .none:
            shape.fill(Color.clear)
        case .solid:
            shape.fill(style.fillColor.color.opacity(style.fillOpacity))
        case .gradient:
            let (start, end) = Self.points(forAngle: style.gradientAngle)
            shape.fill(LinearGradient(colors: [style.fillColor.color, style.fillColor2.color], startPoint: start, endPoint: end))
                .opacity(style.fillOpacity)
        case .frosted:
            shape.fill(.regularMaterial)
                .overlay(shape.fill(style.fillColor.color.opacity(0.18)))
                .opacity(max(0.15, style.fillOpacity))
        }
    }

    static func points(forAngle degrees: Double) -> (UnitPoint, UnitPoint) {
        let radians = degrees * .pi / 180
        let dx = cos(radians) / 2, dy = sin(radians) / 2
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}

// MARK: - Small pieces

private struct ToolbarIcon: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 20)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct ResizeHandle: View {
    enum Axis { case width, height, both }

    let axis: Axis
    let accent: Color
    let onChange: (CGSize) -> Void
    let onEnd: () -> Void
    let onDoubleClick: () -> Void
    @State private var hovering = false
    @State private var cursorPushed = false

    var body: some View {
        ZStack {
            switch axis {
            case .width:
                Capsule().fill(accent.opacity(hovering ? 0.9 : 0.45)).frame(width: 4).padding(.vertical, 6)
            case .height:
                Capsule().fill(accent.opacity(hovering ? 0.9 : 0.45)).frame(height: 4).padding(.horizontal, 6)
            case .both:
                Circle().fill(accent.opacity(hovering ? 1 : 0.8))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5))
                    .frame(width: 12, height: 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside, !cursorPushed {
                cursor.push()
                cursorPushed = true
            } else if !inside, cursorPushed {
                NSCursor.pop()
                cursorPushed = false
            }
        }
        .onDisappear {
            if cursorPushed { NSCursor.pop() }
            cursorPushed = false
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { onChange($0.translation) }
                .onEnded { _ in onEnd() }
        )
        .onTapGesture(count: 2, perform: onDoubleClick)
        .help(helpText)
    }

    private var cursor: NSCursor {
        switch axis {
        case .width: .resizeLeftRight
        case .height: .resizeUpDown
        case .both:
            if #available(macOS 15.0, *) { .frameResize(position: .bottomRight, directions: .all) } else { .crosshair }
        }
    }

    private var helpText: String {
        switch axis {
        case .width: "Drag to change width (snaps to columns, hold ⌥ for free sizing). Double-click for automatic width."
        case .height: "Drag to set a fixed height. Double-click to fit the content."
        case .both: "Drag to resize. Double-click to reset the size."
        }
    }
}

struct CardDropDelegate: DropDelegate {
    let targetID: UUID
    let editor: LayoutEditing?

    func dropEntered(info: DropInfo) {
        guard let editor, let dragging = editor.editState.draggingID, dragging != targetID else { return }
        withAnimation(.snappy(duration: 0.25)) {
            editor.moveSection(dragging, onto: targetID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        editor?.editState.draggingID = nil
        editor?.endChange()
        return true
    }
}

// MARK: - Card style editor

struct CardStyleEditor: View {
    let title: String
    let baseFontSize: Double
    let accent: RGBAColor
    @Binding var style: CardStyle
    let onApplyToAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Card Style").font(.headline)
                Text(title).foregroundStyle(.secondary).lineLimit(1)
            }

            GroupBox("Text") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Custom size", isOn: Binding(
                        get: { style.fontSize != nil },
                        set: { style.fontSize = $0 ? (style.fontSize ?? baseFontSize) : nil }
                    ))
                    if style.fontSize != nil {
                        LabeledSlider(title: "Size", value: Binding(get: { style.fontSize ?? baseFontSize }, set: { style.fontSize = $0 }),
                                      range: Appearance.fontSizeRange, format: .points, step: 0.5)
                    }
                    OptionalColorRow(title: "Title color", color: $style.titleColor, fallback: accent)
                    OptionalColorRow(title: "Text color", color: $style.textColor, fallback: RGBAColor(r: 0.95, g: 0.95, b: 0.97))
                }
                .padding(4)
            }

            GroupBox("Background") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Fill", selection: $style.fill) {
                        ForEach(CardFill.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if style.fill == .solid || style.fill == .gradient || style.fill == .frosted {
                        HStack {
                            ColorPicker(style.fill == .gradient ? "From" : "Color", selection: $style.fillColor.color, supportsOpacity: false)
                            if style.fill == .gradient {
                                Spacer()
                                ColorPicker("To", selection: $style.fillColor2.color, supportsOpacity: false)
                            }
                        }
                        if style.fill == .gradient {
                            LabeledSlider(title: "Angle", value: $style.gradientAngle, range: 0...360, format: .degrees)
                        }
                        LabeledSlider(title: "Opacity", value: $style.fillOpacity, range: 0.05...1, format: .percent)
                    }
                    Picker("Effect", selection: $style.effect) {
                        ForEach(CardEffect.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if style.effect == .glow || style.effect == .outline {
                        OptionalColorRow(title: "Effect color", color: $style.effectColor, fallback: style.titleColor ?? accent)
                    }
                    Toggle("Custom corner radius", isOn: Binding(
                        get: { style.cornerRadius != nil },
                        set: { style.cornerRadius = $0 ? (style.cornerRadius ?? 10) : nil }
                    ))
                    if style.cornerRadius != nil {
                        LabeledSlider(title: "Radius", value: Binding(get: { style.cornerRadius ?? 10 }, set: { style.cornerRadius = $0 }),
                                      range: 0...28, format: .points)
                    }
                }
                .padding(4)
            }

            HStack {
                Button("Apply to All Cards", action: onApplyToAll)
                Spacer()
                Button("Reset") { style = CardStyle() }
                    .disabled(style.isDefault)
            }
        }
        .padding(16)
        .frame(width: 330)
    }
}

private struct OptionalColorRow: View {
    let title: String
    @Binding var color: RGBAColor?
    let fallback: RGBAColor

    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(get: { color != nil }, set: { color = $0 ? (color ?? fallback) : nil }))
            Spacer()
            if color != nil {
                ColorPicker(title, selection: Binding(get: { (color ?? fallback).color }, set: { color = RGBAColor($0) }),
                            supportsOpacity: true)
                    .labelsHidden()
            }
        }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
