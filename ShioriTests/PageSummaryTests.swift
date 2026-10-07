import Foundation
import HisterKit
import ShioriAI
import Testing

/// An engine that counts its calls and answers with a point; with a gate,
/// it waits until opened (whether or not it was cancelled meanwhile), so
/// a test can act while a summary is under way.
nonisolated final class RecordingEngine: AIEngine, @unchecked Sendable {
    let provider: AIProvider
    private let gated: Bool
    private let lock = NSLock()
    private var _calls = 0
    private var _sawCancel = false
    private var opened = false
    private var waiting: CheckedContinuation<Void, Never>?

    var calls: Int { lock.withLock { _calls } }
    /// The request it answered had been cancelled by then.
    var sawCancel: Bool { lock.withLock { _sawCancel } }

    init(_ provider: AIProvider = .appleIntelligence, gated: Bool = false) {
        self.provider = provider
        self.gated = gated
    }

    func respond(to request: AIRequest) async throws -> String {
        lock.withLock { _calls += 1 }
        if gated {
            await withCheckedContinuation { continuation in
                let go = lock.withLock {
                    if opened { return true }
                    waiting = continuation
                    return false
                }
                if go { continuation.resume() }
            }
        }
        lock.withLock { _sawCancel = Task.isCancelled }
        return "• a point"
    }

    func open() {
        let continuation = lock.withLock {
            opened = true
            defer { waiting = nil }
            return waiting
        }
        continuation?.resume()
    }

    /// Until a request has arrived (at most a second).
    func started() async throws {
        for _ in 0..<200 where calls == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(calls > 0)
    }
}

/// Summarize for the page on screen: where each kind of page may go, the
/// cache, Regenerate, and a result that comes back too late.
struct PageSummaryTests {
    /// The cache, in memory: what was written, and what reads back.
    final class Store {
        var kept: [String: Summary] = [:]
        var writes = 0
        var store: SummaryStore {
            SummaryStore(
                read: { url, _ in self.kept[url] },
                write: { summary, page, _ in
                    self.writes += 1
                    self.kept[page.url] = summary
                })
        }
    }

    let updated = Date(timeIntervalSince1970: 1_800_000_000)

    private func page(_ url: String, label: String = "") -> StoredPage {
        StoredPage(url: url, title: "Title", domain: "example.com", label: label, added: updated, updated: updated,
                   faviconKey: "", snippetHTML: "")
    }

    private var preview: PagePreview {
        PagePreview(title: "Title", contentHTML: "<p>Some words about the page.</p>", added: updated, updated: updated,
                    label: "", visits: 1, author: nil, summary: nil)
    }

    private func model(_ engines: [any AIEngine], store: Store = Store(), isPrivate: Bool = false,
                       asked: (@MainActor (String) -> Void)? = nil) -> PageSummary {
        PageSummary(
            chain: { EngineChain(engines) },
            isPrivateNow: { url in
                asked?(url)
                return isPrivate
            },
            store: store.store)
    }

    @Test func aPageIsSummarizedAndKept() async throws {
        let engine = RecordingEngine()
        let store = Store()
        let summary = model([engine], store: store)
        let doc = page("https://example.com/a")
        summary.reset(for: doc.url)
        summary.summarize(document: doc, preview: preview, isNote: false)
        #expect(summary.state == .working)
        await summary.task?.value
        guard case .done(let made) = summary.state else { Issue.record("not done: \(summary.state)"); return }
        #expect(made.text.contains("a point"))
        #expect(engine.calls == 1)
        #expect(store.writes == 1)
    }

    @Test func aNoteThatIsPrivateNowNeverReachesAnEngine() async throws {
        let apple = RecordingEngine(), local = RecordingEngine(.local), cloud = RecordingEngine(.anthropic)
        let store = Store()
        var asked: [String] = []
        let summary = model([apple, local, cloud], store: store, isPrivate: true, asked: { asked.append($0) })
        // Its address says nothing private (a shared vault): Kura's answer now does.
        let note = page("https://kura.example/v/team/n/plan", label: Notes.label)
        summary.reset(for: note.url)
        summary.summarize(document: note, preview: preview, isNote: true)
        await summary.task?.value
        #expect(asked == [note.url])
        #expect(apple.calls + local.calls + cloud.calls == 0)
        #expect(store.writes == 0)
        guard case .failed(let message) = summary.state else { Issue.record("not failed: \(summary.state)"); return }
        #expect(message.contains("never by an AI provider"))
    }

    @Test func aFileReachesNoEngine() async throws {
        let engine = RecordingEngine()
        var asked: [String] = []
        let summary = model([engine], asked: { asked.append($0) })
        let file = page("file:///srv/docs/a.pdf")
        summary.reset(for: file.url)
        summary.summarize(document: file, preview: preview, isNote: false)
        await summary.task?.value
        #expect(engine.calls == 0)
        #expect(asked.isEmpty)
        #expect(summary.state == .failed(AIError.noEngine.localizedDescription))
    }

    @Test func aCachedSummaryShowsWithNoEngineCall() async throws {
        let engine = RecordingEngine()
        let store = Store()
        let doc = page("https://example.com/a")
        let cached = Summary(text: "• from before", provider: .local, partial: false)
        store.kept[doc.url] = cached
        let summary = model([engine], store: store)
        summary.reset(for: doc.url)
        summary.showCached(url: doc.url, updated: updated)
        #expect(summary.state == .done(cached))
        summary.summarize(document: doc, preview: preview, isNote: false)
        #expect(summary.state == .done(cached))
        #expect(summary.task == nil)
        #expect(engine.calls == 0)
    }

    @Test func regenerateGoesPastTheCache() async throws {
        let engine = RecordingEngine()
        let store = Store()
        let doc = page("https://example.com/a")
        store.kept[doc.url] = Summary(text: "• from before", provider: .local, partial: false)
        let summary = model([engine], store: store)
        summary.reset(for: doc.url)
        summary.summarize(document: doc, preview: preview, isNote: false, fresh: true)
        await summary.task?.value
        #expect(engine.calls == 1)
        guard case .done(let made) = summary.state else { Issue.record("not done: \(summary.state)"); return }
        #expect(made.text.contains("a point"))
        #expect(store.kept[doc.url] == made)
    }

    @Test func aResultForThePageLeftBehindIsDropped() async throws {
        let engine = RecordingEngine(gated: true)
        let summary = model([engine])
        let first = page("https://example.com/a"), second = page("https://example.com/b")
        summary.reset(for: first.url)
        summary.summarize(document: first, preview: preview, isNote: false)
        let running = try #require(summary.task)
        try await engine.started()
        summary.reset(for: second.url)
        engine.open()
        await running.value
        #expect(summary.state == .none)
    }

    @Test func closeCancels() async throws {
        let engine = RecordingEngine(gated: true)
        let summary = model([engine])
        let doc = page("https://example.com/a")
        summary.reset(for: doc.url)
        summary.summarize(document: doc, preview: preview, isNote: false)
        let running = try #require(summary.task)
        try await engine.started()
        summary.close()
        #expect(summary.state == .none)
        engine.open()
        await running.value
        #expect(running.isCancelled)
        #expect(engine.sawCancel)
        #expect(summary.state == .none)
    }
}
