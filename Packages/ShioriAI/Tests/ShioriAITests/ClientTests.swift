import Foundation
import Testing

@testable import ShioriAI

/// Serves canned replies and records requests, per host, so suites that
/// run in parallel (each with its own host) never see each other's.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var recorded: [String: [URLRequest]] = [:]

    static func handle(_ host: String, _ handler: @escaping Handler) {
        lock.withLock {
            handlers[host] = handler
            recorded[host] = []
        }
    }

    static func requests(_ host: String) -> [URLRequest] {
        lock.withLock { recorded[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            request.httpBody = data
        }
        let host = request.url?.host() ?? ""
        let handler = Self.lock.withLock { () -> Handler? in
            Self.recorded[host, default: []].append(request)
            return Self.handlers[host]
        }
        do {
            guard let handler else { throw URLError(.cannotFindHost) }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }
}

func json(_ data: Data?) throws -> [String: Any] {
    let data = try #require(data)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

let labelSchema: JSONValue = [
    "type": "object",
    "properties": ["label": ["type": "string"]],
    "required": ["label"],
    "additionalProperties": false,
]

@Suite struct AnthropicClientTests {
    static let host = "anthropic.test"
    let base = URL(string: "https://\(Self.host)/v1")!

    func client(key: String = "sk-test", model: String = "claude-sonnet-5-5") -> AnthropicClient {
        AnthropicClient(apiKey: key, model: model, baseURL: base, session: StubProtocol.session)
    }

    @Test func requestCarriesTheHeadersAndNoSamplingOrPrefill() throws {
        let request = try client().urlRequest(
            for: AIRequest(system: "Pick a label.", user: "<page>x</page>", maxTokens: 300, schema: labelSchema, content: .page))
        #expect(request.url?.absoluteString == "https://anthropic.test/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try json(request.httpBody)
        #expect(body["model"] as? String == "claude-sonnet-5-5")
        #expect(body["max_tokens"] as? Int == 300)
        #expect(body["system"] as? String == "Pick a label.")
        #expect(body["temperature"] == nil)
        #expect(body["thinking"] == nil)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1)  // no prefilled assistant turn
        #expect(messages[0]["role"] as? String == "user")
        let format = try #require((body["output_config"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect((format["schema"] as? [String: Any])?["required"] as? [String] == ["label"])
    }

    @Test func plainTextAsksForNoFormat() throws {
        let request = try client().urlRequest(for: AIRequest(system: "s", user: "u", content: .none))
        #expect(try json(request.httpBody)["output_config"] == nil)
    }

    @Test func theSameRequestIsTheSameBytes() throws {
        let request = AIRequest(system: "s", user: "u", schema: labelSchema, content: .page)
        #expect(try client().urlRequest(for: request).httpBody == client().urlRequest(for: request).httpBody)
    }

    @Test func noKeyIsUnavailableSoTheNextEngineTries() {
        #expect(throws: AIError.unavailable("No Anthropic API key.")) {
            try client(key: "  ").urlRequest(for: AIRequest(system: "s", user: "u", content: .none))
        }
        #expect(AIReachability.mayFallThrough(AIError.unavailable("x")))
    }

    @Test func textJoinsTheTextBlocksAndDropsAFence() throws {
        let reply = """
            {"content":[{"type":"thinking","thinking":""},{"type":"text","text":"```json\\n{\\"label\\":\\"alpha\\"}\\n```"}],"stop_reason":"end_turn"}
            """
        #expect(try AnthropicClient.text(from: Data(reply.utf8)) == #"{"label":"alpha"}"#)
    }

    @Test func aRefusalIsDeclinedNotAnAnswer() {
        let reply = #"{"content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","category":null,"explanation":"No."}}"#
        #expect(throws: AIError.declined("No.")) { try AnthropicClient.text(from: Data(reply.utf8)) }
    }

    @Test func anErrorBodyGivesItsMessage() async {
        StubProtocol.handle(Self.host) { _ in
            (400, Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"model: not found"}}"#.utf8))
        }
        await #expect(throws: AIError.badStatus(400, "model: not found")) {
            try await client().respond(to: AIRequest(system: "s", user: "u", content: .none))
        }
    }

    @Test func modelsFollowThePages() async throws {
        let host = "anthropic-models.test"
        StubProtocol.handle(host) { request in
            let after = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "after_id" }?.value
            let body =
                after == nil
                ? #"{"data":[{"id":"claude-opus-5-5"},{"id":"claude-sonnet-5-5"}],"has_more":true,"last_id":"claude-sonnet-5-5"}"#
                : #"{"data":[{"id":"claude-haiku-4-5"}],"has_more":false,"last_id":"claude-haiku-4-5"}"#
            return (200, Data(body.utf8))
        }
        let client = AnthropicClient(
            apiKey: "k", model: "claude-sonnet-5-5", baseURL: URL(string: "https://\(host)/v1")!, session: StubProtocol.session)
        #expect(try await client.models() == ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"])
        let requests = StubProtocol.requests(host)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01" })
    }
}

@Suite struct AnthropicCachingTests {
    @Test func aRepeatedSystemPromptIsMarkedForCachingAndAOneOffIsNot() throws {
        let client = AnthropicClient(apiKey: "k", model: "claude-sonnet-5-5", session: StubProtocol.session)
        let cached = try json(try client.urlRequest(for: AIRequest(system: "labels", user: "page", content: .page, cacheSystem: true)).httpBody)
        let blocks = try #require(cached["system"] as? [[String: Any]])
        #expect(blocks.count == 1)
        #expect(blocks[0]["type"] as? String == "text")
        #expect(blocks[0]["text"] as? String == "labels")
        #expect((blocks[0]["cache_control"] as? [String: Any])?["type"] as? String == "ephemeral")
        let plain = try json(try client.urlRequest(for: AIRequest(system: "summary", user: "page", content: .page)).httpBody)
        #expect(plain["system"] as? String == "summary")
    }

