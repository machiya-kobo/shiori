import Foundation

/// Files from the folders Hister watches (its `indexer.directories`):
/// documents of type `local`, with a `file://` address, served by Hister
/// itself (`/api/file`). They show only on the Files pill: every other
/// Hister query leaves them out (`SearchText.forHister`). search-core.js's
/// `isLocalFile` / `localFileURL` / `filesQuery` are the twins, with the
/// same tests.
public enum LocalFiles {
    /// Hister's filter for watched files.
    public static let term = "type:local"
    /// Every other query's: never the files.
    public static let exclusion = "-type:local"

    /// A query that asks for files: one with `type:local` among its words.
    public static func asked(in text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).contains { $0 == term }
    }

    /// The Files pill's query from what was typed (`*` for none). The term
    /// leads, so the last typed word still becomes a prefix.
    public static func query(_ typed: String) -> String {
        let words = typed.trimmingCharacters(in: .whitespaces)
        return "\(term) \(words.isEmpty ? "*" : words)"
    }

    /// A watched file, known by its address (Hister's `type: 1`, domain
    /// `local`).
    public static func isLocalFile(_ url: String) -> Bool {
        url.lowercased().hasPrefix("file://")
    }

    /// Hister's served copy of a file: `/api/file?id=<its address>` (the
    /// document's id on a server without users).
    public static func servedURL(for url: String, server: URL) -> URL? {
        guard isLocalFile(url) else { return nil }
        var components = URLComponents(url: server.appending(path: "api/file"), resolvingAgainstBaseURL: false)
        components?.setQueryItems([URLQueryItem(name: "id", value: url)])
        return components?.url
    }

    /// Where a file lives, for its row: the path without `file://`.
    public static func path(of url: String) -> String {
        guard isLocalFile(url) else { return url }
        let rest = String(url.dropFirst("file://".count))
        return rest.removingPercentEncoding ?? rest
    }
}
