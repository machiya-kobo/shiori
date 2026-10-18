import Foundation

/// One item under several addresses: Hister holds a video under each address
/// it was seen at, and the web finds your page under its mobile host.
/// `S.itemKey`, `S.uniqueItems` and `S.foldMine` in search-core.js are the
/// twins, on scripts/same-item-cases.json.
public enum SameItem {
    /// A host's labels that mean "the mobile site": m.example.com, en.m.wikipedia.org.
    static let mobileLabels: Set<String> = ["m", "mobile"]

    /// One key for one item, whatever address it came under: no scheme,
    /// `www.`, fragment, tracking tag, port or trailing slash, the query in
    /// order of names, a site's mobile host taken for the site, and a YouTube
    /// video known by its id alone (a start time, a playlist or a share tag
    /// is the same video).
    public static func key(_ raw: String) -> String {
        guard let parts = URLComponents(string: raw), let found = parts.host?.lowercased(), !found.isEmpty else { return raw }
        if let video = youTubeVideo(parts, host: found) { return "youtube.com/watch?v=" + video }
        let labels = found.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var host = labels.enumerated()
            .filter { !(mobileLabels.contains($0.element) && $0.offset < labels.count - 2) }
            .map(\.element).joined(separator: ".")
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let items = (parts.queryItems ?? []).filter { !isTracking($0.name) }
            .enumerated().sorted { ($0.element.name, $0.offset) < ($1.element.name, $1.offset) }.map(\.element)
        let query = items.isEmpty ? "" : "?" + items.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        return host + path + query
    }

    /// The items once each (`key`), the first kept. `seen` carries over from page to page.
    public static func unique<T>(_ items: [T], seen: inout Set<String>, url: (T) -> String) -> [T] {
        items.filter { seen.insert(key(url($0))).inserted }
    }

    public static func unique<T>(_ items: [T], url: (T) -> String) -> [T] {
        var seen = Set<String>()
        return unique(items, seen: &seen, url: url)
    }

    /// All's web results and your pages as one list where they're the same
    /// item: each web result kept, in order, with the page of yours it is
    /// (`mine`, an index), a later web result for an item already listed
    /// dropped; `rest` is your pages that aren't on the web, to mix in. The
    /// entry is drawn as your page, its title opening the website.
    public struct Fold: Equatable, Sendable {
        public var rows: [(web: Int, mine: Int?)]
        public var rest: [Int]

        public static func == (a: Fold, b: Fold) -> Bool {
            a.rest == b.rest && a.rows.map(\.web) == b.rows.map(\.web) && a.rows.map(\.mine) == b.rows.map(\.mine)
        }
    }

    public static func fold(web: [String], mine: [String]) -> Fold {
        let mineKeys = mine.map(key)
        var taken = Set<Int>()
        var seen = Set<String>()
        var rows: [(web: Int, mine: Int?)] = []
        for (index, url) in web.enumerated() {
            let itemKey = key(url)
            guard seen.insert(itemKey).inserted else { continue }
            let match = mineKeys.indices.first { mineKeys[$0] == itemKey && !taken.contains($0) }
            if let match { taken.insert(match) }
            rows.append((web: index, mine: match))
        }
        return Fold(rows: rows, rest: mine.indices.filter { !taken.contains($0) })
    }

    /// A YouTube address's video id (watch?v=, youtu.be/, /shorts/, /embed/, /live/).
    static func youTubeVideo(_ parts: URLComponents, host: String) -> String? {
        guard Elsewhere.youTube.contains(host) else { return nil }
        let path = parts.path.split(separator: "/").map(String.init)
        let id: String?
        if host == "youtu.be" {
            id = path.first
        } else if path.first == "watch" {
            id = parts.queryItems?.first { $0.name == "v" }?.value
        } else if let first = path.first, ["shorts", "embed", "live"].contains(first), path.count > 1 {
            id = path[1]
        } else {
            id = nil
        }
        guard let id, (6...20).contains(id.count),
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_" || $0 == "-" })
        else { return nil }
        return id
    }

    static func isTracking(_ name: String) -> Bool {
        let lower = name.lowercased()
        return (lower.hasPrefix("utm_") && lower.count > 4) || ["fbclid", "gclid", "mc_cid", "mc_eid", "ref_src"].contains(lower)
    }
}
