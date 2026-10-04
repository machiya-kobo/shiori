import Foundation
import Testing

@testable import ShioriAI

/// An engine that answers, or fails, as told, and counts its calls.
final class FakeEngine: AIEngine, @unchecked Sendable {
    let provider: AIProvider
    let result: Result<String, Error>
    private let lock = NSLock()
    private var _calls = 0
    var calls: Int { lock.withLock { _calls } }

    init(_ provider: AIProvider, _ result: Result<String, Error>) {
        self.provider = provider
        self.result = result
    }

    func respond(to request: AIRequest) async throws -> String {
        lock.withLock { _calls += 1 }
        return try result.get()
    }
}

@Suite struct EngineChainTests {
    let page = AIRequest(system: "s", user: "u", content: .page)
    let note = AIRequest(system: "s", user: "u", content: .note)

    @Test func theFirstEngineThatAnswersWins() async throws {
        let apple = FakeEngine(.appleIntelligence, .success("on device"))
        let cloud = FakeEngine(.anthropic, .success("cloud"))
        let answer = try await EngineChain([apple, cloud]).respond(to: page)
        #expect(answer == AIAnswer(text: "on device", provider: .appleIntelligence))
        #expect(cloud.calls == 0)
    }

    @Test func anEngineThatCantAnswerHandsOnAndTheAnswerSaysWho() async throws {
        let apple = FakeEngine(.appleIntelligence, .failure(AIError.unavailable("Apple Intelligence is off.")))
        let cloud = FakeEngine(.anthropic, .success("cloud"))
        #expect(try await EngineChain([apple, cloud]).respond(to: page) == AIAnswer(text: "cloud", provider: .anthropic))
    }

    @Test func aWrongAnswerIsShownNotRoutedAround() async {
        let apple = FakeEngine(.appleIntelligence, .failure(AIError.badResponse))
        let cloud = FakeEngine(.anthropic, .success("cloud"))
        await #expect(throws: AIError.badResponse) { try await EngineChain([apple, cloud]).respond(to: page) }
        #expect(cloud.calls == 0)
    }

    @Test func aNoteNeverReachesACloudEngine() async {
        let apple = FakeEngine(.appleIntelligence, .failure(AIError.unavailable("off")))
        let anthropic = FakeEngine(.anthropic, .success("cloud"))
        let openAI = FakeEngine(.openAI, .success("cloud"))
        await #expect(throws: AIError.unavailable("off")) {
            try await EngineChain([apple, anthropic, openAI]).respond(to: note)
        }
        #expect(anthropic.calls == 0 && openAI.calls == 0)
    }

    @Test func aNoteWithOnlyCloudEnginesHasNoEngine() async {
        let cloud = FakeEngine(.openAI, .success("cloud"))
        await #expect(throws: AIError.noEngine) { try await EngineChain([cloud]).respond(to: note) }
        #expect(cloud.calls == 0)
    }

    @Test func aWorkNoteReachesNoEngineNotEvenOnTheDevice() async {
        let apple = FakeEngine(.appleIntelligence, .success("on device"))
        let local = FakeEngine(.local, .success("home"))
        let work = AIRequest(system: "s", user: "u", content: .workNote)
        await #expect(throws: AIError.noEngine) { try await EngineChain([apple, local]).respond(to: work) }
        #expect(apple.calls == 0 && local.calls == 0)
    }

    @Test func aLocalFileReachesNoEngineNotEvenOnTheDevice() async {
        let apple = FakeEngine(.appleIntelligence, .success("on device"))
        let local = FakeEngine(.local, .success("home"))
        let cloud = FakeEngine(.anthropic, .success("cloud"))
        let file = AIRequest(system: "s", user: "u", content: .localFile)
        await #expect(throws: AIError.noEngine) { try await EngineChain([apple, local, cloud]).respond(to: file) }
        #expect(apple.calls == 0 && local.calls == 0 && cloud.calls == 0)
        #expect(EngineChain([apple, local, cloud]).eligible(for: .localFile).isEmpty)
    }

    @Test func aNoteMayUseALocalServer() async throws {
        let local = FakeEngine(.local, .success("home"))
        #expect(try await EngineChain([local]).respond(to: note).provider == .local)
    }

    @Test func whenEveryEngineFailsTheLastReasonIsGiven() async {
        let apple = FakeEngine(.appleIntelligence, .failure(AIError.unavailable("off")))
        let cloud = FakeEngine(.anthropic, .failure(URLError(.notConnectedToInternet)))
        await #expect(throws: URLError.self) { try await EngineChain([apple, cloud]).respond(to: page) }
    }

    @Test func noEnginesIsNoEngine() async {
        await #expect(throws: AIError.noEngine) { try await EngineChain([]).respond(to: page) }
    }
}

@Suite struct ConnectionTestTests {
    static let host = "conn.test"

    func client(_ model: String) -> AnthropicClient {
        AnthropicClient(apiKey: "k", model: model, baseURL: URL(string: "https://\(Self.host)/v1")!, session: StubProtocol.session)
    }

    @Test func anOfferedModelIsAskedOnce() async throws {
        StubProtocol.handle(Self.host) { request in
            request.url!.path().hasSuffix("/models")
                ? (200, Data(#"{"data":[{"id":"claude-sonnet-5-5"}],"has_more":false}"#.utf8))
                : (200, Data(#"{"content":[{"type":"text","text":"OK"}],"stop_reason":"end_turn"}"#.utf8))
        }
        guard case .answered(let model, _) = try await ConnectionTest.run(client("claude-sonnet-5-5")) else {
            Issue.record("expected an answer")
            return
        }
        #expect(model == "claude-sonnet-5-5")
        let ping = try #require(StubProtocol.requests(Self.host).last)
        let body = try json(ping.httpBody)
        #expect(body["system"] as? String == ConnectionTest.ping.system)
    }

    @Test func aModelTheProviderDoesntOfferIsNamedWithTheNearestOnes() async throws {
        StubProtocol.handle("conn2.test") { _ in
            (200, Data(#"{"data":[{"id":"claude-opus-5-5"},{"id":"claude-sonnet-5"},{"id":"claude-haiku-4-5"}],"has_more":false}"#.utf8))
        }
        let client = AnthropicClient(
            apiKey: "k", model: "claude-sonnet-5-5", baseURL: URL(string: "https://conn2.test/v1")!, session: StubProtocol.session)
        let outcome = try await ConnectionTest.run(client)
        #expect(outcome == .modelNotOffered(model: "claude-sonnet-5-5", nearest: ["claude-sonnet-5", "claude-opus-5-5", "claude-haiku-4-5"]))
        #expect(StubProtocol.requests("conn2.test").count == 1)  // no message sent
    }
}
