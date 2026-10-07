import Foundation
import os

private let log = Logger(subsystem: logSubsystem, category: "ai")

/// Anthropic's Messages API, over plain HTTPS.
///
/// Current models refuse `temperature` and a prefilled assistant turn
/// (400), so neither is ever sent; JSON answers use structured output
/// (`output_config.format`) instead. Thinking is left to the model's
/// default, and `effort` isn't sent: older models (Haiku 4.5) reject it,
/// and the model is the user's choice.
public struct AnthropicClient: AIEngine {
    public static let defaultBaseURL = URL(string: "https://api.anthropic.com/v1/")!
    static let version = "2023-06-01"

    public let apiKey: String
    public let model: String
    let baseURL: URL
    let session: URLSession

    public var provider: AIProvider { .anthropic }

    public init(apiKey: String, model: String, baseURL: URL = defaultBaseURL, session: URLSession = AIHTTP.session()) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = AIHTTP.base(baseURL)
        self.session = session
    }

    public func respond(to request: AIRequest) async throws -> String {
        let data = try await AIHTTP.data(for: try urlRequest(for: request), session: session)
        if let usage = Self.usage(from: data) {
            // Counts only, never content: shows whether a cached system
            // prompt was read (Console → Logs, category "ai").
            log.notice(
                "Anthropic tokens: \(usage.input) in, \(usage.cacheRead) from cache, \(usage.cacheWrite) cached, \(usage.output) out")
        }
        return try Self.text(from: data)
    }

    /// Every model the key can use, by ID (`GET /v1/models`, paged).
    public func models() async throws -> [String] {
        guard !apiKey.isEmpty else { throw AIError.unavailable("No Anthropic API key.") }
        var ids: [String] = []
        var after: String?
        for _ in 0..<10 {
            var components = URLComponents(url: baseURL.appending(path: "models"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "limit", value: "1000")]
                + (after.map { [URLQueryItem(name: "after_id", value: $0)] } ?? [])
            guard let url = components.url else { throw AIError.badURL }
            var request = URLRequest(url: url)
            headers(&request)
            let page = try Self.modelPage(from: try await AIHTTP.data(for: request, session: session))
            ids += page.ids
            guard page.hasMore, let last = page.lastID else { break }
            after = last
        }
        return ids
    }

    // MARK: Request and reply (fixture-tested: the part that breaks when the API moves)

    struct Body: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct OutputConfig: Encodable {
            struct Format: Encodable {
                let type = "json_schema"
                let schema: JSONValue
            }
            let format: Format
        }
        /// Plain text, or one text block marked for caching.
        enum System: Encodable {
            case text(String)
            case cached(String)

            func encode(to encoder: any Encoder) throws {
                switch self {
                case .text(let text):
                    var container = encoder.singleValueContainer()
                    try container.encode(text)
                case .cached(let text):
                    struct Block: Encodable {
                        struct CacheControl: Encodable { let type = "ephemeral" }
                        let type = "text"
                        let text: String
                        let cacheControl = CacheControl()
                        enum CodingKeys: String, CodingKey {
                            case type, text
                            case cacheControl = "cache_control"
                        }
                    }
                    var container = encoder.singleValueContainer()
                    try container.encode([Block(text: text)])
                }
            }
        }
        let model: String
        let maxTokens: Int
        let system: System
        let messages: [Message]
        let outputConfig: OutputConfig?

        enum CodingKeys: String, CodingKey {
            case model, system, messages
            case maxTokens = "max_tokens"
            case outputConfig = "output_config"
        }
    }

    func urlRequest(for request: AIRequest) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw AIError.unavailable("No Anthropic API key.") }
        guard !model.isEmpty else { throw AIError.unavailable("No Anthropic model set.") }
        var urlRequest = URLRequest(url: baseURL.appending(path: "messages"))
        urlRequest.httpMethod = "POST"
        headers(&urlRequest)
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try AIHTTP.encode(
            Body(
                model: model,
                maxTokens: request.maxTokens,
                system: request.cacheSystem ? .cached(request.system) : .text(request.system),
                messages: [Body.Message(role: "user", content: request.user)],
                outputConfig: request.schema.map { Body.OutputConfig(format: .init(schema: $0)) }))
        return urlRequest
    }

    private func headers(_ request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
    }

    /// The reply's text. A refusal comes back as HTTP 200 with
    /// `stop_reason: "refusal"`, so it's checked before the content.
    static func text(from data: Data) throws -> String {
        struct Envelope: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            struct StopDetails: Decodable { let explanation: String? }
            let content: [Block]
            let stopReason: String?
            let stopDetails: StopDetails?

            enum CodingKeys: String, CodingKey {
                case content
                case stopReason = "stop_reason"
                case stopDetails = "stop_details"
            }
        }
        guard let envelope = DecodeLog.decode(Envelope.self, from: data, what: "Anthropic reply") else { throw AIError.badResponse }
        if envelope.stopReason == "refusal" { throw AIError.declined(envelope.stopDetails?.explanation) }
        let text = envelope.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.emptyContent }
        return AIHTTP.stripFence(text)
    }

    /// The reply's token counts, for the log: cache reads show a cached
    /// system prompt at work. Nil when the reply has none.
    static func usage(from data: Data) -> (input: Int, cacheRead: Int, cacheWrite: Int, output: Int)? {
        struct Envelope: Decodable {
            struct Usage: Decodable {
                let inputTokens: Int?
                let outputTokens: Int?
                let cacheReadInputTokens: Int?
                let cacheCreationInputTokens: Int?
                enum CodingKeys: String, CodingKey {
                    case inputTokens = "input_tokens"
                    case outputTokens = "output_tokens"
                    case cacheReadInputTokens = "cache_read_input_tokens"
                    case cacheCreationInputTokens = "cache_creation_input_tokens"
                }
            }
            let usage: Usage?
        }
        guard let usage = DecodeLog.decode(Envelope.self, from: data, what: "Anthropic usage")?.usage else { return nil }
        return (usage.inputTokens ?? 0, usage.cacheReadInputTokens ?? 0, usage.cacheCreationInputTokens ?? 0, usage.outputTokens ?? 0)
    }

    static func modelPage(from data: Data) throws -> (ids: [String], hasMore: Bool, lastID: String?) {
        struct Page: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
            let hasMore: Bool?
            let lastID: String?

            enum CodingKeys: String, CodingKey {
                case data
                case hasMore = "has_more"
                case lastID = "last_id"
            }
        }
        guard let page = DecodeLog.decode(Page.self, from: data, what: "Anthropic models") else { throw AIError.badResponse }
        return (page.data.map(\.id), page.hasMore ?? false, page.lastID)
    }
}
