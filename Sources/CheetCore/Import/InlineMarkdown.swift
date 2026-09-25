import Foundation

/// Helpers for the inline-Markdown strings stored in cheet cells.
public enum InlineMarkdown {
    /// Escapes characters that would otherwise be interpreted as inline Markdown.
    public static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "\\", "`", "*", "_", "[", "]":
                out.append("\\")
                out.append(ch)
            default:
                out.append(ch)
            }
        }
        return out
    }

    /// Wraps text in a code span, choosing a backtick fence that doesn't collide with the content.
    public static func codeSpan(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var longestRun = 0, run = 0
        for ch in trimmed {
            if ch == "`" { run += 1; longestRun = max(longestRun, run) } else { run = 0 }
        }
        let fence = String(repeating: "`", count: longestRun + 1)
        let pad = (trimmed.hasPrefix("`") || trimmed.hasSuffix("`")) ? " " : ""
        return fence + pad + trimmed + pad + fence
    }

    static let parsingOptions = AttributedString.MarkdownParsingOptions(
        allowsExtendedAttributes: true,
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
    )

    /// Parses inline Markdown, including the `script` (super/subscript) attribute.
    public static func attributed(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, including: \.cheet, options: parsingOptions)) ?? AttributedString(markdown)
    }

    /// Plain text with inline Markdown syntax removed (for copying and searching).
    /// Superscripts and subscripts become Unicode where possible (x², aₙ), else ^(…) / _(…).
    public static func plainText(_ markdown: String) -> String {
        guard markdown.contains(where: { "`*_[]\\<&".contains($0) }) else { return markdown }
        let attributed = attributed(markdown)
        var out = ""
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            if let script = run[ScriptAttribute.self] {
                out += MathScript.flatten(text, raised: script > 0)
            } else {
                out += text
            }
        }
        return out
    }

    /// `![alt](source "title")`
    public static func imageMarkdown(alt: String, source: String, title: String? = nil) -> String {
        let url = source.replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
        let titlePart = title.map { " \"\($0.replacingOccurrences(of: "\"", with: "'"))\"" } ?? ""
        return "![\(escape(alt))](\(url)\(titlePart))"
    }

    private static let soleImagePattern = try! NSRegularExpression(
        pattern: #"^\[?!\[((?:\\.|[^\]])*)\]\((\S+?)(?:\s+"([^"]*)")?\)(?:\]\(\S+\))?$"#
    )

    /// If the Markdown is nothing but one image (possibly wrapped in a link), its parts.
    public static func soleImage(_ markdown: String) -> (alt: String, source: String, title: String?)? {
        let text = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("!") || text.hasPrefix("[!"),
              let match = soleImagePattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let altRange = Range(match.range(at: 1), in: text),
              let sourceRange = Range(match.range(at: 2), in: text) else { return nil }
        let title = Range(match.range(at: 3), in: text).map { String(text[$0]) }
        return (plainText(String(text[altRange])), String(text[sourceRange]), title)
    }

    /// Collapses runs of whitespace (including newlines) into single spaces.
    public static func collapseWhitespace(_ text: String) -> String {
        var out = ""
        var lastWasSpace = false
        for ch in text {
            if ch.isWhitespace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        return out
    }

    /// Wraps content with a delimiter (e.g. `**`), keeping surrounding whitespace outside the markers.
    static func wrap(_ content: String, with marker: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return content }
        let leading = content.prefix { $0 == " " }
        let trailing = String(content.reversed().prefix { $0 == " " })
        return leading + marker + trimmed + marker + trailing
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Case- and diacritic-insensitive form used for searching.
    public var searchFolded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
