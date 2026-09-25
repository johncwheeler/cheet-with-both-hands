import CheetCore
import SwiftUI

/// A miniature overlay showing how a cheet will look, over a desktop-like backdrop.
struct CheetPreview<Placeholder: View>: View {
    let cheet: Cheet?
    let appearance: Appearance
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        let look = cheet?.appearance ?? appearance
        ZStack {
            LinearGradient(colors: [Color(red: 0.22, green: 0.26, blue: 0.40), Color(red: 0.45, green: 0.33, blue: 0.36)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Group {
                if let cheet, !cheet.sections.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            Text(cheet.title)
                                .font(look.font(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                        ScrollView {
                            CheetContentView(sections: cheet.visibleSections, style: RenderStyle(appearance: look, scale: 0.92, copyOnClick: false))
                                .padding(14)
                        }
                    }
                    .foregroundStyle(look.textColor?.color ?? Color.primary)
                } else {
                    placeholder()
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(GlassBackground(appearance: look, blending: .withinWindow))
            .environment(\.colorScheme, look.swiftUIScheme ?? .dark)
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Icon + message used for empty previews.
struct PreviewMessage: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
