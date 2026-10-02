import Foundation

/// OpenAI's chat completions, and (through `baseURL`) any server that
/// speaks the same API: Ollama, LM Studio, llama.cpp. One client, two
/// providers.
public struct OpenAICompatibleClient: AIEngine {
    public static let openAIBaseURL = URL(string: "https://api.openai.com/v1/")!

    public let provider: AIProvider
    public let apiKey: String
    public let model: String
    let baseURL: URL
    let session: URLSession

    /// OpenAI itself.
    public init(apiKey: String, model: String, session: URLSession = AIHTTP.session()) {
        self.init(provider: .openAI, baseURL: Self.openAIBaseURL, apiKey: apiKey, model: model, session: session)
    }

    /// A model server of the user's own: the key is optional (stock Ollama
    /// takes none).
    public init(localBaseURL: URL, apiKey: String, model: String, session: URLSession = AIHTTP.session()) {
        self.init(provider: .local, baseURL: localBaseURL, apiKey: apiKey, model: model, session: session)
    }

    init(provider: AIProvider, baseURL: URL, apiKey: String, model: String, session: URLSession) {
        self.provider = provider
        self.baseURL = AIHTTP.base(baseURL)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    public func respond(to request: AIRequest) async throws -> String {
        try Self.text(from: try await AIHTTP.data(for: try urlRequest(for: request), session: session))
    }

    /// Every model the server offers, by ID (`GET /models`).
    public func models() async throws -> [String] {
        try checkKey()
        var request = URLRequest(url: baseURL.appending(path: "models"))
        authorize(&request)
        struct Page: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        let data = try await AIHTTP.data(for: request, session: session)
        guard let page = try? JSONDecoder().decode(Page.self, from: data) else { throw AIError.badResponse }
        return page.data.map(\.id)
    }

    // MARK: Request and reply (fixture-tested)

    struct Body: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct ResponseFormat: Encodable {
            struct Schema: Encodable {
                let name = "answer"
                let strict = true
                let schema: JSONValue
            }
            let type = "json_schema"
            let jsonSchema: Schema

            enum CodingKeys: String, CodingKey {
                case type
                case jsonSchema = "json_schema"
            }
        }
        let model: String
        let messages: [Message]
        /// The token cap's NAME differs: api.openai.com refuses
        /// `max_tokens` on the GPT-5 family and later ("use
        /// max_completion_tokens"), while local servers only know
        /// `max_tokens`.
        let maxTokensKey: String
        let maxTokens: Int
        let responseFormat: ResponseFormat?

        private struct Key: CodingKey {
            let stringValue: String
            init(_ stringValue: String) { self.stringValue = stringValue }
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { nil }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(model, forKey: Key("model"))
            try container.encode(messages, forKey: Key("messages"))
            try container.encode(maxTokens, forKey: Key(maxTokensKey))
            try container.encodeIfPresent(responseFormat, forKey: Key("response_format"))
        }
    }

    func urlRequest(for request: AIRequest) throws -> URLRequest {
        try checkKey()
        guard !model.isEmpty else { throw AIError.unavailable("No \(provider.displayName) model set.") }
        var urlRequest = URLRequest(url: baseURL.appending(path: "chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        authorize(&urlRequest)
        urlRequest.httpBody = try AIHTTP.encode(
            Body(
                model: model,
                messages: [
                    Body.Message(role: "system", content: request.system),
                    Body.Message(role: "user", content: request.user),
                ],
                maxTokensKey: provider == .openAI ? "max_completion_tokens" : "max_tokens",
                maxTokens: request.maxTokens,
                responseFormat: request.schema.map { Body.ResponseFormat(jsonSchema: .init(schema: $0)) }))
        return urlRequest
    }

    private func checkKey() throws {
        if provider == .openAI, apiKey.isEmpty { throw AIError.unavailable("No OpenAI API key.") }
    }

    /// An empty key sends no header: some proxies refuse an empty Bearer.
    private func authorize(_ request: inout URLRequest) {
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
    }

    /// The reply's text. A structured-output refusal comes back in
    /// `message.refusal`, a filtered one as `finish_reason: content_filter`.
    static func text(from data: Data) throws -> String {
        struct Envelope: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                    let refusal: String?
                }
                let message: Message
                let finishReason: String?

                enum CodingKeys: String, CodingKey {
                    case message
                    case finishReason = "finish_reason"
                }
            }
            let choices: [Choice]
        }
        guard let choice = (try? JSONDecoder().decode(Envelope.self, from: data))?.choices.first else {
            throw AIError.badResponse
        }
        if let refusal = choice.message.refusal, !refusal.isEmpty { throw AIError.declined(refusal) }
        if choice.finishReason == "content_filter" { throw AIError.declined(nil) }
        guard let text = choice.message.content, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.emptyContent
        }
        return AIHTTP.stripFence(text)
    }
}
