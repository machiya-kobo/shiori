import Foundation

/// Hister's own order for All. Hister ranks a page holding the whole phrase
/// first, and a site's home page for a one-word search, but not in a query
/// with any filter, an exclusion such as -label:vault included (v0.20.0 and
/// main), and every query of Shiori's has those (`SearchText.forHister`).
/// So All asks for the words alone too and puts Hister's order first: the
/// filtered query still gives the count, the paging and the rest of the
/// page. search-core.js's `rankedText` / `isOwnPage` / `rankedPages` are
/// its twins, with the same tests.
public enum RankedPages {
    /// The words as Hister ranks them, or nil when they hold syntax (a
    /// field, -word, a group, *, an @alias), which turns the bonuses off anyway.
    public static func text(_ typed: String) -> String? {
        let t = SearchText.closeQuote(typed.trimmingCharacters(in: .whitespaces))
        guard !t.isEmpty, t != "*" else { return nil }
        let plain = t.split(whereSeparator: \.isWhitespace).allSatisfy { word in
            !word.contains(where: { ":()|*".contains($0) }) && !word.hasPrefix("-") && !word.hasPrefix("@")
        }
        return plain ? t : nil
    }

    /// A page of yours: not a note, a file or code (what `forHister` leaves out).
    public static func isOwnPage(_ page: StoredPage) -> Bool {
        page.label != "vault" && page.source != "vault" && page.source != "code" && !LocalFiles.isLocalFile(page.url)
    }

    /// A filtered first page in Hister's own order: the plain words' pages
    /// of yours first, then the rest of the filtered page. The opened ones
    /// are both replies' (Hister keeps them per exact text, so Shiori's and
    /// Hister's own UI's differ), never repeated below. Total and paging
    /// stay the filtered page's; no plain page leaves it as it was.
    public static func merge(filtered: SearchPage, plain: SearchPage?) -> SearchPage {
        guard let plain else { return filtered }
        var opened = filtered.opened
        var openedURLs = Set(opened.map(\.url))
        for item in plain.opened where !openedURLs.contains(item.url) && !LocalFiles.isLocalFile(item.url) {
            opened.append(item)
            openedURLs.insert(item.url)
        }
        let first = plain.documents.filter { isOwnPage($0) && !openedURLs.contains($0.url) }
        let placed = Set(first.map(\.url))
        let rest = filtered.documents.filter { !placed.contains($0.url) && !openedURLs.contains($0.url) }
        var merged = filtered
        merged.documents = first + rest
        merged.opened = opened
        return merged
    }
}
