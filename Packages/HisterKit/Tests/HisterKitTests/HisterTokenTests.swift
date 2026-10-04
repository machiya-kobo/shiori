import Foundation
import Testing

@testable import HisterKit

/// The same cases as search-core.test.mjs's "Hister's token" test.
@Suite(.serialized)
struct HisterTokenTests {
    static let host = "token.example"
    let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset(Self.host)
        StubProtocol.handle(Self.host) { _ in (200, Data(#"{"total":0,"documents":[]}"#.utf8)) }
    }

    @Test func onlyASoundTokenIsKept() {
        #expect(HisterToken.clean("  ABCDEFGHJKLMNPQRSTUVWXYZ23  ") == "ABCDEFGHJKLMNPQRSTUVWXYZ23")
        #expect(HisterToken.clean("short") == nil)
        #expect(HisterToken.clean("has a space in it") == nil)
        #expect(HisterToken.clean("line\nbreak-token") == nil)
        #expect(HisterToken.clean("tökén-with-umlauts") == nil)
        #expect(HisterToken.clean(String(repeating: "x", count: 513)) == nil)
        #expect(HisterToken.clean(nil) == nil)
    }

    @Test func aTokenIsSentAsXAccessTokenNeverInTheURL() async throws {
        let client = try #require(HisterClient(serverURL: "https://\(Self.host)", token: "ABCDEFGHJKLMNPQRSTUVWXYZ23", session: session))
        #expect(client.sendsToken)
        _ = try await client.search("x")
        let request = try #require(StubProtocol.requests(Self.host).first)
        #expect(request.value(forHTTPHeaderField: "X-Access-Token") == "ABCDEFGHJKLMNPQRSTUVWXYZ23")
        #expect(request.value(forHTTPHeaderField: "Origin") == "hister://")
        #expect(!(request.url?.absoluteString.contains("ABCDEFGH") ?? true))
    }

    @Test func noTokenOrABadOneSendsNothing() async throws {
        for token in [nil, "", "not a token"] {
            StubProtocol.reset(Self.host)
            StubProtocol.handle(Self.host) { _ in (200, Data(#"{"total":0,"documents":[]}"#.utf8)) }
            let client = try #require(HisterClient(serverURL: "https://\(Self.host)", token: token, session: session))
            #expect(!client.sendsToken)
            _ = try await client.search("x")
            let request = try #require(StubProtocol.requests(Self.host).first)
            #expect(request.value(forHTTPHeaderField: "X-Access-Token") == nil)
        }
    }

    @Test func aRedirectElsewhereDropsTheToken() {
        let delegate = TokenKeepingRedirects()
        let session = URLSession(configuration: .ephemeral)
        func follow(_ from: String, _ to: String) -> String? {
            var original = URLRequest(url: URL(string: from)!)
            original.setValue("ABCDEFGHJKLMNPQRSTUVWXYZ23", forHTTPHeaderField: HisterToken.header)
            var next = original
            next.url = URL(string: to)
            let task = session.dataTask(with: original)
            nonisolated(unsafe) var out: URLRequest?
            delegate.urlSession(
                session, task: task,
                willPerformHTTPRedirection: HTTPURLResponse(url: original.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!,
                newRequest: next) { out = $0 }
            return out?.value(forHTTPHeaderField: HisterToken.header)
        }
        #expect(follow("https://h.example/a", "https://h.example/b") == "ABCDEFGHJKLMNPQRSTUVWXYZ23")
        #expect(follow("https://h.example/a", "https://evil.example/b") == nil)
        #expect(follow("https://h.example/a", "http://h.example/b") == nil)
        #expect(follow("https://h.example/a", "https://h.example:8443/b") == nil)
    }
}