    @Test func usageCountsTheCacheReads() {
        let reply = #"{"content":[{"type":"text","text":"x"}],"usage":{"input_tokens":620,"output_tokens":40,"cache_read_input_tokens":3100,"cache_creation_input_tokens":0}}"#
        let usage = AnthropicClient.usage(from: Data(reply.utf8))
        #expect(usage?.input == 620 && usage?.cacheRead == 3100 && usage?.cacheWrite == 0 && usage?.output == 40)
        #expect(AnthropicClient.usage(from: Data(#"{"content":[]}"#.utf8)) == nil)
    }
}

@Suite struct OpenAICompatibleClientTests {
    static let host = "openai.test"

    @Test func openAIUsesMaxCompletionTokensAndAStrictSchema() throws {
        let client = OpenAICompatibleClient(
            provider: .openAI, baseURL: URL(string: "https://\(Self.host)/v1")!, apiKey: "sk-o", model: "gpt-6-luna",
            session: StubProtocol.session)
        let request = try client.urlRequest(
            for: AIRequest(system: "sys", user: "usr", maxTokens: 200, schema: labelSchema, content: .page))
        #expect(request.url?.absoluteString == "https://openai.test/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-o")
        let body = try json(request.httpBody)
        #expect(body["max_completion_tokens"] as? Int == 200)
        #expect(body["max_tokens"] == nil)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user"])
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["json_schema"] as? [String: Any])
        #expect(schema["strict"] as? Bool == true)
        #expect(schema["name"] as? String == "answer")
    }

    @Test func aLocalServerUsesMaxTokensAndNoEmptyBearer() throws {
        let client = OpenAICompatibleClient(
            localBaseURL: URL(string: "http://ollama.test:11434/v1")!, apiKey: "", model: "qwen3", session: StubProtocol.session)
        let request = try client.urlRequest(for: AIRequest(system: "s", user: "u", maxTokens: 64, content: .none))
        #expect(request.url?.absoluteString == "http://ollama.test:11434/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try json(request.httpBody)
        #expect(body["max_tokens"] as? Int == 64)
        #expect(body["max_completion_tokens"] == nil)
        #expect(client.provider == .local && !client.provider.isCloud)
    }

    @Test func openAIWithoutAKeyIsUnavailable() {
        let client = OpenAICompatibleClient(apiKey: "", model: "gpt-6-luna")
        #expect(throws: AIError.unavailable("No OpenAI API key.")) {
            try client.urlRequest(for: AIRequest(system: "s", user: "u", content: .none))
        }
    }

    @Test func textReadsTheFirstChoiceAndTheRefusals() throws {
        let ok = #"{"choices":[{"message":{"role":"assistant","content":"{\"label\":\"gamma\"}"},"finish_reason":"stop"}]}"#
        #expect(try OpenAICompatibleClient.text(from: Data(ok.utf8)) == #"{"label":"gamma"}"#)
        let refused = #"{"choices":[{"message":{"role":"assistant","content":null,"refusal":"Can't help."},"finish_reason":"stop"}]}"#
        #expect(throws: AIError.declined("Can't help.")) { try OpenAICompatibleClient.text(from: Data(refused.utf8)) }
        let filtered = #"{"choices":[{"message":{"role":"assistant","content":""},"finish_reason":"content_filter"}]}"#
        #expect(throws: AIError.declined(nil)) { try OpenAICompatibleClient.text(from: Data(filtered.utf8)) }
    }

    @Test func modelsListsTheIDs() async throws {
        StubProtocol.handle(Self.host) { _ in (200, Data(#"{"object":"list","data":[{"id":"gpt-6-luna"},{"id":"gpt-6"}]}"#.utf8)) }
        let client = OpenAICompatibleClient(
            provider: .openAI, baseURL: URL(string: "https://\(Self.host)/v1/")!, apiKey: "k", model: "gpt-6-luna",
            session: StubProtocol.session)
        #expect(try await client.models() == ["gpt-6-luna", "gpt-6"])
    }
}

@Suite struct ErrorTests {
    @Test func whatMayFallThrough() {
        #expect(AIReachability.mayFallThrough(URLError(.notConnectedToInternet)))
        #expect(AIReachability.mayFallThrough(URLError(.timedOut)))
        #expect(AIReachability.mayFallThrough(AIError.badStatus(429, nil)))
        #expect(AIReachability.mayFallThrough(AIError.badStatus(503, nil)))
        #expect(AIReachability.mayFallThrough(AIError.badStatus(401, nil)))
        #expect(AIReachability.mayFallThrough(AIError.declined(nil)))
        // Answers that came back wrong are errors to see.
        #expect(!AIReachability.mayFallThrough(AIError.badStatus(400, "bad model")))
        #expect(!AIReachability.mayFallThrough(AIError.badResponse))
        #expect(!AIReachability.mayFallThrough(URLError(.serverCertificateUntrusted)))
    }

    @Test func errorMessagesComeFromEitherShape() {
        #expect(AIHTTP.errorMessage(from: Data(#"{"error":{"message":" Use max_completion_tokens. "}}"#.utf8)) == "Use max_completion_tokens.")
        #expect(AIHTTP.errorMessage(from: Data("<html>".utf8)) == nil)
    }
}
