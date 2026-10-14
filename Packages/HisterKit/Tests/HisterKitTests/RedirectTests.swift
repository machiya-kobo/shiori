import Foundation
import Testing

@testable import HisterKit

/// Every request that carries a credential refuses to take it to another
/// address: Hister's token and session (`TokenKeepingRedirects`), the
/// media services' tokens (`NoRedirects`). URLSession itself only strips
/// `Authorization`, so without the delegates `X-Access-Token`, `Cookie` and
/// `X-Plex-Token` would follow a redirect anywhere.
@Suite(.serialized)
struct RedirectTests {
    static let from = "redirect-from.example"
    static let elsewhere = "redirect-elsewhere.example"

    let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }()

    init() {
        StubProtocol.reset(Self.from)
        StubProtocol.reset(Self.elsewhere)
        StubProtocol.handle(Self.elsewhere) { _ in (200, Data(#"{"total":0,"documents":[]}"#.utf8)) }
    }

    func redirect(to path: String) {
        StubProtocol.headers(Self.from, ["Location": "https://\(Self.elsewhere)\(path)"])
        StubProtocol.handle(Self.from) { _ in (302, Data()) }
    }

    @Test func histersTokenAndSessionNeverFollowToAnotherHost() async throws {
        redirect(to: "/search")
        let client = try #require(HisterClient(
            serverURL: "https://\(Self.from)", token: "ABCDEFGHJKLMNPQRSTUVWXYZ23", histerSession: "s3cr3t", session: session))
        _ = try? await client.search("x")
        #expect(!StubProtocol.requests(Self.from).isEmpty)
        for request in StubProtocol.requests(Self.elsewhere) {
            #expect(request.value(forHTTPHeaderField: "X-Access-Token") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        }
    }

    @Test func aMediaTokenNeverFollowsARedirect() async throws {
        redirect(to: "/identity")
        let account = try #require(MediaAccount(base: "https://\(Self.from):32400/", token: "plex-secret"))
        let client = MediaClient(accounts: [.plex: account], session: session)
        _ = await client.check(.plex)
        #expect(!StubProtocol.requests(Self.from).isEmpty)
        #expect(StubProtocol.requests(Self.elsewhere).isEmpty)
    }
}
