import Foundation

/// The pages you opened for a search first, then the rest. Hister takes an
/// opened page out of `documents` and sends it only in `history` (it ranks
/// it first), so a list that dropped `history` lost the page from its
/// search. Only web addresses; `keep` leaves out what the list doesn't show
/// (a note, a file). Duplicates go. `S.openedFirst` is the twin, on
/// scripts/opened-first-cases.json.
public enum OpenedFirst {
    public static func pages(
        opened: [OpenedResult], documents: [StoredPage], keep: (String) -> Bool = { _ in true }
    ) -> [StoredPage] {
        let lifted = opened
            .filter { $0.url.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil && keep($0.url) }
            .map(StoredPage.init(opened:))
        var seen = Set<String>()
        return (lifted + documents).filter { seen.insert($0.url).inserted }
    }
}

extension StoredPage {
    /// An opened result as a page, with what Hister sends for it: no
    /// snippet or label.
    public init(opened: OpenedResult) {
        self.init(
            url: opened.url, title: opened.title, domain: opened.domain ?? URL(string: opened.url)?.host() ?? "",
            label: "", added: opened.added ?? .distantPast, updated: opened.updated ?? opened.added ?? .distantPast,
            faviconKey: "", snippetHTML: "")
    }
}
