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
        // Oldest by the time it was saved, not by when it was queued.
        #expect(outbox.status() == Outbox.Status(count: 2, oldest: Date(timeIntervalSince1970: 100)))
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
        // The refused page is listed, with why.
        #expect(outbox.notSaved() == [Outbox.NotSaved(
            url: "https://skip.example/", title: "T", reason: "Hister skips this site.", date: Date(timeIntervalSince1970: 3))])
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
        #expect(outbox.notSaved().map(\.reason) == ["Hister answered 502 5 times."])
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
        #expect(outbox.notSaved().map(\.url) == ["https://old.example/"])
        #expect(outbox.notSaved().first?.reason == "Waited more than 14 days.")
    }

    @Test func queueingAPageDropsOnesTooOldToSend() throws {
        let outbox = Outbox(directory: dir)
        let now = Date(timeIntervalSince1970: 2_000_000)
        try outbox.enqueue(page("https://old.example/", added: Int(now.timeIntervalSince1970 - Outbox.maxAge - 1)), now: now)
        try outbox.enqueue(page("https://new.example/"), now: now)
        #expect(outbox.pages.map(\.url) == ["https://new.example/"])
        #expect(outbox.notSaved().map(\.url) == ["https://old.example/"])
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

    @Test func aSiteErrorIsThrownNotReturnedAsThePage() async throws {
        let host = "fetch-error.example"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        defer { StubProtocol.reset(host) }
        let url = try #require(URL(string: "https://\(host)/page"))
        StubProtocol.headers(host, ["Content-Type": "text/html"])
        for status in [404, 403, 429, 503] {
            StubProtocol.handle(host) { _ in (status, Data("<title>\(status) Error</title>".utf8)) }
            await #expect(throws: PageFetcher.SiteError(status: status)) { try await PageFetcher.fetch(url, session: session) }
        }
        #expect(PageFetcher.SiteError(status: 404).isTemporary == false)
        #expect(PageFetcher.SiteError(status: 429).isTemporary)
        #expect(PageFetcher.SiteError(status: 502).isTemporary)
    }

    @Test func onlyWebAddressesAreFetched() async {
        for raw in ["file:///etc/hosts", "ftp://example.com/x", "data:text/html,hi"] {
            await #expect(throws: URLError(.unsupportedURL)) { try await PageFetcher.fetch(URL(string: raw)!) }
        }
    }

    @Test func aFailedLookupThrowsRatherThanReadingAsNotHeld() async throws {
        StubProtocol.handle(Self.host) { _ in (502, Data()) }
        await #expect(throws: HisterError.self) { try await client.heldLabels(for: ["gemini://example.org/"]) }
        // The best-effort form, for marks only, reads it as nothing known.
        #expect(await client.savedLabels(for: ["gemini://example.org/"]).isEmpty)
    }

    @Test func aLinkKeptAloneIsDownloadedWhenTheOutboxDrains() async throws {
        let outbox = Outbox(directory: dir)
        try outbox.enqueue(NewPage(url: "https://later.example/", title: "later.example", via: "share"))
        try outbox.enqueue(NewPage(url: "https://gone.example/", title: "", via: "share"))
        try outbox.enqueue(NewPage(url: "https://busy.example/", title: "", via: "share"))
        StubProtocol.handle(Self.host) { _ in (201, Data()) }
        let result = await outbox.drain(using: client, fetch: { url in
            switch url.host() {
            case "later.example": return PageFetcher.Fetched(url: "https://later.example/", title: "Later", html: "<p>later</p>")
            case "gone.example": throw PageFetcher.SiteError(status: 410)
            default: throw PageFetcher.SiteError(status: 503)
            }
        })
        #expect(result == .sent(1))
        let sent = try jsonBody(try #require(StubProtocol.requests(Self.host).first))
        #expect(sent["title"] as? String == "Later")
        #expect((sent["html"] as? String)?.contains("later") == true)
        // The gone page is dropped; the busy one waits for the next drain.
        #expect(outbox.pages.map(\.url) == ["https://busy.example/"])
        #expect(outbox.notSaved().map(\.reason) == ["The site answered 410: not saved."])
    }

    @Test func signedOutKeepsEveryPageAndCountsNoTry() async throws {
        let outbox = Outbox(directory: dir)
        try outbox.enqueue(page("https://a.example/"))
        try outbox.enqueue(page("https://b.example/"))
        StubProtocol.handle(Self.host) { _ in (401, Data()) }
        // Far more drains than tries: a sign-in never runs a page out of them.
        for _ in 0..<(Outbox.maxAttempts * 2) {
            #expect(await outbox.drain(using: client) == .signedOut(sent: 0))
        }
        #expect(outbox.status().count == 2)
        #expect(outbox.notSaved().isEmpty)
        StubProtocol.handle(Self.host) { _ in (201, Data()) }
        #expect(await outbox.drain(using: client) == .sent(2))
    }

    @Test func aBusyServerCountsATryAndStops() async throws {
        let outbox = Outbox(directory: dir)
        try outbox.enqueue(page("https://a.example/"))
        try outbox.enqueue(page("https://b.example/"))
        StubProtocol.handle(Self.host) { _ in (429, Data()) }
        for _ in 1..<Outbox.maxAttempts {
            #expect(await outbox.drain(using: client) == .stopped(sent: 0))
        }
        // Only the first page was tried each time: the second keeps all its tries.
        #expect(StubProtocol.requests(Self.host).count == Outbox.maxAttempts - 1)
        #expect(outbox.status().count == 2)
        #expect(await outbox.drain(using: client) == .stopped(sent: 0))
        #expect(outbox.pages.map(\.url) == ["https://b.example/"])
        #expect(outbox.notSaved().map(\.reason) == ["Hister answered 429 5 times."])
    }

    @Test func aMisroutedServerIsRetriedNotDropped() async throws {
        let outbox = Outbox(directory: dir)
        try outbox.enqueue(page("https://a.example/"))
        // A proxy that answers 404 or 405 for api/add: the page waits.
        for status in [404, 405, 408] {
            StubProtocol.handle(Self.host) { _ in (status, Data()) }
            #expect(await outbox.drain(using: client) == .stopped(sent: 0))
        }
        #expect(outbox.status().count == 1)
        #expect(outbox.notSaved().isEmpty)
    }

    @Test func aBadRequestIsDroppedAndListed() async throws {
        let outbox = Outbox(directory: dir)
        try outbox.enqueue(page("https://a.example/"), now: Date(timeIntervalSince1970: 10))
        StubProtocol.handle(Self.host) { _ in (400, Data(#"{"error":"no url"}"#.utf8)) }
        #expect(await outbox.drain(using: client, now: Date(timeIntervalSince1970: 20)) == .sent(0))
        #expect(outbox.notSaved() == [Outbox.NotSaved(
            url: "https://a.example/", title: "T", reason: "Hister refused it: no url", date: Date(timeIntervalSince1970: 20))])
        outbox.clearNotSaved()
        #expect(outbox.notSaved().isEmpty)
    }

    @Test func theNotSavedListKeepsTheNewest() async throws {
        let outbox = Outbox(directory: dir)
        StubProtocol.handle(Self.host) { _ in (422, Data()) }
        for i in 0..<(Outbox.notSavedLimit + 5) {
            try outbox.enqueue(page("https://\(i).example/"), now: Date(timeIntervalSince1970: TimeInterval(i + 1)))
            await outbox.drain(using: client, now: Date(timeIntervalSince1970: TimeInterval(i + 1)))
        }
        let listed = outbox.notSaved()
        #expect(listed.count == Outbox.notSavedLimit)
        #expect(listed.first?.url == "https://\(Outbox.notSavedLimit + 4).example/")
    }

    @Test func aFullOutboxRefusesANewPageButTakesAReplacement() throws {
        let outbox = Outbox(directory: dir)
        let now = Date.now
        for i in 0..<Outbox.maxCount {
            try outbox.enqueue(page("https://\(i).example/"), now: now.addingTimeInterval(TimeInterval(i) / 1000))
        }
        #expect(throws: Outbox.Full.self) { try outbox.enqueue(page("https://more.example/")) }
        try outbox.enqueue(page("https://0.example/"))
        #expect(outbox.status().count == Outbox.maxCount)
        #expect(outbox.notSaved().isEmpty)
    }

    @Test func aPageTooBigForTheSpaceLeftIsRefused() throws {
        let outbox = Outbox(directory: dir)
        let big = String(repeating: "a", count: Outbox.maxBytes / 2 + 1)
        try outbox.enqueue(NewPage(url: "https://a.example/", title: "A", html: big, via: "share"))
        #expect(throws: Outbox.Full.self) {
            try outbox.enqueue(NewPage(url: "https://b.example/", title: "B", html: big, via: "share"))
        }
        #expect(outbox.status().count == 1)
    }

    @Test func pagesQueuedUnderTheOldNamesStillCount() async throws {
        let outbox = Outbox(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = Outbox.Entry(page: page("https://old-name.example/", added: 50), attempts: 0)
        try JSONEncoder().encode(old).write(to: dir.appending(path: "0000000050.000000-\(UUID().uuidString).json"))
        #expect(outbox.status() == Outbox.Status(count: 1, oldest: Date(timeIntervalSince1970: 50)))
        // Queued again: replaced, keeping its first time.
        try outbox.enqueue(page("https://old-name.example/"), now: Date(timeIntervalSince1970: 60))
        #expect(outbox.pages.map(\.added) == [50])
        StubProtocol.handle(Self.host) { _ in (201, Data()) }
        #expect(await outbox.drain(using: client, now: Date(timeIntervalSince1970: 70)) == .sent(1))
    }

    @Test func aFolderWithASpaceIsListed() async throws {
        // The Mac's App Group lives in "Group Containers".
        let spaced = dir.appending(path: "Group Containers", directoryHint: .isDirectory)
        let outbox = Outbox(directory: spaced)
        try outbox.enqueue(page("https://a.example/"))
        #expect(outbox.status().count == 1)
        StubProtocol.handle(Self.host) { _ in (201, Data()) }
        #expect(await outbox.drain(using: client) == .sent(1))
        #expect(outbox.status().count == 0)
    }

    @Test func aLinkThatMovedIsFoundUnderItsNewAddress() async throws {
        let outbox = Outbox(directory: dir)
        try outbox.enqueue(NewPage(url: "https://short.example/x", title: "", via: "share"))
        StubProtocol.handle(Self.host) { _ in (503, Data()) }
        await outbox.drain(using: client, fetch: { _ in
            PageFetcher.Fetched(url: "https://long.example/article", title: "Article", html: "<p>a</p>")
        })
        #expect(outbox.pages.map(\.url) == ["https://long.example/article"])
        // Saved again under the address it landed on: one page, not two.
        try outbox.enqueue(page("https://long.example/article"))
        #expect(outbox.status().count == 1)
    }
}
