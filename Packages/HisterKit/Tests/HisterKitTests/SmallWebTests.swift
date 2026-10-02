import Foundation
import Testing

@testable import HisterKit

/// The small-web gateway's search and save, against a stub.
@Suite(.serialized)
struct SmallWebTests {
    static let host = "smallweb.example"
    let client: SmallWebClient

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = SmallWebClient(serverURL: "https://\(Self.host)", session: URLSession(configuration: config))!
        StubProtocol.reset(Self.host)
    }

    static let reply = """
        {"query": "sample query", "page": 1, "results": [
          {"title": "A Sample Post", "url": "gemini://capsule.example/sample_post",
           "proxy_url": "https://smallweb.example/page?url=gemini%3A%2F%2Fcapsule.example%2Fsample_post",
           "snippet": "sample notes … my query", "marks": [[20, 25], [0, 6]], "source": "tlgs", "sources": ["tlgs", "kennedy"],
           "scheme": "gemini", "kind": "text/gemini", "size": "9KB", "archive_url": null},
          {"title": "", "url": "gopher://gopher.example/1/phlog", "proxy_url": "https://smallweb.example/page?url=x",
           "snippet": "menu · gopher.example › /phlog", "marks": [], "source": "veronica", "sources": ["veronica"], "scheme": "gopher", "kind": "menu"},
          {"title": "Not ours", "url": "https://example.com/", "proxy_url": "https://smallweb.example/page?url=y"},
          {"title": "Broken"}
        ],
        "sources": {"tlgs": {"ok": true, "ms": 1043, "total": 937, "next": true, "cached": false},
                    "veronica": {"ok": false, "ms": 8000, "total": null, "next": false, "cached": false}},
        "errors": {"veronica": "timeout"}}
        """

    @Test func searchReadsResultsAndSkipsWhatItCant() async throws {
        StubProtocol.handle(Self.host) { _ in (200, Data(Self.reply.utf8)) }
        let page = try await client.search("  sample   query ", page: 2)
        let request = try #require(StubProtocol.requests(Self.host).first)
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(request.url?.path() == "/api/search")
        #expect(items.first { $0.name == "q" }?.value == "sample query")
        #expect(items.first { $0.name == "page" }?.value == "2")
        #expect(page.results.map(\.url) == ["gemini://capsule.example/sample_post", "gopher://gopher.example/1/phlog"])
        #expect(page.results[1].title == "gopher://gopher.example/1/phlog")
        #expect(page.results[0].engineNames == "TLGS · Kennedy")
        #expect(page.results[0].place == "capsule.example/sample_post")
        #expect(page.hasMore)
        #expect(page.failures == ["Veronica-2 timed out"])
    }

    @Test func marksAreScalarOffsetsAndBadOnesAreSkipped() {
        let result = SmallWebResult(url: "gemini://a/", title: "A", proxyURL: "https://s/", snippet: "sample notes … my query",
                                    marks: [[18, 23], [0, 6], [3, 4], [30, 40]])
        let runs = result.snippetRuns.map { "\($0.marked ? "[" : "")\($0.text)\($0.marked ? "]" : "")" }
        #expect(runs.joined() == "[sample] notes … my [query]")
    }

    @Test func saveAsksTheGatewayWithOriginHister() async throws {
        StubProtocol.handle(Self.host) { _ in (202, Data(#"{"queued": true}"#.utf8)) }
        try await client.save("gemini://a.example/x")
        let request = try #require(StubProtocol.requests(Self.host).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/api/save")
        #expect(request.value(forHTTPHeaderField: "Origin") == "hister://")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["url": "gemini://a.example/x"])
    }

    @Test func anEmptySearchAsksNothing() async throws {
        let page = try await client.search("   ")
        #expect(page.results.isEmpty)
        #expect(StubProtocol.requests(Self.host).isEmpty)
    }
}
