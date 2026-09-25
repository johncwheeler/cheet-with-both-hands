import Foundation

/// Downloads pages for URL imports and the Cheatography browser.
enum WebFetcher {
    /// Browser-compatible, but identifies the app.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) CheetWithBothHands/1.0"

    struct Page: Sendable {
        var text: String
        var url: URL
        var mimeType: String?
        var byteCount: Int
    }

    enum FetchError: LocalizedError {
        case invalidURL
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: "That doesn't look like a web address."
            case .http(let code): "The server answered \(code) (\(HTTPURLResponse.localizedString(forStatusCode: code)))."
            }
        }
    }

    /// Accepts "example.com/page" as well as full URLs.
    static func normalizedURL(_ string: String) -> URL? {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host != nil else {
            return nil
        }
        return url
    }

    static func fetch(_ url: URL) async throws -> Page {
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html, text/markdown, text/csv, application/json, text/plain;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.http(http.statusCode)
        }
        var encoding = String.Encoding.utf8
        if let name = response.textEncodingName {
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId {
                encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            }
        }
        let text = String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
        return Page(text: text, url: response.url ?? url, mimeType: response.mimeType, byteCount: data.count)
    }

    /// Canonical form for "is this page already in the library?" comparisons.
    static func libraryKey(_ string: String?) -> String? {
        guard let string, let components = URLComponents(string: string), let host = components.host else { return nil }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        let bareHost = host.lowercased().hasPrefix("www.") ? String(host.lowercased().dropFirst(4)) : host.lowercased()
        return bareHost + path.lowercased()
    }
}
