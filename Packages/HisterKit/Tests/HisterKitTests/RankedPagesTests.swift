import Foundation
import Testing
@testable import HisterKit

/// search-core.js's rankedText / isOwnPage / rankedPages tests, case for case.
@Suite(.serialized)
struct RankedPagesTests {
    static let host = "ranked.example"
    let client: HisterClient

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = HisterClient(serverURL: "https://\(Self.host)", session: URLSession(configuration: config))!
        StubProtocol.reset(Self.host)
    }

    private func page(_ url: String, label: String = "", source: String = "") -> StoredPage {
        var page = StoredPage(url: url, title: url, domain: "", label: label, added: .distantPast, updated: .distantPast, faviconKey: "", snippetHTML: "")
        page.source = source
        return page
    }

    @Test func allAsksForThePlainWordsTooInHistersOwnOrder() {
        let cases: [(String, String?)] = [
            ("raspberry pi", "raspberry pi"), ("  hister  ", "hister"), ("\"exact phrase", "\"exact phrase\""), ("c++ guide", "c++ guide"),
            ("町家 京都", "町家 京都"), ("label:alpha pi", nil), ("pi -zero", nil), ("raspberry (pi|zero)", nil), ("hist*", nil),
            ("@retro games", nil), ("*", nil), ("", nil),
        ]
        for (typed, ranked) in cases { #expect(RankedPages.text(typed) == ranked, "\(typed)") }
    }

    @Test func aPageOfYoursIsNotANoteAFileOrCode() {
        #expect(RankedPages.isOwnPage(page("https://a.example/")))
        #expect(RankedPages.isOwnPage(page("https://a.example/", label: "retro", source: "shiori")))
        #expect(!RankedPages.isOwnPage(page("https://kura.example.com/n/x", label: "vault")))
        #expect(!RankedPages.isOwnPage(page("https://kura.example.com/n/x", source: "vault")))
        #expect(!RankedPages.isOwnPage(page("https://forge.example/o/r", source: "code")))
        #expect(!RankedPages.isOwnPage(page("file:///home/u/notes.txt")))
    }

    @Test func thePlainWordsPagesLeadTheFilteredPageFillsInOpenedOnesFromBoth() {
        let filtered = SearchPage(
            total: 4,
            documents: [page("https://org.example/"), page("https://forum.example/1"), page("https://wiki.example/"), page("https://pine.example/")],
            nextPageKey: "k2", suggestion: nil, opened: [OpenedResult(url: "https://com.example/", title: "")])
        let plain = SearchPage(
            total: 9,
            documents: [page("https://wiki.example/"), page("https://kura.example.com/n/x", label: "vault"), page("https://com.example/"),
                        page("https://forge.example/o/r", source: "code"), page("https://org.example/"), page("https://forum.example/1")],
            nextPageKey: nil, suggestion: nil,
            opened: [OpenedResult(url: "https://locator.example/", title: ""), OpenedResult(url: "https://com.example/", title: ""),
                     OpenedResult(url: "file:///x.txt", title: "")])
        let merged = RankedPages.merge(filtered: filtered, plain: plain)
        #expect(merged.documents.map(\.url) == ["https://wiki.example/", "https://org.example/", "https://forum.example/1", "https://pine.example/"])
        #expect(merged.opened.map(\.url) == ["https://com.example/", "https://locator.example/"])
        #expect(merged.total == 4)
        #expect(merged.nextPageKey == "k2")
        // A plain reply that failed (or wasn't asked) leaves the filtered one as it was.
        #expect(RankedPages.merge(filtered: filtered, plain: nil) == filtered)
    }

    /// The text each request sent.
    private var sentTexts: [String] {
        StubProtocol.requests(Self.host).compactMap { request in
            guard let url = request.url,
                  let sent = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "query" })?.value,
                  let query = try? JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: Any]
            else { return nil }
            return query["text"] as? String
        }
    }

    private func stub(plain: String?, filtered: String) {
        StubProtocol.handle(Self.host) { request in
            let text = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "query" }?.value } ?? ""
            if text.contains(#""text":"raspberry pi""#) {
                guard let plain else { return (502, Data("down".utf8)) }
                return (200, Data(plain.utf8))
            }
            return (200, Data(filtered.utf8))
        }
    }

    private static let filteredReply = #"{"total":3,"page_key":"k2","documents":[{"url":"https://org.example/"},{"url":"https://forum.example/"},{"url":"https://wiki.example/"}]}"#
    private static let plainReply = #"{"total":5,"documents":[{"url":"https://wiki.example/"},{"url":"https://kura.example/n/x","label":"vault"},{"url":"https://org.example/"},{"url":"https://forge.example/r","metadata":{"source":"code"}}]}"#

    @Test func rankedSearchAsksForThePlainWordsBesideTheFilteredSearch() async throws {
        stub(plain: Self.plainReply, filtered: Self.filteredReply)
        let page = try await client.rankedSearch("raspberry pi", limit: 3)
        #expect(Set(sentTexts) == ["raspberry pi", SearchText.forHister("raspberry pi")])
        #expect(page.documents.map(\.url) == ["https://wiki.example/", "https://org.example/", "https://forum.example/"])
        #expect(page.total == 3)
        #expect(page.nextPageKey == "k2")
    }

    @Test func rankedSearchWithSyntaxOrADateRangeIsTheFilteredSearchAlone() async throws {
        stub(plain: Self.plainReply, filtered: Self.filteredReply)
        _ = try await client.rankedSearch("label:retro pi", limit: 3)
        #expect(sentTexts == [SearchText.forHister("label:retro pi")])
        StubProtocol.reset(Self.host)
        stub(plain: Self.plainReply, filtered: Self.filteredReply)
        _ = try await client.rankedSearch("raspberry pi", limit: 3, options: SearchOptions(dateFrom: .now.addingTimeInterval(-86_400)))
        #expect(sentTexts == [SearchText.forHister("raspberry pi")])
    }

    @Test func rankedSearchKeepsTheFilteredPageWhenThePlainOneFails() async throws {
        stub(plain: nil, filtered: Self.filteredReply)
        let page = try await client.rankedSearch("raspberry pi", limit: 3)
        #expect(page.documents.map(\.url) == ["https://org.example/", "https://forum.example/", "https://wiki.example/"])
    }
}
