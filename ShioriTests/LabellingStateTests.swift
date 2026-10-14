import Foundation
import ShioriAI
import Testing

/// Label New Pages' saved state and the rules its runs go by.
struct LabellingStateTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "labelling-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func oneEntryThatDoesntReadLeavesTheRest() throws {
        // A newer build's provider, after a downgrade: that entry goes, not the file.
        let json = """
            {"seen":{"https://example.com/a":0},
             "applied":[{"url":"https://example.com/a","title":"A","label":"alpha","previous":"","by":"anthropic","at":0},
                        {"url":"https://example.com/b","title":"B","label":"beta","previous":"","by":"someNewEngine","at":0}],
             "pending":"not a list",
             "cloudCount":3}
            """
        let state = try JSONDecoder().decode(LabellingState.self, from: Data(json.utf8))
        #expect(state.applied.map(\.url) == ["https://example.com/a"])
        #expect(state.seen.keys.sorted() == ["https://example.com/a"])
        #expect(state.pending.isEmpty)
        #expect(state.cloudCount == 3)
        #expect(state.server == nil && !state.caughtUp)
    }

    @Test func aFileThatDoesntReadIsKeptAsideNotLost() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "labelling.json")
        for n in 0..<5 {
            try Data("[not json \(n)".utf8).write(to: file)
            LabellingStore.keepAside(file, now: Date(timeIntervalSince1970: 1_800_000_000 + Double(n)))
        }
        let kept = try FileManager.default.contentsOfDirectory(atPath: dir.path()).filter { $0.hasSuffix(".bak") }
        #expect(kept.count == LabellingStore.keptAside)
        #expect(kept.contains("labelling-1800000004.json.bak"))
        #expect(!FileManager.default.fileExists(atPath: file.path()))

        try Data("{".utf8).write(to: file)
        guard case .missing = LabellingStore.readNow(from: file) else { Issue.record("a bad file should read as empty"); return }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path()).filter { $0.hasSuffix(".bak") }.count == LabellingStore.keptAside)
    }

    @Test func missingIsEmptyAndUnreadableIsLeftAlone() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard case .missing = LabellingStore.readNow(from: dir.appending(path: "labelling.json")) else {
            Issue.record("no file should read as missing")
            return
        }
        // Something there that can't be read (here a folder): never treated
        // as empty, so nothing is written over it.
        let blocked = dir.appending(path: "blocked.json", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        guard case .unreadable = LabellingStore.readNow(from: blocked) else { Issue.record("should be unreadable"); return }
    }

    @Test func writtenStateReadsBack() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "AI/labelling.json")
        var state = LabellingState()
        state.seen["https://example.com/a"] = Date(timeIntervalSince1970: 1_800_000_000)
        state.server = "https://hister.example.com/"
        state.user = "someone"
        state.caughtUp = true
        LabellingStore.writeNow(state, to: file)
        guard case .read(let back) = LabellingStore.readNow(from: file) else { Issue.record("not read back"); return }
        #expect(back.seen == state.seen)
        #expect(back.server == state.server && back.user == state.user && back.caughtUp)
    }

    @Test func everyListIsBounded() {
        var state = LabellingState()
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        state.pending = (0..<600).map {
            PendingSuggestion(url: "https://example.com/\($0)", title: "", labels: ["a"], newLabel: nil, at: at.addingTimeInterval(Double($0)))
        }
        state.applied = (0..<1_200).map {
            AppliedLabel(url: "https://example.com/\($0)", title: "", label: "a", previous: "", by: .appleIntelligence, at: at)
        }
        state.seen = Dictionary(uniqueKeysWithValues: (0..<5_001).map { ("https://example.com/\($0)", at.addingTimeInterval(Double($0))) })
        state.trim()
        #expect(state.pending.count == 500)
        #expect(state.pending.contains { $0.url == "https://example.com/599" })
        #expect(state.applied.count == LabellingState.appliedKept)
        #expect(state.seen.count == 4_000)
        #expect(state.seen["https://example.com/5000"] != nil)
    }

    @Test func anotherServerOrUserStartsOverSigningOutDoesnt() {
        let server = "https://hister.example.com/"
        #expect(!LabellingOwner.changed(fromServer: nil, user: nil, toServer: server, user: "someone"))
        #expect(!LabellingOwner.changed(fromServer: server, user: "someone", toServer: server, user: nil))
        #expect(!LabellingOwner.changed(fromServer: server, user: "someone", toServer: server, user: "someone"))
        #expect(!LabellingOwner.changed(fromServer: server, user: nil, toServer: server, user: "someone"))
        #expect(LabellingOwner.changed(fromServer: server, user: "someone", toServer: server, user: "another"))
        #expect(LabellingOwner.changed(fromServer: server, user: nil, toServer: "https://other.example.com/", user: nil))
    }

    @Test func runsAreFifteenMinutesApartWhateverTheForeground() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(LabellingSchedule.firstWait(after: nil, now: now) == 20)
        #expect(LabellingSchedule.firstWait(after: now.addingTimeInterval(-60), now: now) == 14 * 60)
        #expect(LabellingSchedule.firstWait(after: now.addingTimeInterval(-3_600), now: now) == 20)
    }

    @Test func aRefusedKeyStopsTheRunADeclinedPageDoesnt() {
        #expect(LabelFailure(AIError.badStatus(401, nil)) == .stop)
        #expect(LabelFailure(AIError.badStatus(404, "no such model")) == .stop)
        #expect(LabelFailure(AIError.badResponse) == .stop)
        #expect(LabelFailure(AIError.cutShort("")) == .stop)
        #expect(LabelFailure(URLError(.notConnectedToInternet)) == .stop)
        #expect(LabelFailure(AIError.busy("busy")) == .stop)
        #expect(LabelFailure(AIError.declined(nil)) == .thisPage)
        #expect(LabelFailure(AIError.noEngine) == .thisPage)
    }

    @Test func undoTakesOutOnlyWhatTheEditAdded() {
        let edit = CollectionEdit(keyword: "@tech", previous: "label:(a|b)", value: "label:(a|b|c)", summary: "", automatic: true, at: Date())
        #expect(AliasUndo(edit, previous: "label:(a|b)", current: "label:(a|b|c)") == .write("label:(a|b)"))
        // Another label added since: it stays.
        #expect(AliasUndo(edit, previous: "label:(a|b)", current: "label:(a|b|c|d)") == .write("label:(a|b|d)"))
        #expect(AliasUndo(edit, previous: "label:(a|b)", current: "label:(a|b)") == .nothing)
        #expect(AliasUndo(edit, previous: "label:(a|b)", current: nil) == .nothing)
        #expect(AliasUndo(edit, previous: "label:(a|b)", current: "label:(a|d)") == .nothing)
        #expect(AliasUndo(edit, previous: "label:(a|b)", current: "label:(a|c) domain:x.example") == .cannot)
    }
}
