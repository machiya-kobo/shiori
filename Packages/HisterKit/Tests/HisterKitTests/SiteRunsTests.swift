import Foundation
import Testing

@testable import HisterKit

struct SiteRunsTests {
    func page(_ url: String, domain: String? = nil, label: String = "") -> StoredPage {
        StoredPage(
            url: url, title: url, domain: domain ?? (URL(string: url)?.host() ?? ""), label: label,
            added: .now, updated: .now, faviconKey: "", snippetHTML: "")
    }

    func shape(_ items: [SiteRuns.Item]) -> [String] {
        items.map {
            switch $0 {
            case .page(let p): p.url
            case .folded(let site, let pages): "\(site) +\(pages.count)"
            }
        }
    }

    @Test func aRunOfThreeOrMoreShowsItsFirstPageAndFoldsTheRest() {
        let pages = [
            page("https://a.example/accounts/login/"),
            page("https://a.example/"),
            page("https://www.a.example/projects/"),
            page("https://b.example/search?q=x"),
            page("https://a.example/docs/"),
        ]
        #expect(shape(SiteRuns.items(pages)) == [
            "https://a.example/accounts/login/", "a.example +2",
            "https://b.example/search?q=x", "https://a.example/docs/",
        ])
    }

    @Test func twoInARowStayAsTheyAre() {
        let pages = [page("https://a.example/1"), page("https://a.example/2"), page("https://b.example/")]
        #expect(shape(SiteRuns.items(pages)) == pages.map(\.url))
    }

    @Test func notesNeverFoldThoughTheyShareAHost() {
        let notes = (1...4).map { page("https://konbini.example/p/\($0)", label: "vault") }
        #expect(shape(SiteRuns.items(notes)) == notes.map(\.url))
    }

    @Test func filesNeverFoldThoughTheyShareLocal() {
        let files = (1...4).map { StoredPage(url: "file:///home/u/doc\($0).md", title: "", domain: "local", label: "",
                                             added: .distantPast, updated: .distantPast, faviconKey: "", snippetHTML: "") }
        #expect(shape(SiteRuns.items(files)) == files.map(\.url))
    }

    @Test func theFoldedRowKeepsItsIdentityAsTheRunGrows() {
        let three = (1...3).map { page("https://a.example/\($0)") }
        let four = three + [page("https://a.example/4")]
        #expect(SiteRuns.items(three)[1].id == SiteRuns.items(four)[1].id)
    }

    @Test func pagesWithoutASiteDontFold() {
        let pages = (1...3).map { page("file:///doc\($0).pdf", domain: "") }
        #expect(shape(SiteRuns.items(pages)) == pages.map(\.url))
    }
}

struct OpenedResultTests {
    @Test func openedResultsCarryTheirHostAndDatesWhenHisterSendsThem() throws {
        let json = Data(#"""
            [{"url": "https://hister.org/", "title": "Hister", "count": 3, "domain": "hister.org",
              "added": 1790380800, "updated": 1790600000},
             {"url": "https://old.example/", "title": "Old", "count": 1}]
            """#.utf8)
        let results = try JSONDecoder().decode([OpenedResult].self, from: json)
        #expect(results[0].domain == "hister.org")
        #expect(results[0].updated == Date(timeIntervalSince1970: 1_790_600_000))
        #expect(results[1].domain == nil)
        #expect(results[1].added == nil && results[1].updated == nil)
    }
}
