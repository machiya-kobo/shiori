import Foundation
import Testing

@testable import ShioriAI

@Suite struct AIContentTests {
    struct Flags: CustomTestStringConvertible, Sendable {
        var file = false, code = false, privateNote = false, note = false
        var testDescription: String { "file \(file), code \(code), private \(privateNote), note \(note)" }
    }

    /// Every combination of the four flags.
    static let every: [Flags] = (0..<16).map {
        Flags(file: $0 & 8 != 0, code: $0 & 4 != 0, privateNote: $0 & 2 != 0, note: $0 & 1 != 0)
    }

    /// The strictest flag wins: file, then code, then a private note, then a note.
    @Test(arguments: every) func theStrictestFlagDecides(_ flags: Flags) {
        let expected: AIContent =
            flags.file ? .localFile : flags.code ? .code : flags.privateNote ? .workNote : flags.note ? .note : .page
        #expect(AIContent.classify(
            isLocalFile: flags.file, isCode: flags.code, isPrivateNote: flags.privateNote, isNote: flags.note) == expected)
    }

    @Test func theTableByHand() {
        #expect(AIContent.classify(isLocalFile: false, isCode: false, isPrivateNote: false, isNote: false) == .page)
        #expect(AIContent.classify(isLocalFile: false, isCode: false, isPrivateNote: false, isNote: true) == .note)
        #expect(AIContent.classify(isLocalFile: false, isCode: false, isPrivateNote: true, isNote: true) == .workNote)
        // A private vault's note is private whatever its label says.
        #expect(AIContent.classify(isLocalFile: false, isCode: false, isPrivateNote: true, isNote: false) == .workNote)
        #expect(AIContent.classify(isLocalFile: false, isCode: true, isPrivateNote: true, isNote: true) == .code)
        #expect(AIContent.classify(isLocalFile: true, isCode: true, isPrivateNote: true, isNote: true) == .localFile)
    }

    /// The classification and `EngineChain.eligible` together, over the
    /// three kinds of engine: where each kind of document may go.
    @Test func whereEachKindMayGo() {
        let chain = EngineChain([
            FakeEngine(.appleIntelligence, .success("")), FakeEngine(.local, .success("")),
            FakeEngine(.anthropic, .success("")),
        ])
        func providers(file: Bool = false, code: Bool = false, privateNote: Bool = false, note: Bool = false) -> [AIProvider] {
            chain.eligible(for: .classify(isLocalFile: file, isCode: code, isPrivateNote: privateNote, isNote: note)).map(\.provider)
        }
        #expect(providers() == [.appleIntelligence, .local, .anthropic])
        #expect(providers(note: true) == [.appleIntelligence, .local])
        #expect(providers(code: true) == [.appleIntelligence])
        #expect(providers(privateNote: true, note: true).isEmpty)
        #expect(providers(privateNote: true).isEmpty)
        #expect(providers(file: true).isEmpty)
    }
}

@Suite struct SummaryFailureTests {
    @Test func aCancelledSummarySaysNothing() {
        #expect(Summarizer.failureMessage(CancellationError(), isNote: false) == nil)
        #expect(Summarizer.failureMessage(CancellationError(), isNote: true) == nil)
    }

    @Test func aNoteWithNoEngineSaysWhy() throws {
        let message = try #require(Summarizer.failureMessage(AIError.noEngine, isNote: true))
        #expect(message.contains("never by an AI provider"))
    }

    @Test func anythingElseSaysWhatWentWrong() {
        #expect(Summarizer.failureMessage(AIError.noEngine, isNote: false) == AIError.noEngine.localizedDescription)
        #expect(Summarizer.failureMessage(AIError.declined(nil), isNote: true) == AIError.declined(nil).localizedDescription)
        #expect(Summarizer.failureMessage(AIError.emptyContent, isNote: false) == AIError.emptyContent.localizedDescription)
    }
}
