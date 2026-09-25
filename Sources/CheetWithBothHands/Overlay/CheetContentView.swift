import AppKit
import CheetCore
import SwiftUI

/// Everything a cell needs to draw itself, derived once per render from the effective appearance.
struct RenderStyle: Equatable {
    var appearance: Appearance
    var scale: CGFloat = 1
    var tokens: [String] = []
    var copyOnClick = true

    var fontSize: CGFloat { CGFloat(appearance.fontSize) * scale }
    var accent: Color { appearance.accent.color }
    var highlight: Color { appearance.accent.color.opacity(0.38) }
    var rowSpacing: CGFloat { CGFloat(appearance.density.rowSpacing) * scale }

    func font(_ relative: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
        appearance.font(size: fontSize * relative, weight: weight)
    }
}

/// Renders a cheet's sections as cards that flow around each other's sizes.
/// Pass an `editor` to turn on layout editing (hide, delete, resize, restyle, reorder).
struct CheetContentView: View {
    let sections: [CheetSection]
    let style: RenderStyle
    var maxColumns: Int? = nil
    var collapsed: Set<UUID> = []
    var editor: LayoutEditing? = nil
    var onToggleSection: ((UUID) -> Void)? = nil
    var onCopy: ((String) -> Void)? = nil

    @State private var containerWidth: CGFloat = 900

    var body: some View {
        let metrics = GridMetrics.make(width: containerWidth, style: style, maxColumns: maxColumns)
        let live = editor?.editState.liveResize
        MasonryLayout(style: style, maxColumns: maxColumns) {
            ForEach(sections) { section in
                let width = live?.id == section.id ? live!.width : section.layout.width
                CardView(
                    section: section,
                    style: style,
                    isCollapsed: collapsed.contains(section.id) && style.tokens.isEmpty,
                    metrics: metrics,
                    editor: editor,
                    onToggle: { onToggleSection?(section.id) },
                    onCopy: onCopy
                )
                .layoutValue(key: CardSizingKey.self, value: CardSizing(width: width, prefersFullWidth: section.prefersFullWidth))
            }
        }
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.86), value: live)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { containerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { containerWidth = proxy.size.width }
            }
        )
    }
}

struct BlockView: View {
    let block: CheetBlock
    let style: RenderStyle
    let onCopy: ((String) -> Void)?

    var body: some View {
        switch block {
        case .heading(let text):
            Text(InlineRenderer.shared.render(text, style: style, relative: 0.9, weight: .semibold))
                .font(style.font(0.9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4 * style.scale)

        case .table(let table):
            TableBlockView(table: table, style: style, onCopy: onCopy)

        case .list(let list):
            VStack(alignment: .leading, spacing: style.rowSpacing + 1) {
                ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                    let (depth, text) = ListBlock.depthAndText(item)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(list.ordered && depth == 0 ? "\(index + 1)." : (depth == 0 ? "•" : "◦"))
                            .font(style.font(0.9))
                            .foregroundStyle(style.accent.opacity(0.8))
                            .monospacedDigit()
                        CellView(text: text, style: style, onCopy: onCopy)
                    }
                    .padding(.leading, CGFloat(depth) * 14 * style.scale)
                }
            }

        case .text(let text):
            CellView(text: text, style: style, secondary: true, allowKeycaps: false, onCopy: onCopy)

        case .code(let code):
            CodeBlockView(code: code, style: style, onCopy: onCopy)

        case .image(let image):
            ImageBlockView(image: image, style: style)
        }
    }
}

struct TableBlockView: View {
    let table: CheetTable
    let style: RenderStyle
    let onCopy: ((String) -> Void)?

    var body: some View {
        let columns = max(table.columnCount, 1)
        let rows = table.normalizedRows
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14 * style.scale, verticalSpacing: style.rowSpacing) {
            if let headers = table.headers {
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        Text(InlineRenderer.shared.render(column < headers.count ? headers[column] : "", style: style, relative: 0.72, weight: .semibold))
                            .font(style.font(0.72, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if style.appearance.rowSeparators, index > 0 || table.headers != nil {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 0.5)
                        .gridCellUnsizedAxes(.horizontal)
                }
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        CellView(
                            text: row[column],
                            style: style,
                            emphasized: column == 0 && columns > 1,
                            expand: column == columns - 1,
                            onCopy: onCopy
                        )
                        .gridColumnAlignment(.leading)
                    }
                }
            }
        }
    }
}

