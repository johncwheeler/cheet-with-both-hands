import Foundation

/// JSON → cheet. Accepts this app's own cheet export, or generic tabular JSON:
/// - `[{…}, {…}]` array of objects → table (keys become headers)
/// - `[[…], […]]` array of arrays → table
/// - `{"key": "value", …}` → two-column table
/// - `{"Section": <any of the above>, …}` → one section per key
public enum JSONImporter {
    public enum Output {
        case cheet(Cheet)
        case events([OutlineEvent])
    }

    public static func parse(_ text: String) throws -> Output {
        guard let data = text.data(using: .utf8) else { throw ImportError.invalidJSON("Not UTF-8 text") }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ImportError.invalidJSON(error.localizedDescription)
        }

        // Our own format: a cheet object with sections.
        if let dict = object as? [String: Any], dict["sections"] is [Any],
           let cheet = try? JSONDecoder.cheet.decode(Cheet.self, from: data) {
            return .cheet(cheet)
        }

        let orderHint = KeyOrder(source: text)
        var events: [OutlineEvent] = []

        if let dict = object as? [String: Any] {
            let keys = orderHint.sorted(Array(dict.keys))
            if dict.values.allSatisfy(isScalar) {
                let rows = keys.map { [InlineMarkdown.escape($0), scalarText(dict[$0]!)] }
                events.append(.block(.table(CheetTable(headers: nil, rows: rows))))
            } else {
                for key in keys {
                    let value = dict[key]!
                    events.append(.heading(level: 2, text: InlineMarkdown.escape(key)))
                    if isScalar(value) {
                        events.append(.block(.text(scalarText(value))))
                    } else {
                        events.append(contentsOf: blocks(for: value, order: orderHint))
                    }
                }
            }
        } else {
            events.append(contentsOf: blocks(for: object, order: orderHint))
        }
        return .events(events)
    }

    private static func blocks(for value: Any, order: KeyOrder) -> [OutlineEvent] {
        if let array = value as? [Any] {
            if array.allSatisfy(isScalar) {
                return [.block(.list(ListBlock(items: array.map(scalarText))))]
            }
            if let objects = array as? [[String: Any]] {
                var keys: [String] = []
                for obj in objects { for k in obj.keys where !keys.contains(k) { keys.append(k) } }
                keys = order.sorted(keys)
                let rows = objects.map { obj in keys.map { obj[$0].map(scalarText) ?? "" } }
                return [.block(.table(CheetTable(headers: keys.map(InlineMarkdown.escape), rows: rows)))]
            }
            if let arrays = array as? [[Any]] {
                let rows = arrays.map { $0.map(scalarText) }
                let columns = rows.map(\.count).max() ?? 0
                if DelimitedImporter.looksLikeHeader(rows, columns: columns) {
                    return [.block(.table(CheetTable(headers: rows[0], rows: Array(rows.dropFirst()))))]
                }
                return [.block(.table(CheetTable(headers: nil, rows: rows)))]
            }
        }
        if let dict = value as? [String: Any] {
            let keys = order.sorted(Array(dict.keys))
            let rows = keys.map { [InlineMarkdown.escape($0), scalarText(dict[$0]!)] }
            return [.block(.table(CheetTable(headers: nil, rows: rows)))]
        }
        return [.block(.text(scalarText(value)))]
    }

    private static func isScalar(_ value: Any) -> Bool {
        !(value is [Any]) && !(value is [String: Any])
    }

    private static func scalarText(_ value: Any) -> String {
        switch value {
        case let s as String: return InlineMarkdown.escape(s)
        case is NSNull: return ""
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        case let array as [Any]: return array.map(scalarText).joined(separator: ", ")
        case let dict as [String: Any]:
            return dict.keys.sorted().map { "\($0): \(scalarText(dict[$0]!))" }.joined(separator: "; ")
        default: return InlineMarkdown.escape("\(value)")
        }
    }

    /// `JSONSerialization` loses key order, so recover it from where each key first appears in the source.
    struct KeyOrder {
        let source: String
        func sorted(_ keys: [String]) -> [String] {
            let positions = Dictionary(uniqueKeysWithValues: keys.map { key -> (String, Int) in
                let needle = "\"\(key)\""
                if let range = source.range(of: needle) {
                    return (key, source.distance(from: source.startIndex, to: range.lowerBound))
                }
                return (key, Int.max)
            })
            return keys.sorted { (positions[$0]!, $0) < (positions[$1]!, $1) }
        }
    }
}
