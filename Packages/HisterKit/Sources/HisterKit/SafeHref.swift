import Foundation

/// A stored or fetched address (Hister's, Kura's, SearXNG's…) as something
/// to open: http(s) only, else nil. `javascript://example.com/%0Aalert(1)`
/// is a valid URL with a host: only the scheme tells. `S.safeHref` in
/// search-core.js is the twin, with the same tests.
public enum SafeHref {
    public static func url(_ address: String?) -> URL? {
        guard let address else { return nil }
        // As a browser reads it: no tabs or newlines, no leading or trailing
        // spaces and control characters.
        let cleaned = String(address.unicodeScalars.filter { $0 != "\t" && $0 != "\n" && $0 != "\r" })
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !cleaned.isEmpty, let url = URL(string: cleaned),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host() != nil
        else { return nil }
        return url
    }
}
