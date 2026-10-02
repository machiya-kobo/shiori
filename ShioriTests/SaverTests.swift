import Foundation
import HisterKit
import Testing

/// The one save path behind the share sheet, the shortcut and the app's
/// Save: what's saved, what waits, what's given up on.
@Suite(.serialized)
struct SaverTests {
    static let host = "saver.example"
    let client: HisterClient
    let outbox: Outbox
    let input = Saver.Input(url: URL(string: "https://a.example/post")!, title: "A post", html: "<p>hi</p>", text: "hi")

    init() {
        client = HisterClient(serverURL: "https://\(Self.host)/", session: StubProtocol.session())!
        StubProtocol.reset(Self.host)
        outbox = Outbox(directory: FileManager.default.temporaryDirectory.appending(path: "saver-\(UUID().uuidString)"))
    }

    @Test func savedWhenHisterTakesIt() async throws {
        StubProtocol.handle(Self.host) { _ in (201, Data()) }
        let outcome = await Saver.save(input, label: "books", via: "share", client: client, outbox: outbox)
        #expect(outcome == .saved)
        #expect(outbox.status().count == 0)
        let request = try #require(StubProtocol.requests(Self.host).first)
        #expect(request.url?.path() == "/api/add")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(body?["url"] as? String == "https://a.example/post")
        #expect(body?["label"] as? String == "books")
        #expect((body?["metadata"] as? [String: Any])?["via"] as? String == "share")
    }

    @Test func aRefusalForGoodIsRejectedNotQueued() async {
        StubProtocol.handle(Self.host) { _ in (422, Data(#"{"error":"sensitive content"}"#.utf8)) }
        let outcome = await Saver.save(input, label: nil, via: "share", client: client, outbox: outbox)
        // The client's own sentence for a 422, not the server's.
        guard case .rejected(let reason) = outcome else {
            Issue.record("Expected a rejection, got \(outcome)")
            return
        }
        #expect(reason.contains("sensitive"))
        #expect(outbox.status().count == 0)
    }

    @Test func outOfReachQueuesThePageWithItsTime() async throws {
        StubProtocol.handle(Self.host) { _ in throw URLError(.cannotFindHost) }
        let outcome = await Saver.save(input, label: "books", via: "shortcut", client: client, outbox: outbox)
        #expect(outcome == .queued)
        let waiting = try #require(outbox.pages.first)
        #expect(waiting.url == "https://a.example/post")
        #expect(waiting.label == "books")
        #expect(waiting.added != nil)
    }

    @Test func aBrokenServerQueuesToo() async {
        StubProtocol.handle(Self.host) { _ in (503, Data()) }
        #expect(await Saver.save(input, label: nil, via: "app", client: client, outbox: outbox) == .queued)
        #expect(outbox.status().count == 1)
    }

    @Test func aBadRequestFailsWithoutQueueing() async {
        StubProtocol.handle(Self.host) { _ in (400, Data(#"{"error":"no url"}"#.utf8)) }
        let outcome = await Saver.save(input, label: nil, via: "app", client: client, outbox: outbox)
        #expect(outcome == .failed("no url"))
        #expect(outbox.status().count == 0)
    }

    @Test func cancellingSavesNothingAndQueuesNothing() async {
        StubProtocol.handle(Self.host) { _ in (201, Data()) }
        let save = Task { await Saver.save(input, label: nil, via: "share", client: client, outbox: outbox) }
        // Cancelled before it runs: the request is refused as cancelled,
        // and that must not read as "Hister is out of reach".
        save.cancel()
        #expect(await save.value == .cancelled)
        #expect(outbox.status().count == 0)
    }

    @Test func withNowhereToQueueItSaysSo() async {
        StubProtocol.handle(Self.host) { _ in throw URLError(.notConnectedToInternet) }
        let outcome = await Saver.save(input, label: nil, via: "share", client: client, outbox: nil)
        #expect(outcome == .failed("Hister is out of reach, and the page couldn't be kept for later."))
    }
}
