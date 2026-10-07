import Foundation
import HisterKit
import Testing

/// Delete with Undo: nothing goes to Hister inside the window, a second
/// delete sends the first, a failure brings the page back, and a private
/// vault's note is never sent.
struct PendingDeletesTests {
    /// What was sent, in order; `fails` makes every send fail.
    final class Sent {
        var urls: [String] = []
        var fails: HisterError?
    }

    private func page(_ url: String) -> StoredPage {
        StoredPage(url: url, title: "Title", domain: "example.com", label: "", added: .now, updated: .now,
                   faviconKey: "", snippetHTML: "")
    }

    private func deletes(_ sent: Sent, window: Duration = .milliseconds(50)) -> PendingDeletes {
        PendingDeletes(
            send: { (document: StoredPage) async throws(HisterError) -> Void in
                if let failure = sent.fails { throw failure }
                sent.urls.append(document.url)
            },
            isPrivate: { $0.contains("/v/") },
            undoWindow: window,
            holdBackground: { {} })
    }

    /// Waits until `condition` holds, at most two seconds.
    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func anUndoInsideTheWindowNeverSends() async throws {
        let sent = Sent()
        let deletes = deletes(sent, window: .milliseconds(100))
        let doc = page("https://example.com/a")
        deletes.start(doc)
        #expect(deletes.hidden.contains(doc.url))
        #expect(deletes.pending?.document == doc)
        deletes.undo()
        #expect(deletes.pending == nil)
        #expect(!deletes.hidden.contains(doc.url))
        try await Task.sleep(for: .milliseconds(300))
        #expect(sent.urls.isEmpty)
    }

    @Test func aSecondDeleteSendsTheFirst() async throws {
        let sent = Sent()
        let deletes = deletes(sent, window: .seconds(60))
        let first = page("https://example.com/a"), second = page("https://example.com/b")
        deletes.start(first)
        deletes.start(second)
        #expect(deletes.pending?.document == second)
        try await until { !sent.urls.isEmpty }
        #expect(sent.urls == [first.url])
        #expect(deletes.hidden == [first.url, second.url])
    }

    @Test func onceTheWindowIsUpTheDeleteIsSent() async throws {
        let sent = Sent()
        let deletes = deletes(sent)
        let doc = page("https://example.com/a")
        deletes.start(doc)
        try await until { !sent.urls.isEmpty }
        #expect(sent.urls == [doc.url])
        #expect(deletes.pending == nil)
        // Gone for good: lists keep hiding it.
        #expect(deletes.hidden.contains(doc.url))
        #expect(deletes.failure == nil)
    }

    @Test func aFailureBringsThePageBackAndSaysWhy() async throws {
        let sent = Sent()
        sent.fails = .unreachable
        let deletes = deletes(sent)
        let doc = page("https://example.com/a")
        deletes.start(doc)
        try await until { deletes.failure != nil }
        #expect(deletes.failure == HisterError.unreachable.userMessage)
        #expect(!deletes.hidden.contains(doc.url))
        #expect(deletes.pending == nil)
    }

    @Test func aPrivateNoteIsRefused() async throws {
        let sent = Sent()
        let deletes = deletes(sent)
        deletes.start(page("https://kura.example/v/work/n/plan"))
        #expect(deletes.pending == nil)
        #expect(deletes.hidden.isEmpty)
        try await Task.sleep(for: .milliseconds(150))
        #expect(sent.urls.isEmpty)
    }

    @Test func committingSendsAtOnceAndHoldsTheBackgroundUntilDone() async throws {
        let sent = Sent()
        var held = 0, released = 0
        let deletes = PendingDeletes(
            send: { (document: StoredPage) async throws(HisterError) -> Void in sent.urls.append(document.url) },
            isPrivate: { _ in false },
            undoWindow: .seconds(60),
            holdBackground: {
                held += 1
                return { released += 1 }
            })
        let doc = page("https://example.com/a")
        deletes.start(doc)
        deletes.commit()
        #expect(held == 1)
        #expect(deletes.pending == nil)
        try await until { released == 1 }
        #expect(sent.urls == [doc.url])
        #expect(released == 1)
    }
}
