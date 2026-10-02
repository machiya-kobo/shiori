import Foundation
import Testing

@testable import ShioriAI

/// Answers every request with a fixed JSON, recording the request.
final class JSONEngine: AIEngine, @unchecked Sendable {
    let provider: AIProvider
    let answer: String
    private let lock = NSLock()
    private var _last: AIRequest?
    var last: AIRequest? { lock.withLock { _last } }

    init(_ provider: AIProvider = .appleIntelligence, answer: String) {
        self.provider = provider
        self.answer = answer
    }

    func respond(to request: AIRequest) async throws -> String {
        lock.withLock { _last = request }
        return answer
    }
}

@Suite struct LabelClassifierTests {
    let choices = [
        LabelChoice(name: "alpha", collections: ["@systems"]),
        LabelChoice(name: "vintage-tech", collections: ["@vintage"]),
        LabelChoice(name: "gamma"),
    ]

    func suggest(_ answer: String, text: String = "Version 15 is out.") async throws -> (LabelSuggestion, AIRequest?) {
        let engine = JSONEngine(answer: answer)
        let suggestion = try await LabelClassifier(chain: EngineChain([engine]))
            .suggest(title: "Sample OS", url: "https://www.os.example/", text: text, choices: choices, content: .page)
        return (suggestion, engine.last)
    }

    @Test func theRequestListsTheLabelsAndConstrainsTheAnswerToThem() async throws {
        let (_, request) = try await suggest(#"{"label":"alpha","second":"none","new_label":"","confidence":"high"}"#)
        let sent = try #require(request)
        #expect(sent.system.contains("- alpha (in @systems)"))
        #expect(sent.system.contains("- gamma\n") || sent.system.contains("- gamma\n") || sent.system.contains("- gamma"))
        #expect(sent.user.contains("Site: www.os.example"))
        #expect(sent.user.contains("<page>\nVersion 15 is out.\n</page>"))
        guard case .object(let schema)? = sent.schema, case .object(let properties)? = schema["properties"],
              case .object(let label)? = properties["label"], case .array(let allowed)? = label["enum"]
        else {
            Issue.record("no enum of labels")
            return
        }
        #expect(allowed == ["alpha", "vintage-tech", "gamma", "none"])
    }

    @Test func aGoodAnswerIsRead() async throws {
        let (suggestion, _) = try await suggest(#"{"label":"alpha","second":"vintage-tech","new_label":"","confidence":"high"}"#)
        #expect(suggestion == LabelSuggestion(labels: ["alpha", "vintage-tech"], newLabel: nil, confidence: .high, provider: .appleIntelligence))
    }

    @Test func labelsOffTheListAreIgnoredNotTrusted() async throws {
        let (suggestion, _) = try await suggest(#"{"label":"banking","second":"alpha","new_label":"","confidence":"high"}"#)
        #expect(suggestion.labels == ["alpha"])
    }

    @Test func noneWithANewLabelInTheUsersStyle() async throws {
        let (suggestion, _) = try await suggest(#"{"label":"none","second":"none","new_label":"Home Automation!","confidence":"medium"}"#)
        #expect(suggestion.labels.isEmpty)
        #expect(suggestion.newLabel == "home-automation")
    }

    @Test func aNewLabelThatAlreadyExistsIsTheExistingOne() async throws {
        let (suggestion, _) = try await suggest(#"{"label":"none","second":"none","new_label":"Gamma","confidence":"low"}"#)
        #expect(suggestion.labels == ["gamma"])
        #expect(suggestion.newLabel == nil)
    }

    @Test func onlyTheStartOfALongPageIsSent() async throws {
        let long = String(repeating: "A sentence about operating systems. ", count: 1_000)
        let (_, request) = try await suggest(#"{"label":"alpha","second":"none","new_label":"","confidence":"high"}"#, text: long)
        #expect(try #require(request).user.count < LabelClassifier.excerptLimit + 200)
    }

    @Test func anUnreadableAnswerIsAnError() async {
        await #expect(throws: AIError.badResponse) { try await suggest("alpha, I think") }
    }

    @Test func noLabelsNoRequest() async {
        let engine = JSONEngine(answer: "{}")
        await #expect(throws: AIError.self) {
            try await LabelClassifier(chain: EngineChain([engine])).suggest(title: "t", url: "u", text: "x", choices: [], content: .page)
        }
        #expect(engine.last == nil)
    }

    @Test func aDeclinedPageIsAskedAgainFromItsTitleAlone() async throws {
        let engine = DecliningEngine()
        let suggestion = try await LabelClassifier(chain: EngineChain([engine]))
            .suggest(title: "A Sample Article", url: "https://blog.example/post/", text: "Body that trips a guardrail.",
                     choices: choices, content: .page)
        #expect(suggestion.labels == ["alpha"])
        #expect(engine.users.count == 2)
        #expect(engine.users[1].contains(LabelClassifier.withheld))
        #expect(!engine.users[1].contains("Body that trips"))
    }
}

/// Declines anything with the page's text in it; answers from the title.
final class DecliningEngine: AIEngine, @unchecked Sendable {
    let provider = AIProvider.appleIntelligence
    private let lock = NSLock()
    private var _users: [String] = []
    var users: [String] { lock.withLock { _users } }

    func respond(to request: AIRequest) async throws -> String {
        lock.withLock { _users.append(request.user) }
        if !request.user.contains(LabelClassifier.withheld) { throw AIError.declined(nil) }
        return #"{"label":"alpha","second":"none","new_label":"","confidence":"medium"}"#
    }
}
