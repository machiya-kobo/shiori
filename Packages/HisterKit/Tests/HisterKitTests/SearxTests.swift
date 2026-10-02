import Foundation
import Testing

@testable import HisterKit

@Suite(.serialized)
struct SearxTests {
    static let host = "searx.example"
    let client: SearxClient

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = SearxClient(serverURL: "https://\(Self.host)", session: URLSession(configuration: config))!
        StubProtocol.reset(Self.host)
    }

    @Test func resultsKeepOnlyProxiedThumbnailsAndDropDuplicates() async throws {
        StubProtocol.handle(Self.host) { _ in
            (200, Data(#"""
            {"results":[
              {"url":"https://a.example/","title":"A","content":"x","engines":["bing","brave"],
               "thumbnail":"https://searx.example/image_proxy?url=u&h=1","publishedDate":"2026-06-25T03:32:37"},
              {"url":"https://a.example/","title":"A again"},
              {"url":"https://b.example/","title":"B","engine":"google","thumbnail":"https://gstatic.example/t.jpg"},
              {"url":"ftp://c.example/","title":"C"}
            ],"suggestions":["s1"],"corrections":[]}
            """#.utf8))
        }
        let page = try await client.search("q", page: 2)
        let request = try #require(StubProtocol.requests(Self.host).first)
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.first { $0.name == "pageno" }?.value == "2")
        #expect(items.first { $0.name == "format" }?.value == "json")
        #expect(page.results.map(\.url) == ["https://a.example/", "https://b.example/"])
        #expect(page.results[0].thumbnail?.host() == "searx.example")
        #expect(page.results[0].engines == ["bing", "brave"])
        #expect(page.results[0].published != nil)
        #expect(page.results[1].thumbnail == nil)
        #expect(page.results[1].engines == ["google"])
        #expect(page.suggestions == ["s1"])
    }

    @Test func unreachableIsUnreachable() async {
        StubProtocol.handle(Self.host) { _ in throw URLError(.cannotFindHost) }
        await #expect(throws: HisterError.unreachable) { try await client.search("q") }
    }

    @Test func imageProxyLinksForAnotherAddressComeHere() {
        let searx = SearxClient(serverURL: "https://searxng.example/")!
        let moved = searx.proxied("https://search.example/image_proxy?url=https%3A%2F%2Fi.example%2Fa.png&h=abc")
        #expect(moved?.absoluteString == "https://searxng.example/image_proxy?url=https%3A%2F%2Fi.example%2Fa.png&h=abc")
        // Anything but the image proxy, elsewhere: dropped.
        #expect(searx.proxied("https://tracker.example/pixel.gif") == nil)
        #expect(searx.proxied("https://search.example/search?q=x") == nil)
    }
}

struct WebQueryTests {
    @Test func histerSyntaxStaysOutOfTheWebSearch() {
        #expect(SearxClient.webQuery("label:foo") == "")
        #expect(SearxClient.webQuery("label:foo rust book") == "rust book")
        #expect(SearxClient.webQuery("rust -domain:reddit.com") == "rust")
        #expect(SearxClient.webQuery("Metadata.client:shiori x") == "x")
        #expect(SearxClient.webQuery("raspberry pi") == "raspberry pi")
        #expect(SearxClient.webQuery("@alpha amiga") == "amiga")
    }
}
