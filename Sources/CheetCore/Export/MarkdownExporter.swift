import Foundation

/// Serialises a cheet back to Markdown. Used for editing and export; re-importing the output
/// reproduces the same structure.
public enum MarkdownExporter {
    public static func markdown(for cheet: Cheet) -> String {
        var out: [String] = ["# \(cheet.title)"]
        for section in cheet.sections {
            if !section.title.isEmpty { out.append("## \(section.title)") }
            for block in section.blocks {
                out.append(markdown(for: block))
            }
        }
        return out.joined(separator: "\n\n") + "\n"
    }

    static func markdown(for block: CheetBlock) -> String {
        switch block {
        case .heading(let text):
            return "### \(text)"
        case .text(let text):
            return text
        case .code(let code):
            let fence = code.code.contains("```") ? "~~~~" : "```"
            return "\(fence)\(code.language ?? "")\n\(code.code)\n\(fence)"
        case .image(let image):
            return InlineMarkdown.imageMarkdown(alt: image.alt, source: image.source, title: image.caption)
        case .list(let list):
            return list.items.enumerated().map { index, item in
                let (depth, text) = ListBlock.depthAndText(item)
                let marker = list.ordered && depth == 0 ? "\(index + 1)." : "-"
                return String(repeating: "  ", count: depth) + "\(marker) \(text)"
            }.joined(separator: "\n")
        case .table(let table):
            let columns = max(table.columnCount, 1)
            let headers = table.headers.map { pad($0, to: columns) } ?? Array(repeating: "", count: columns)
            var lines = [row(headers), row(Array(repeating: "---", count: columns))]
            lines += table.normalizedRows.map { row(pad($0, to: columns)) }
            return lines.joined(separator: "\n")
        }
    }

    private static func pad(_ cells: [String], to count: Int) -> [String] {
        cells.count >= count ? cells : cells + Array(repeating: "", count: count - cells.count)
    }

    private static func row(_ cells: [String]) -> String {
        "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: " | ") + " |"
    }
}
