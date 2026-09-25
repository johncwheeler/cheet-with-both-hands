import AppKit
import CheetCore
import SwiftUI

/// Caches parsed inline Markdown and keycap detection per cell string, and applies search highlights.
@MainActor
final class InlineRenderer {
    static let shared = InlineRenderer()

    private var attributedCache: [String: AttributedString] = [:]
    private var keycapCache: [String: [KeyCapParser.Element]?] = [:]


    func attributed(_ markdown: String) -> AttributedString {
        if let cached = attributedCache[markdown] { return cached }
        var attributed = InlineMarkdown.attributed(markdown)
        let codeRanges = attributed.runs
            .filter { $0.inlinePresentationIntent?.contains(.code) == true }
            .map(\.range)
        for range in codeRanges {
            attributed[range].backgroundColor = Color.primary.opacity(0.10)
        }
        if attributedCache.count > 8000 { attributedCache.removeAll(keepingCapacity: true) }
        attributedCache[markdown] = attributed
        return attributed
    }

    /// Inline Markdown styled for a cell: search highlights, plus superscripts/subscripts drawn
    /// smaller and shifted off the baseline in the cell's own font.
    func render(_ markdown: String, style: RenderStyle, relative: CGFloat = 1, weight: Font.Weight = .regular) -> AttributedString {
        var attributed = render(markdown, highlighting: style.tokens, color: style.highlight)
        guard markdown.contains("](script:") else { return attributed }
        let size = style.fontSize * relative
        let scripts = attributed.runs.compactMap { run in run[ScriptAttribute.self].map { (run.range, $0) } }
        for (range, value) in scripts {
            attributed[range].font = style.font(relative * 0.7, weight: weight)
            attributed[range].baselineOffset = value > 0 ? size * 0.36 : -size * 0.14
        }
        return attributed
    }

    func render(_ markdown: String, highlighting tokens: [String], color: Color) -> AttributedString {
        var attributed = self.attributed(markdown)
        guard !tokens.isEmpty else { return attributed }
        for token in tokens {
            var searchStart = attributed.startIndex
            while searchStart < attributed.endIndex,
                  let range = attributed[searchStart...].range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) {
                attributed[range].backgroundColor = color
                searchStart = range.upperBound
            }
        }
        return attributed
    }

    func keycaps(_ text: String) -> [KeyCapParser.Element]? {
        if let cached = keycapCache[text] { return cached }
        let parsed = KeyCapParser.parse(text)
        if keycapCache.count > 8000 { keycapCache.removeAll(keepingCapacity: true) }
        keycapCache[text] = parsed
        return parsed
    }
}
