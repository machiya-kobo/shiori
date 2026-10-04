import Foundation

/// A list with runs of one site folded: Hister keeps every page you
/// visit, so a session on one site (a sign-in, its settings, a dashboard)
/// fills a screen with it. A run of `minimum` or more pages from one site
/// in a row shows its first page, then one row that holds the rest.
/// Notes (`label:vault`) and files never fold: each is its own document,
/// though notes share Niwa's or Konbini's host and files Hister's `local`.
public enum SiteRuns {
    public enum Item: Sendable, Equatable, Identifiable {
        case page(StoredPage)
        /// The rest of a run: `site`, and its pages in list order.
        case folded(site: String, pages: [StoredPage])

        public var id: String {
            switch self {
            case .page(let page): page.id
            // Named for its first page, so it keeps its identity (and
            // whether it's open) as later pages join the run.
            case .folded(_, let pages): "folded:" + (pages.first?.id ?? "")
            }
        }
    }

    public static func items(_ pages: [StoredPage], minimum: Int = 3) -> [Item] {
        var items: [Item] = []
        var index = pages.startIndex
        while index < pages.endIndex {
            let site = key(pages[index])
            var end = pages.index(after: index)
            if let site {
                while end < pages.endIndex, key(pages[end]) == site { end = pages.index(after: end) }
            }
            items.append(.page(pages[index]))
            let rest = Array(pages[pages.index(after: index)..<end])
            if rest.count + 1 >= minimum, let site {
                items.append(.folded(site: site, pages: rest))
            } else {
                items += rest.map(Item.page)
            }
            index = end
        }
        return items
    }

    /// The site a page counts under ("www." aside), or nil for one that
    /// never folds.
    static func key(_ page: StoredPage) -> String? {
        // Nor code: one forge holds every repo, and the rows are its own.
        guard page.label != "vault", !LocalFiles.isLocalFile(page.url), page.code == nil else { return nil }
        let host = page.domain.isEmpty ? (URL(string: page.url)?.host() ?? "") : page.domain
        let site = host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host.lowercased()
        return site.isEmpty ? nil : site
    }
}
