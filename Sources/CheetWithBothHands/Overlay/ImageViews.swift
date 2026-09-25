import AppKit
import CheetCore
import SwiftUI

/// Loads an image from the cache (or network, once) and shows it at no more than its natural size.
struct RemoteImage: View {
    let source: String
    var maxHeight: CGFloat? = nil
    var backdrop = true

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: max(image.size.width, 1), maxHeight: maxHeight.map { min($0, max(image.size.height, 1)) } ?? max(image.size.height, 1))
                    .padding(backdrop ? 5 : 0)
                    .background {
                        if backdrop {
                            // Diagrams are often dark ink on transparency — keep them legible on dark overlays.
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.93))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else if failed {
                Label("Image unavailable", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: maxHeight.map { min($0 * 1.5, 120) } ?? 120, height: maxHeight.map { min($0, 60) } ?? 60)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: source) {
            if let cached = ImageStore.shared.cached(source) {
                image = cached
                return
            }
            let loaded = await ImageStore.shared.image(for: source)
            image = loaded
            failed = loaded == nil
        }
    }
}

/// An image block in a card: the image, its caption, click to copy, and a context menu.
struct ImageBlockView: View {
    let image: ImageBlock
    let style: RenderStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RemoteImage(source: image.source, backdrop: style.appearance.imageBackdrop)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(image.alt)
                .contentShape(Rectangle())
                .if(style.copyOnClick) { view in
                    view.onTapGesture { AppController.shared.overlay.copyImage(image.source) }
                }
                .contextMenu {
                    Button("Copy Image") { AppController.shared.overlay.copyImage(image.source) }
                    if !image.isAsset {
                        Button("Copy Image Address") { AppController.shared.overlay.copy(image.source) }
                        if let url = URL(string: image.source) {
                            Button("Open Original") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
            if let caption = image.caption, !caption.isEmpty {
                Text(InlineRenderer.shared.render(caption, style: style, relative: 0.85))
                    .font(style.font(0.85))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
