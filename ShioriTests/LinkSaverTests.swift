import Foundation
import HisterKit
import Testing

/// Save This Note's Links, one link at a time: never a page Hister holds,
/// skip rules unless Save Anyway, the note recorded, the outbox when
/// Hister is away.
@Suite(.serialized)
struct LinkSaverTests {
    static let host = "linksaver.example"
    let client: HisterClient
    let outbox: Outbox
    let link = LinkToSave(url: "https://a.example/post", text: "A post", notePath: "Notes/Sample.md", noteTitle: "Sample")
    let fetch: @Sendable (URL) async throws -> PageFetcher.Fetched = { url in
        PageFetcher.Fetched(url: url.absoluteString, title: "A post", html: "<p>hi</p>")
    }

    init() {
        client = HisterClient(serverURL: "https://\(Self.host)/", session: StubProtocol.session())!
        StubProtocol.reset(Self.host)
        outbox = Outbox(directory: FileManager.default.temporaryDirectory.appending(path: "linksaver-\(UUID().uuidString)"))
    }

    /// Hister: a search finds `known`; an add answers `status`.
    func hister(known: [String] = [], add status: Int = 201) {
        StubProtocol.handle(Self.host) { request in
            if request.url!.path().hasSuffix("/search") || request.url!.path() == "/search" {
                let docs = known.map { #"{"url":"\#($0)","title":"T","domain":"a.example","label":"","added":1,"updated":1,"favicon_key":""}"# }
                return (200, Data(#"{"total":\#(known.count),"documents":[\#(docs.joined(separator: ","))]}"#.utf8))
            }
            return (status, status == 406 ? Data(#"{"error":"skip rule"}"#.utf8) : Data())
        }
    }

    func adds() -> [[String: Any]] {
        StubProtocol.requests(Self.host).filter { $0.url?.path() == "/api/add" }.compactMap {
            $0.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    @Test func savedWithTheNoteRecordedAndSkipRulesHeld() async throws {
        hister()
        let outcome = await Saver.saveLink(link, label: "games", anyway: false, client: client, outbox: outbox, fetch: fetch)
        #expect(outcome == .saved)
        let body = try #require(adds().first)
        #expect(body["label"] as? String == "games")
        let metadata = try #require(body["metadata"] as? [String: Any])
        #expect(metadata["via"] as? String == "note-links")
        #expect(metadata["from_note"] as? String == "Notes/Sample.md")
        #expect(metadata["ignore_skip_rules"] == nil)
    }

    @Test func aPageHisterHoldsIsNeverSent() async {
        hister(known: ["https://a.example/post"])
        #expect(await Saver.saveLink(link, label: nil, anyway: false, client: client, outbox: outbox, fetch: fetch) == .alreadyInHister)
        #expect(adds().isEmpty)
    }

    @Test func norUnderTheAddressItRedirectsTo() async {
        hister(known: ["https://b.example/final"])
        let redirected: @Sendable (URL) async throws -> PageFetcher.Fetched = { _ in
            PageFetcher.Fetched(url: "https://b.example/final", title: "B", html: "<p>b</p>")
        }
        #expect(await Saver.saveLink(link, label: nil, anyway: false, client: client, outbox: outbox, fetch: redirected) == .alreadyInHister)
        #expect(adds().isEmpty)
    }

    @Test func aSkipRuleWaitsForSaveAnyway() async throws {
        hister(add: 406)
        let outcome = await Saver.saveLink(link, label: nil, anyway: false, client: client, outbox: outbox, fetch: fetch)
        #expect(outcome == .skipped("Hister skips this site."))
        hister()
        #expect(await Saver.saveLink(link, label: nil, anyway: true, client: client, outbox: outbox, fetch: fetch) == .saved)
        let metadata = try #require(adds().last?["metadata"] as? [String: Any])
        #expect(metadata["ignore_skip_rules"] as? Bool == true)
    }

    @Test func outOfReachItWaitsInTheOutbox() async {
        hister(add: 503)
        #expect(await Saver.saveLink(link, label: nil, anyway: false, client: client, outbox: outbox, fetch: fetch) == .queued)
        #expect(outbox.status().count == 1)
    }

    @Test func aFileIsNeverFetchedOrSaved() async {
        hister()
        let deb = LinkToSave(url: "https://example.org/pool/x_1.0_armhf.deb", text: "", notePath: "N.md", noteTitle: "N")
        #expect(await Saver.saveLink(deb, label: nil, anyway: false, client: client, outbox: outbox, fetch: fetch)
            == .failed("A file, not a web page: not saved."))
        let notHTML: @Sendable (URL) async throws -> PageFetcher.Fetched = { url in PageFetcher.Fetched(url: url.absoluteString, title: "", html: "") }
        #expect(await Saver.saveLink(link, label: nil, anyway: false, client: client, outbox: outbox, fetch: notHTML)
            == .failed("A file, not a web page: not saved."))
        #expect(adds().isEmpty)
    }

    @Test func plainHTTPIsTriedAsHTTPSFirst() async throws {
        hister()
        let short = LinkToSave(url: "http://go.example/docs", text: "", notePath: "N.md", noteTitle: "N")
        let tried = Tried()
        let onlyHTTPS: @Sendable (URL) async throws -> PageFetcher.Fetched = { url in
            await tried.add(url.absoluteString)
            guard url.scheme == "https" else { throw URLError(.appTransportSecurityRequiresSecureConnection) }
            return PageFetcher.Fetched(url: "https://docs.example/config", title: "Config", html: "<p>c</p>")
        }
        #expect(await Saver.saveLink(short, label: nil, anyway: false, client: client, outbox: outbox, fetch: onlyHTTPS) == .saved)
        #expect(await tried.all == ["https://go.example/docs"])
        #expect(adds().first?["url"] as? String == "https://docs.example/config")
    }

    actor Tried {
        var all: [String] = []
        func add(_ url: String) { all.append(url) }
    }

    // MARK: gemini:// and gopher:// through the small-web gateway (a fake)

    static let gateway = "linksaver-smallweb.example"
    let gemini = LinkToSave(url: "gemini://Example.org:1965/log/", text: "", notePath: "N.md", noteTitle: "N")
    let noWait: @Sendable (Duration) async -> Void = { _ in }

    func smallweb(_ answers: [(Int, String)]) -> SmallWebClient {
        StubProtocol.reset(Self.gateway)
        let queue = Answers(answers)
        StubProtocol.handle(Self.gateway) { request in
            #expect(request.url?.path() == "/api/save")
            #expect(request.value(forHTTPHeaderField: "Origin") == "hister://")
            let (status, body) = queue.next()
            return (status, Data(body.utf8))
        }
        return SmallWebClient(serverURL: "https://\(Self.gateway)/", session: StubProtocol.session())!
    }

    nonisolated final class Answers: @unchecked Sendable {
        private var list: [(Int, String)]
        private let lock = NSLock()
        init(_ list: [(Int, String)]) { self.list = list }
        func next() -> (Int, String) { lock.withLock { list.count > 1 ? list.removeFirst() : list[0] } }
    }

    @Test func aGeminiLinkGoesToTheGatewayNeverHere() async throws {
        hister()
        let gateway = smallweb([(202, #"{"queued": true, "url": "gemini://example.org/log/"}"#)])
        let outcome = await Saver.saveLink(gemini, label: nil, anyway: false, client: client, outbox: outbox, smallweb: gateway, wait: noWait)
        #expect(outcome == .viaGateway("gemini://example.org/log/"))
        #expect(adds().isEmpty)
        let body = try #require(StubProtocol.requests(Self.gateway).first?.httpBody)
        #expect((try JSONSerialization.jsonObject(with: body) as? [String: String])?["url"] == "gemini://Example.org:1965/log/")
    }

    @Test func aGeminiPageHisterHoldsIsNotSent() async {
        hister(known: ["gemini://example.org/log/"])
        let gateway = smallweb([(202, "{}")])
        #expect(await Saver.saveLink(gemini, label: nil, anyway: false, client: client, outbox: outbox, smallweb: gateway, wait: noWait) == .alreadyInHister)
        #expect(StubProtocol.requests(Self.gateway).isEmpty)
    }

    @Test func aFullGatewayIsWaitedOut() async {
        hister()
        let gateway = smallweb([(429, "{}"), (429, "{}"), (202, #"{"queued": true, "url": "gemini://example.org/log/"}"#)])
        #expect(await Saver.saveLink(gemini, label: nil, anyway: false, client: client, outbox: outbox, smallweb: gateway, wait: noWait)
            == .viaGateway("gemini://example.org/log/"))
        #expect(StubProtocol.requests(Self.gateway).count == 3)
    }

    @Test func withoutTheGatewayNothingIsSent() async {
        hister()
        #expect(await Saver.saveLink(gemini, label: nil, anyway: false, client: client, outbox: outbox, smallweb: nil, wait: noWait)
            == .failed("Needs the small-web gateway (Settings → Search)."))
        #expect(adds().isEmpty)
    }

    @Test func theBatchLabelWaitsForTheGatewaysSave() async throws {
        hister(known: ["gemini://example.org/log/"])
        #expect(await Saver.labelWhenSaved("gemini://example.org/log/", label: "smallweb", client: client, wait: noWait))
        let request = try #require(StubProtocol.requests(Self.host).first { $0.url?.path() == "/api/label" })
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body?["label"] == "smallweb")
        #expect(body?["url"] == "gemini://example.org/log/")
        hister()
        #expect(!(await Saver.labelWhenSaved("gemini://example.org/other", label: "smallweb", client: client, tries: 2, wait: noWait)))
    }

    @Test func aPageThatWontDownloadIsntSaved() async {
        hister()
        let broken: @Sendable (URL) async throws -> PageFetcher.Fetched = { _ in throw URLError(.badServerResponse) }
        #expect(await Saver.saveLink(link, label: nil, anyway: false, client: client, outbox: outbox, fetch: broken)
            == .failed("Couldn't download this page."))
        #expect(adds().isEmpty)
    }
}