/// A single cell: keycaps if it reads as a shortcut, otherwise inline-styled text. Click to copy.
struct CellView: View {
    let text: String
    let style: RenderStyle
    var emphasized = false
    /// Fill the remaining width (last column only, so key columns stay tight).
    var expand = true
    var secondary = false
    var allowKeycaps = true
    let onCopy: ((String) -> Void)?

    @State private var isHovering = false

    var body: some View {
        content
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(isHovering && style.copyOnClick && !text.isEmpty ? 0.09 : 0))
            )
            .padding(.horizontal, -3)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .if(style.copyOnClick && !text.isEmpty) { view in
                view.onTapGesture { onCopy?(InlineMarkdown.plainText(text)) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image = InlineMarkdown.soleImage(text) {
            RemoteImage(source: image.source, maxHeight: 120 * style.scale, backdrop: style.appearance.imageBackdrop)
                .help(image.alt)
        } else if allowKeycaps, style.appearance.keycaps, let elements = InlineRenderer.shared.keycaps(text) {
            KeycapSequence(elements: elements, style: style)
        } else {
            let label = Text(InlineRenderer.shared.render(text, style: style, weight: emphasized ? .medium : .regular))
                .font(style.font(1, weight: emphasized ? .medium : .regular))
                .foregroundStyle(secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: expand ? .infinity : nil, alignment: .leading)
            if style.copyOnClick {
                label
            } else {
                label.textSelection(.enabled)
            }
        }
    }
}

struct KeycapSequence: View {
    let elements: [KeyCapParser.Element]
    let style: RenderStyle

    var body: some View {
        FlowLayout(spacing: 4 * style.scale, lineSpacing: 3 * style.scale) {
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                switch element {
                case .chord(let keys):
                    chord(keys)
                case .separator(let text):
                    Text(text)
                        .font(style.font(0.8))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func chord(_ keys: [String]) -> some View {
        let display = KeyCapParser.display(keys, style: style.appearance.modifierStyle)
        let symbolic = keys.contains { ["⌘", "⌥", "⌃", "⇧"].contains($0) }
            && !keys.contains { $0.count > 1 && KeyCapParser.isModifier($0) }
        if style.appearance.modifierStyle == .symbols || (style.appearance.modifierStyle == .asWritten && symbolic) {
            Keycap(label: KeyCapParser.compactSymbolLabel(display), style: style)
        } else {
            HStack(spacing: 2) {
                ForEach(Array(display.enumerated()), id: \.offset) { index, key in
                    if index > 0 {
                        Text("+").font(style.font(0.75)).foregroundStyle(.tertiary)
                    }
                    Keycap(label: key, style: style)
                }
            }
        }
    }
}

struct Keycap: View {
    let label: String
    let style: RenderStyle

    var body: some View {
        Text(label)
            .font(.system(size: style.fontSize * 0.9, weight: .medium, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 6 * style.scale)
            .padding(.vertical, 1.5 * style.scale)
            .frame(minWidth: 20 * style.scale)
            .background(
                RoundedRectangle(cornerRadius: 5 * style.scale, style: .continuous)
                    .fill(Color.primary.opacity(0.11))
                    .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5 * style.scale, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5)
            )
    }
}

struct CodeBlockView: View {
    let code: CodeBlock
    let style: RenderStyle
    let onCopy: ((String) -> Void)?
    @State private var isHovering = false

    var body: some View {
        Text(code.code)
            .font(.system(size: style.fontSize * 0.9, design: .monospaced))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8 * style.scale)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovering && style.copyOnClick ? 0.12 : 0.07))
            )
            .overlay(alignment: .topTrailing) {
                if isHovering, style.copyOnClick {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: style.fontSize * 0.75))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .if(style.copyOnClick) { view in view.onTapGesture { onCopy?(code.code) } }
    }
}
