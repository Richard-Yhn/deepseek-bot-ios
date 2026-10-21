// DeepSeek Bot for iOS — Apache-2.0
// A DSH host is addressed by the login URL it prints:
//   http://127.0.0.1:3080/?token=…
// Opening that URL sets a signed cookie (30 days, bound to that authority); every
// `/api/bot` call after it is authenticated by the cookie alone.
// The phone keeps the origin and the token apart, so the token is only ever sent once.

import Foundation

struct HostAddress: Equatable, Codable {
    /// Scheme, host and port only — no path, no query.
    var origin: String
    /// The `?token=` value from the login URL, when the user pasted one.
    var token: String?

    static let defaultPort = 3080

    var baseURL: URL? {
        URL(string: origin)
    }

    var loginURL: URL? {
        guard var components = URLComponents(string: origin) else { return nil }
        guard let token, !token.isEmpty else { return components.url }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    var displayHost: String {
        guard let url = baseURL else { return origin }
        if let port = url.port { return "\(url.host ?? origin):\(port)" }
        return url.host ?? origin
    }

    /// People paste the token in whatever shape the host printed it. `?token=abc`,
    /// `token=abc` and `abc` all mean the same thing here.
    static func normalizeToken(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("?") || text.hasPrefix("&") { text.removeFirst() }
        if let range = text.range(of: "token=", options: .backwards) {
            text = String(text[range.upperBound...])
        }
        if let amp = text.firstIndex(of: "&") { text = String(text[..<amp]) }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        return text.isEmpty ? nil : text
    }

    /// Accepts what people actually paste: a full login URL, a bare `ip:port`,
    /// or `ip` (port assumed to be DSH Web's default). A separate token field wins
    /// over one already inside the pasted URL.
    static func parse(_ raw: String, token extraToken: String = "") -> HostAddress? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard var components = URLComponents(string: text),
              let host = components.host,
              !host.isEmpty
        else { return nil }

        if components.port == nil { components.port = defaultPort }

        var token = normalizeToken(extraToken)
        if let fromURL = components.queryItems?.first(where: { $0.name == "token" || $0.name == "t" })?.value,
           let cleaned = normalizeToken(fromURL) {
            token = cleaned
        }

        components.query = nil
        components.path = ""
        components.fragment = nil
        components.user = nil
        components.password = nil
        guard let origin = components.string else { return nil }

        return HostAddress(origin: origin, token: token)
    }
}
