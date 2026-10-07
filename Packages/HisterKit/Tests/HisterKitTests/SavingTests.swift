import Foundation
import Testing

@testable import HisterKit

@Suite(.serialized)
struct SavingTests {
    static let host = "saving.example"
    let client: HisterClient
    let dir: URL

    init() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = HisterClient(serverURL: "https://\(Self.host)", session: URLSession(configuration: config))!
        StubProtocol.reset(Self.host)
        dir = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
    }

    func page(_ url: String, added: Int? = nil) -> NewPage {
        NewPage(url: url, title: "T", html: "<p>x</p>", label: "books", added: added, via: "share", clientVersion: "1.2")
    }

    @Test func addPostsTheDocumentWithProvenanceAndNoSkipRules() async throws {
        StubProtocol.handle(Self.host) { _ in (201, Data()) }
        try await client.add(page("https://a.example/"))
        let request = try #require(StubProtocol.requests(Self.host).first)
        #expect(request.url?.path() == "/api/add")
        let body = try jsonBody(request)
        #expect(body["url"] as? String == "https://a.example/")
        #expect(body["label"] as? String == "books")
        let metadata = try #require(body["metadata"] as? [String: Any])
        #expect(metadata["client"] as? String == "shiori")
        #expect(metadata["source"] as? String == "shiori")
        #expect(metadata["client_version"] as? String == "1.2")
        #expect(metadata["via"] as? String == "share")
        #expect(metadata["ignore_skip_rules"] as? Bool == true)
    }

    @Test func refusalsThatRetryingCantChangeAreRejections() async {
        StubProtocol.handle(Self.host) { _ in (406, Data()) }
        await #expect(throws: HisterError.rejected(Rejection(status: 406, message: ""))) {
            try await client.add(page("https://a.example/"))
        }
    }

    @Test func anEmptyLabelIsLeftOut() throws {
        let p = NewPage(url: "u", title: "t", label: "", via: "share")
        let body = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        #expect(body["label"] == nil)
    }

    @Test func theOutboxStampsTheVisitTimeAndKeepsOnePerURL() throws {
        let outbox = Outbox(directory: dir)
        try outbox.enqueue(page("https://a.example/"), now: Date(timeIntervalSince1970: 100))
        try outbox.enqueue(page("https://b.example/"), now: Date(timeIntervalSince1970: 200))
        try outbox.enqueue(page("https://a.example/"), now: Date(timeIntervalSince1970: 300))
        #expect(outbox.pages.map(\.url) == ["https://b.example/", "https://a.example/"])
        #expect(outbox.pages.last?.added == 100)
        #expect(outbox.status() == Outbox.Status(count: 2, oldest: Date(timeIntervalSince1970: 200)))
    }

    @Test func drainingSendsInOrderAndDropsRejections() async throws {
        let outbox = Outbox(directory: dir)
        try outbox.enqueue(page("https://ok.example/"), now: Date(timeIntervalSince1970: 1))
        try outbox.enqueue(page("https://skip.example/"), now: Date(timeIntervalSince1970: 2))
        StubProtocol.handle(Self.host) { request in
            let body = try jsonBody(request)
            return ((body["url"] as? String) == "https://skip.example/" ? 406 : 201, Data())
        }
        // The pages are stamped at seconds 1 and 2: drain on their clock.
        let result = await outbox.drain(using: client, now: Date(timeIntervalSince1970: 3))
        #expect(result == .sent(1))
        #expect(outbox.status().count == 0)
        let first = try jsonBody(try #require(StubProtocol.requests(Self.host).first))
        #expect(first["added"] as? Int == 1)
    }

    @Test func drainingStopsWhenUnreachableAndKeepsEverything() async throws {
        let outbox = Outbox(directory: dir)
        try outbox.enqueue(page("https://a.example/"))
        try outbox.enqueue(page("https://b.example/"))
        StubProtocol.handle(Self.host) { _ in throw URLError(.cannotFindHost) }
        #expect(await outbox.drain(using: client) == .stopped(sent: 0))
        #expect(outbox.status().count == 2)
    }

    @Test func aBrokenServerGetsFiveTriesPerPage() async throws {
        let outbox = Outbox(directory: dir)
        try outbox.enqueue(page("https://a.example/"))
        StubProtocol.handle(Self.host) { _ in (502, Data()) }
        for _ in 1..<Outbox.maxAttempts { await outbox.drain(using: client) }
        #expect(outbox.status().count == 1)
        await outbox.drain(using: client)
        #expect(outbox.status().count == 0)
    }

    @Test func pagesOlderThanTwoWeeksAreDroppedUnsent() async throws {
        let outbox = Outbox(directory: dir)
        let now = Date(timeIntervalSince1970: 2_000_000)
        try outbox.enqueue(page("https://new.example/"), now: now)
        try outbox.enqueue(page("https://old.example/", added: Int(now.timeIntervalSince1970 - Outbox.maxAge - 1)), now: now)
        StubProtocol.handle(Self.host) { _ in (201, Data()) }
        #expect(await outbox.drain(using: client, now: now) == .sent(1))
        #expect(outbox.status().count == 0)
        let sent = try jsonBody(try #require(StubProtocol.requests(Self.host).first))
        #expect(sent["url"] as? String == "https://new.example/")
    }

    @Test func queueingAPageDropsOnesTooOldToSend() throws {
        let outbox = Outbox(directory: dir)
        let now = Date(timeIntervalSince1970: 2_000_000)
        try outbox.enqueue(page("https://old.example/", added: Int(now.timeIntervalSince1970 - Outbox.maxAge - 1)), now: now)
        try outbox.enqueue(page("https://new.example/"), now: now)
        #expect(outbox.pages.map(\.url) == ["https://new.example/"])
    }

    @Test func anUnreadableEntryIsDroppedAndTheRestSent() async throws {
        let outbox = Outbox(directory: dir)
        try outbox.enqueue(page("https://a.example/"))
        try Data("not json".utf8).write(to: dir.appending(path: "0000000000.000000-broken.json"))
        StubProtocol.handle(Self.host) { _ in (201, Data()) }
        #expect(await outbox.drain(using: client) == .sent(1))
        #expect(outbox.status().count == 0)
    }

    @Test func theOutboxIsKeptOutOfBackups() throws {
        try Outbox(directory: dir).enqueue(page("https://a.example/"))
        #expect(try dir.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func titlesAndCapsForFetchedPages() {
        #expect(PageFetcher.title(in: "<html><head><TITLE> A &amp; B </TITLE></head>") == "A & B")
        #expect(PageFetcher.title(in: "<p>none</p>") == "")
        let big = "<p>" + String(repeating: "a", count: PageFetcher.maxHTMLCharacters) + "</p>"
        let cut = PageFetcher.capped(big)
        #expect(cut == "<p>")
        #expect(PageFetcher.capped("<p>été</p>") == "<p>été</p>")
    }

    @Test func aFetchedPageIsCappedAndOnlyHTMLOrText() async throws {
        let host = "fetch.example"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        defer { StubProtocol.reset(host) }
        let url = try #require(URL(string: "https://\(host)/page"))
        let big = "<title>Big</title>" + String(repeating: "a", count: PageFetcher.maxBytes + 100_000)
        StubProtocol.headers(host, ["Content-Type": "text/html; charset=utf-8"])
        StubProtocol.handle(host) { _ in (200, Data(big.utf8)) }
        let fetched = try await PageFetcher.fetch(url, session: session)
        #expect(fetched.title == "Big")
        #expect(fetched.url == url.absoluteString)
        #expect(fetched.html.utf8.count <= PageFetcher.maxHTMLCharacters)
        #expect(fetched.html.hasPrefix("<title>Big</title>"))

        StubProtocol.headers(host, ["Content-Type": "text/html"])
        StubProtocol.handle(host) { _ in (200, Data("<title>Small</title><p>x</p>".utf8)) }
        #expect(try await PageFetcher.fetch(url, session: session).html == "<title>Small</title><p>x</p>")

        StubProtocol.headers(host, ["Content-Type": "application/pdf"])
        StubProtocol.handle(host) { _ in (200, Data("%PDF".utf8)) }
        #expect(try await PageFetcher.fetch(url, session: session) == PageFetcher.Fetched(url: url.absoluteString, title: "", html: ""))
    }
}
