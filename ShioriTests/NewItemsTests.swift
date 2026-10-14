import Foundation
import HisterKit
import Testing

/// The New Items banner counts only results newer than the list's top.
struct NewItemsTests {
    private func page(_ path: String, _ minutesAgo: Double) -> StoredPage {
        let date = Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60)
        return StoredPage(url: "https://example.com/\(path)", title: path, domain: "example.com", label: "",
                          added: date, updated: date, faviconKey: "", snippetHTML: "")
    }

    @Test func heldBackOlderResultsAreNotNew() {
        // On screen: a (newest), b. Fetched again: a, b, plus c and d, older
        // ones All hadn't placed yet, and e, really new.
        let shown = [page("a", 10), page("b", 20)]
        let seen = Set(shown.map(\.url))
        let fetched = [page("e", 1), page("a", 10), page("b", 20), page("c", 30), page("d", 40)]
        #expect(NewItems.count(fetched, seen: seen, newestShown: shown.map(\.updated).max()) == 1)
    }

    @Test func nothingNewIsZero() {
        let shown = [page("a", 10), page("b", 20)]
        let fetched = [page("a", 10), page("b", 20), page("c", 30)]
        #expect(NewItems.count(fetched, seen: Set(shown.map(\.url)), newestShown: shown.map(\.updated).max()) == 0)
    }

    @Test func itAsksLessOftenWhileNothingChanges() {
        let first = Duration.seconds(60), most = Duration.seconds(600)
        func wait(_ s: Int64, _ changed: Bool) -> Duration { NewItems.wait(after: .seconds(s), changed: changed, first: first, most: most) }
        #expect(wait(60, false) == .seconds(120))
        #expect(wait(480, false) == .seconds(600))
        #expect(wait(600, false) == .seconds(600))
        #expect(wait(600, true) == .seconds(60))
        #expect(wait(10, false) == .seconds(120))
    }

    @Test func anEmptyListCountsEverythingUnseen() {
        #expect(NewItems.count([page("a", 1), page("b", 2)], seen: [], newestShown: nil) == 2)
    }
}
