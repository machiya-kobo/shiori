import Foundation

/// "wiki" as a word in a search: Wikipedia's article first.
/// search-core.js's `wikiQuery` / `wikipediaArticle` /
/// `wikiFirst` are its twins, with the same tests.
public enum WikipediaFirst {
    /// A Wikipedia article among web results.
    public struct Article: Equatable, Sendable {
        public var url: String
        public var title: String
        public var lang: String
        public var index: Int
    }

    /// The query without "wiki" or "wikipedia" when one of its words is
    /// that, to find the article by; nil when neither is, or nothing's left.
    public static func query(_ text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let isWiki = { (w: String) in ["wiki", "wikipedia"].contains(w.lowercased()) }
        guard words.contains(where: isWiki) else { return nil }
        let rest = words.filter { !isWiki($0) }.joined(separator: " ")
        return rest.isEmpty ? nil : rest
    }

    /// The first article among `results`: `<lang>.wikipedia.org/wiki/<Title>`
    /// (a mobile `.m.` host too), not the portal, the main page or a
    /// namespace page. Namespaces are translated ("Faili:Jauza_Gemini.jpg"),
    /// so they're known by shape: one word, a colon, then no space
    /// ("Talk:Gemini"; "Batman:_Year_One" is an article). One in `languages`
    /// (the reader's, e.g. ["en-US"]) comes before one in any other.
    public static func article(in results: [WebResult], languages: [String] = []) -> Article? {
        var articles: [Article] = []
        for (i, result) in results.enumerated() {
            guard let u = URLComponents(string: result.url), u.query == nil,
                let host = u.host?.lowercased(), host.hasSuffix(".wikipedia.org")
            else { continue }
            let parts = host.dropLast(".wikipedia.org".count).split(separator: ".")
            guard let lang = parts.first.map(String.init), lang != "www",
                parts.count == 1 || (parts.count == 2 && parts[1] == "m"),
                lang.allSatisfy({ $0.isLetter || $0 == "-" })
            else { continue }
            let path = u.percentEncodedPath
            guard path.hasPrefix("/wiki/") else { continue }
            let encoded = String(path.dropFirst("/wiki/".count))
            guard !encoded.isEmpty, !encoded.contains("/"), let raw = encoded.removingPercentEncoding,
                !notArticle(raw)
            else { continue }
            articles.append(Article(url: "https://\(lang).wikipedia.org/wiki/\(encoded)",
                                    title: raw.replacingOccurrences(of: "_", with: " "), lang: lang, index: i))
        }
        let wanted = languages.map { $0.lowercased().split(separator: "-").first.map(String.init) ?? "" }
        return articles.first { wanted.contains($0.lang) } ?? articles.first
    }

    /// Whether `article` is in one of the reader's `languages`.
    public static func inReadersLanguage(_ article: Article, languages: [String]) -> Bool {
        languages.contains { $0.lowercased().split(separator: "-").first.map(String.init) == article.lang }
    }

    /// The results with the article first: moved up when it's there, else
    /// `found` (the result it came from, in another search) put in front.
    public static func ordered(_ results: [WebResult], article: Article?, found: WebResult? = nil) -> [WebResult] {
        guard let article else { return results }
        var list = results
        if let at = list.firstIndex(where: { self.article(in: [$0])?.url == article.url }) {
            let first = list.remove(at: at)
            return [first] + list
        }
        let first = found ?? WebResult(url: article.url, title: "\(article.title) - Wikipedia", content: "",
                                       engines: [], thumbnail: nil, published: nil)
        return [first] + list
    }

    private static func notArticle(_ title: String) -> Bool {
        if title == "Main_Page" { return true }
        guard let colon = title.firstIndex(of: ":") else { return false }
        let prefix = title[..<colon]
        let after = title[title.index(after: colon)...]
        return !prefix.isEmpty && !prefix.contains("_") && after.first != "_"
    }
}
