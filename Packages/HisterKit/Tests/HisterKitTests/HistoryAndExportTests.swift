import Foundation
import Testing

@testable import HisterKit

@Suite(.serialized)
struct HistoryTests {
    static let host = "history.example"
    let client: HisterClient

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = HisterClient(serverURL: "https://\(Self.host)", session: URLSession(configuration: config))!
        StubProtocol.reset(Self.host)
    }

    func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    @Test func openingAResultIsRecordedWithItsQuery() async throws {
        StubProtocol.handle(Self.host) { _ in (200, Data()) }
        try await client.recordOpened(url: "https://a.example/", title: "A", query: " rust ")
        let request = try #require(StubProtocol.requests(Self.host).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/api/history")
        #expect(request.value(forHTTPHeaderField: "Origin") == "hister://")
        let sent = try body(request)
        #expect(sent["url"] as? String == "https://a.example/")
        // As the search was sent (Hister matches the exact text).
        #expect(sent["query"] as? String == "(rust|rust*) -label:vault -metadata.source:vault -type:local")
        #expect(sent["delete"] == nil)
    }

    @Test func anEmptyQueryRecordsNothing() async throws {
        try await client.recordOpened(url: "https://a.example/", title: "A", query: "  ")
        #expect(StubProtocol.requests(Self.host).isEmpty)
    }

    @Test func forgettingSendsDelete() async throws {
        StubProtocol.handle(Self.host) { _ in (200, Data()) }
        try await client.forgetOpened(url: "https://a.example/", query: "rust")
        let sent = try body(try #require(StubProtocol.requests(Self.host).first))
        #expect(sent["delete"] as? Bool == true)
    }

    @Test func searchCarriesOpenedResultsAndFacets() async throws {
        let reply = """
            {"total":2,"documents":[{"url":"https://a.example/","title":"A"}],
             "history":[{"url":"https://b.example/","title":"B","count":3,"pinned":false}],
             "facets":{"terms":{"domains":{"terms":[{"term":"a.example","count":1}],"other":4},
                                "visits":{"terms":[{"term":"2..4","count":1,"label":"2 to 4"}]}},
                       "date_histogram":[{"name":"last_7d","count":2}]}}
            """
        StubProtocol.handle(Self.host) { _ in (200, Data(reply.utf8)) }
        let page = try await client.search("rust", options: SearchOptions(facets: true, dateFrom: Date(timeIntervalSince1970: 100)))
        #expect(page.opened == [OpenedResult(url: "https://b.example/", title: "B", count: 3)])
        #expect(page.facets?.terms["domains"]?.terms.first?.term == "a.example")
        #expect(page.facets?.terms["domains"]?.other == 4)
        #expect(page.facets?.terms["visits"]?.terms.first?.label == "2 to 4")
        #expect(page.facets?.dates == [Facets.Bucket(name: "last_7d", count: 2)])
        let sent = query(try #require(StubProtocol.requests(Self.host).first))["query"] ?? ""
        let json = try #require(try JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: Any])
        #expect(json["facets"] as? Bool == true)
        #expect(json["date_from"] as? Int == 100)
    }

    @Test func aBrokenFacetsBlockDoesntFailTheSearch() async throws {
        StubProtocol.handle(Self.host) { _ in (200, Data(#"{"total":0,"documents":[],"facets":"nope","history":7}"#.utf8)) }
        let page = try await client.search("x")
        #expect(page.facets == nil)
        #expect(page.opened.isEmpty)
    }

    @Test func laterPagesDontRepeatOpenedResults() async throws {
        StubProtocol.handle(Self.host) { _ in (200, Data(#"{"total":1,"documents":[],"history":[{"url":"u","title":"t","count":1}]}"#.utf8)) }
        #expect(try await client.search("x", pageKey: "k").opened.isEmpty)
    }

    @Test func theTimelineDecodesDaysMonthsAndOlder() async throws {
        let reply = """
            {"days":[{"key":"day:2026-09-28","from":10,"to":20,"count":15},{"key":"day:2026-09-27","from":0,"to":10,"count":0}],
             "months":[{"key":"month:2026-08","from":-5,"to":0,"count":4}],"older":{"key":"older","to":-5,"count":9}}
            """
        StubProtocol.handle(Self.host) { _ in (200, Data(reply.utf8)) }
        let timeline = try await client.timeline(opened: true, timeZone: TimeZone(identifier: "Europe/London")!)
        #expect(timeline.buckets.map(\.key) == ["day:2026-09-28", "month:2026-08", "older"])
        #expect(timeline.older?.from == nil)
        let items = query(try #require(StubProtocol.requests(Self.host).first))
        #expect(items["opened"] == "true")
        #expect(items["timezone"] == "Europe/London")
    }

    @Test func indexedHistoryPagesByTheLastURL() async throws {
        let docs = (0..<100).map { #"{"url":"https://p\#($0).example/","title":"P"}"# }.joined(separator: ",")
        StubProtocol.handle(Self.host) { _ in (200, Data(#"{"total":100,"documents":[\#(docs)]}"#.utf8)) }
        let page = try await client.indexedHistory(from: Date(timeIntervalSince1970: 5), to: Date(timeIntervalSince1970: 9), filter: "rust")
        #expect(page.documents.count == 100)
        #expect(page.next == "https://p99.example/")
        let items = query(try #require(StubProtocol.requests(Self.host).first))
        #expect(items["date_from"] == "5")
        #expect(items["date_to"] == "9")
        #expect(items["filter"] == "rust")
    }

    @Test func openedHistoryDecodesEntries() async throws {
        let reply = #"{"documents":[{"id":6,"url":"https://c.example/","title":"C","query":"sample","added":1790550000,"add_count":3}],"last_id":6}"#
        StubProtocol.handle(Self.host) { _ in (200, Data(reply.utf8)) }
        let page = try await client.openedHistory()
        #expect(page.entries.first?.query == "sample")
        #expect(page.next == nil)
    }

    @Test func versionsComeNewestFirst() async throws {
        let reply = """
            [{"id":1,"created_at":"2026-09-01T10:00:00Z","url":"u","text_diff":"-a\\n+b","html_diff":""},
             {"id":2,"created_at":"2026-09-20T10:00:00.123456Z","url":"u","text_diff":"-b\\n+c","html_diff":""}]
            """
        StubProtocol.handle(Self.host) { _ in (200, Data(reply.utf8)) }
        let versions = try await client.versions(of: "u")
        #expect(versions.map(\.id) == [2, 1])
        #expect(versions.first?.created != .distantPast)
    }

    @Test func extractorsKeepOnlyThoseThatPreview() async throws {
        let reply = """
            [{"name":"GitHub","description":"Repos","enabled":true,"capabilities":{"preview":true}},
             {"name":"Enricher","enabled":true,"capabilities":{"preview":false}},
             {"name":"Off","enabled":false,"capabilities":{"preview":true}}]
            """
        StubProtocol.handle(Self.host) { _ in (200, Data(reply.utf8)) }
        #expect(try await client.extractors(for: "u").map(\.name) == ["GitHub"])
    }

    @Test func capabilitiesAndStats() async throws {
        StubProtocol.handle(Self.host) { request in
            request.url?.path() == "/api/config"
                ? (200, Data(#"{"semanticEnabled":true}"#.utf8))
                : (200, Data(#"{"doc_count":100,"file_count":0,"rule_count":43,"alias_count":3}"#.utf8))
        }
        #expect(try await client.capabilities().semantic)
        let stats = try await client.stats()
        #expect(stats.documents == 100)
        #expect(stats.aliases == 3)
    }
}

struct ExportTests {
    let pages = [
        StoredPage(
            url: "https://a.example/x?y=1&z=2", title: "A, \"quoted\" <b>", domain: "a.example", label: "books",
            added: Date(timeIntervalSince1970: 1_790_000_000), updated: Date(timeIntervalSince1970: 1_790_000_100),
            faviconKey: "", snippetHTML: "Some <mark>text</mark>"),
        StoredPage(
            url: "https://b.example/", title: "=SUM(A1)", domain: "b.example", label: "",
            added: Date(timeIntervalSince1970: 0), updated: Date(timeIntervalSince1970: 0), faviconKey: "", snippetHTML: ""),
    ]

    @Test func csvQuotesAndDefusesFormulas() {
        let lines = Export.csv(pages).components(separatedBy: "\r\n")
        #expect(lines[0] == "url,title,domain,label,added,updated")
        #expect(lines[1].hasPrefix(#"https://a.example/x?y=1&z=2,"A, ""quoted"" <b>",a.example,books,"#))
        #expect(lines[2].hasPrefix("https://b.example/,'=SUM(A1),b.example,,"))
    }

    @Test func jsonRoundTripsTheFields() throws {
        let rows = try #require(try JSONSerialization.jsonObject(with: Export.json(pages)) as? [[String: Any]])
        #expect(rows.count == 2)
        #expect(rows[0]["url"] as? String == "https://a.example/x?y=1&z=2")
        #expect(rows[0]["added"] as? Int == 1_790_000_000)
    }

    @Test func rssIsEscapedAndDated() throws {
        let rss = Export.rss(pages, title: "books & more", link: URL(string: "https://h.example/"))
        #expect(rss.contains("<title>Shiori – books &amp; more</title>"))
        #expect(rss.contains("<link>https://a.example/x?y=1&amp;z=2</link>"))
        #expect(rss.contains("<title>A, &quot;quoted&quot; &lt;b&gt;</title>"))
        #expect(rss.contains("<category>books</category>"))
        #expect(rss.contains("<description>Some text</description>"))
        #expect(rss.contains("<pubDate>Mon, 21 Sep 2026 14:13:20 +0000</pubDate>"))
        // Well-formed.
        let parser = XMLParser(data: Data(rss.utf8))
        #expect(parser.parse())
    }

    @Test func feedURLsEscapeTheQuery() {
        let url = Export.feedURL(base: URL(string: "https://h.example/")!, query: "label:c++ tech", title: "C++")
        #expect(url.absoluteString == "https://h.example/shiori/feed?q=label:c%2B%2B%20tech&title=C%2B%2B")
        let same = Export.feedURL(base: URL(string: "https://h.example/")!, query: "tech", title: "tech")
        #expect(same.absoluteString == "https://h.example/shiori/feed?q=tech")
    }

    @Test func newsBlurSubscribeLinks() {
        let feed = URL(string: "https://h.example/shiori/feed?q=tech")!
        let url = Export.newsBlurSubscribeURL(newsBlur: "https://newsblur.example", feed: feed)
        #expect(url?.absoluteString == "https://newsblur.example/?url=https://h.example/shiori/feed?q%3Dtech")
        #expect(Export.newsBlurSubscribeURL(newsBlur: "not a url", feed: feed) == nil)
    }

    @Test func opmlListsEveryFeed() throws {
        let data = Export.opml(title: "Shiori", feeds: [
            (title: "tech", url: URL(string: "https://h.example/shiori/feed?q=tech&x=1")!),
            (title: "arts", url: URL(string: "https://h.example/shiori/feed?q=arts")!),
        ])
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#"xmlUrl="https://h.example/shiori/feed?q=tech&amp;x=1""#))
        #expect(XMLParser(data: data).parse())
    }

    @Test func fileNamesAreTidy() {
        #expect(Export.fileName("label:books  & more", format: .csv) == "shiori-label-books-more.csv")
        #expect(Export.fileName("***", format: .json) == "shiori-results.json")
    }
}
