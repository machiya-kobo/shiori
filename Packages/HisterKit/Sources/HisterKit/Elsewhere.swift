import Foundation

/// A web page elsewhere: its copies on the Wayback Machine and archive.is,
/// and the same page through a privacy front end (Redlib for Reddit,
/// Invidious for YouTube…) when the build names one. Links only: Shiori
/// never fetches any of them. `S.cachedURL` / `S.archiveURL` build the
/// same archive links on the search page.
public enum Elsewhere {
    /// The page on the Wayback Machine (its newest snapshot).
    public static func wayback(_ url: String) -> URL? {
        guard isWeb(url) else { return nil }
        return URL(string: "https://web.archive.org/web/" + url)
    }

    /// The page's newest snapshot on archive.is.
    public static func archiveToday(_ url: String) -> URL? {
        guard isWeb(url) else { return nil }
        return URL(string: "https://archive.is/newest/" + url)
    }

    /// A privacy front end: its name, and the sites it stands in for.
    public struct Frontend: Sendable, Equatable {
        public let key: String
        public let name: String
        let hosts: Set<String>
        let rewrite: @Sendable (URLComponents) -> (path: String, query: String?)?

        public static func == (a: Frontend, b: Frontend) -> Bool { a.key == b.key }
    }

    /// The front ends Shiori knows, keyed as `SHIORI_FRONTENDS` names them.
    public static let known: [Frontend] = [
        Frontend(key: "redlib", name: "Redlib",
                 hosts: ["reddit.com", "www.reddit.com", "old.reddit.com", "new.reddit.com", "np.reddit.com", "m.reddit.com", "redd.it"]) { c in
            // redd.it/<id> is a post's short link.
            if c.host?.lowercased() == "redd.it" {
                let id = c.path.split(separator: "/").first.map(String.init) ?? ""
                return id.isEmpty ? nil : ("/comments/" + id, nil)
            }
            return (c.path, c.percentEncodedQuery)
        },
        Frontend(key: "invidious", name: "Invidious", hosts: youTube, rewrite: youTubeRewrite),
        Frontend(key: "piped", name: "Piped", hosts: youTube, rewrite: youTubeRewrite),
        Frontend(key: "nitter", name: "Nitter",
                 hosts: ["twitter.com", "www.twitter.com", "mobile.twitter.com", "x.com", "www.x.com", "mobile.x.com"]) { c in
            (c.path, c.percentEncodedQuery)
        },
        Frontend(key: "scribe", name: "Scribe", hosts: ["medium.com", "www.medium.com"]) { c in
            (c.path, c.percentEncodedQuery)
        },
        Frontend(key: "rimgo", name: "rimgo", hosts: ["imgur.com", "www.imgur.com", "i.imgur.com", "m.imgur.com"]) { c in
            (c.path, c.percentEncodedQuery)
        },
        Frontend(key: "libremdb", name: "libremdb", hosts: ["imdb.com", "www.imdb.com", "m.imdb.com"]) { c in
            (c.path, c.percentEncodedQuery)
        },
        Frontend(key: "breezewiki", name: "BreezeWiki", hosts: []) { c in
            // <wiki>.fandom.com/wiki/Page → /<wiki>/wiki/Page.
            guard let host = c.host?.lowercased(), host.hasSuffix(".fandom.com") else { return nil }
            let wiki = String(host.dropLast(".fandom.com".count))
            guard !wiki.isEmpty, !wiki.contains("."), wiki != "www" else { return nil }
            return ("/" + wiki + c.path, c.percentEncodedQuery)
        },
    ]

    static let youTube: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "www.youtube-nocookie.com", "youtube-nocookie.com"]

    /// youtu.be/<id> and /shorts/<id> become /watch?v=<id> (a start time kept).
    @Sendable static func youTubeRewrite(_ c: URLComponents) -> (path: String, query: String?)? {
        let parts = c.path.split(separator: "/").map(String.init)
        var id: String?
        if c.host?.lowercased() == "youtu.be" {
            id = parts.first
        } else if parts.count >= 2, parts[0] == "shorts" || parts[0] == "embed" || parts[0] == "live" {
            id = parts[1]
        }
        guard let id else { return (c.path, c.percentEncodedQuery) }
        guard !id.isEmpty else { return nil }
        let start = c.queryItems?.first { $0.name == "t" || $0.name == "start" }?.value
        var items = [URLQueryItem(name: "v", value: id)]
        if let start { items.append(URLQueryItem(name: "t", value: start)) }
        var q = URLComponents()
        q.queryItems = items
        return ("/watch", q.percentEncodedQuery)
    }

    /// The configured front ends from `SHIORI_FRONTENDS` ("redlib=https://…,
    /// invidious=https://…"): known names with an http(s) address; the rest
    /// is ignored.
    public static func instances(from setting: String) -> [(frontend: Frontend, base: URL)] {
        setting.split(separator: ",").compactMap { entry in
            let pair = entry.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, let frontend = known.first(where: { $0.key == pair[0].lowercased() }),
                  let base = URL(string: pair[1]), ["http", "https"].contains(base.scheme?.lowercased() ?? ""), base.host != nil
            else { return nil }
            return (frontend, base)
        }
    }

    /// The page through each configured front end that stands in for its
    /// site, by the front end's name ("Redlib" → the page on Redlib).
    public static func frontends(for url: String, instances: [(frontend: Frontend, base: URL)]) -> [(name: String, url: URL)] {
        guard isWeb(url), let c = URLComponents(string: url), let host = c.host?.lowercased() else { return [] }
        return instances.compactMap { frontend, base in
            let serves = frontend.hosts.contains(host) || (frontend.key == "breezewiki" && host.hasSuffix(".fandom.com"))
            guard serves, let (path, query) = frontend.rewrite(c),
                  var out = URLComponents(url: base, resolvingAgainstBaseURL: false)
            else { return nil }
            let basePath = out.path.hasSuffix("/") ? String(out.path.dropLast()) : out.path
            out.path = basePath + (path.isEmpty ? "/" : path)
            out.percentEncodedQuery = query
            out.fragment = c.fragment
            return out.url.map { (frontend.name, $0) }
        }
    }

    static func isWeb(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasPrefix("https://") || lower.hasPrefix("http://")
    }
}
