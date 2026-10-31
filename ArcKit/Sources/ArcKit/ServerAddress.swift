import Foundation

public enum ServerAddress {
    /// Arc's port unless the address says otherwise.
    public static let defaultPort = 8099

    /// Turns what someone typed with a remote into a server's base URL (no trailing slash).
    ///
    /// "192.168.1.20" becomes http://192.168.1.20:8099; "arc.example.com" the same with its name;
    /// an address with a scheme or port keeps them, so "https://arc.example.com" stays on 443.
    /// Paths, queries and fragments are dropped: the API lives at the root. Nil for something
    /// that can't be an address.
    public static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.contains(where: { $0.isWhitespace }) { return nil }
        let lower = text.lowercased()
        let hasScheme = lower.hasPrefix("http://") || lower.hasPrefix("https://")
        if !hasScheme {
            if text.contains("://") { return nil }
            text = "http://" + text
        }
        guard var parts = URLComponents(string: text), let host = parts.host, !host.isEmpty else { return nil }
        if !hasScheme && parts.port == nil { parts.port = defaultPort }
        parts.scheme = parts.scheme?.lowercased()
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        return parts.url
    }

    /// How an address is shown back to people.
    public static func display(_ url: URL) -> String {
        var s = url.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
