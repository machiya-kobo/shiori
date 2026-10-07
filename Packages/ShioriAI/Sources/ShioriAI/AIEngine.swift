import Foundation

/// The engines, in the order they're tried (docs/ai.md): Apple
/// Intelligence on the device, a model server of the user's own, then one
/// cloud engine. The raw values are stored in settings: never rename them.
public enum AIProvider: String, Sendable, CaseIterable, Codable {
    case appleIntelligence
    case local
    case anthropic
    case openAI

    /// Page text leaves the user's own devices and servers.
    public var isCloud: Bool { self == .anthropic || self == .openAI }

    public var displayName: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .local: "Local Server"
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        }
    }

    /// The model a new setup starts with. Newer than this code's reference
    /// material, so Test Connection checks each against the provider's own model list
    /// rather than trusting these strings.
    public var defaultModel: String {
        switch self {
        case .anthropic: "claude-sonnet-5-5"
        case .openAI: "gpt-6-luna"
        case .appleIntelligence, .local: ""
        }
    }
}

/// What's being sent, which decides where it may go.
public enum AIContent: Sendable, Equatable {
    /// A web page from Hister.
    case page
    /// A note from the vault: never to a cloud engine.
    case note
    /// A note from a work vault (Kura's other vaults): never to any model,
    /// on-device ones included.
    /// No engine is eligible, so it fails as `noEngine` if a caller forgets.
    case workNote
    /// A file from the folders Hister watches (the Files pill): never to
    /// any model either, on-device ones included.
    case localFile
    /// A code document (your repos, code-import's, the Code pill):
    /// on-device engines only (Apple Intelligence), not a local server, never
    /// a cloud one. Code stays on the device, as notes do.
    case code
    /// Nothing of the user's: a connection test.
    case none
}

extension AIContent {
    /// What a document is, for where it may go, the strictest first: a
    /// file, then code, then a private vault's note (from Kura asked
    /// afresh, the caller's job), then any other note, else a page.
    public static func classify(isLocalFile: Bool, isCode: Bool, isPrivateNote: Bool, isNote: Bool) -> AIContent {
        if isLocalFile { return .localFile }
        if isCode { return .code }
        if isPrivateNote { return .workNote }
        return isNote ? .note : .page
    }
}

/// One question for an engine: instructions, the user turn, and (for
/// answers code will read) a JSON schema the reply must follow.
public struct AIRequest: Sendable {
    public var system: String
    public var user: String
    public var maxTokens: Int
    public var schema: JSONValue?
    public var content: AIContent
    /// The system prompt repeats, unchanged, across a run of requests
    /// seconds apart (a labelling run: the label list and its examples),
    /// so Anthropic may cache it: after the first, each reads it at a
    /// tenth of the price. Off for one-off prompts (a summary, an answer),
    /// where a cache write would only add 25%. Other engines ignore it.
    public var cacheSystem: Bool

    public init(
        system: String, user: String, maxTokens: Int = 1024, schema: JSONValue? = nil, content: AIContent,
        cacheSystem: Bool = false
    ) {
        self.system = system
        self.user = user
        self.maxTokens = maxTokens
        self.schema = schema
        self.content = content
        self.cacheSystem = cacheSystem
    }
}

/// An engine's reply, and which engine gave it (said beside every result,
/// so a fallback to the cloud is never silent).
public struct AIAnswer: Sendable, Equatable {
    public var text: String
    public var provider: AIProvider

    public init(text: String, provider: AIProvider) {
        self.text = text
        self.provider = provider
    }
}

public protocol AIEngine: Sendable {
    var provider: AIProvider { get }
    /// How much page text one request may carry, in characters: small on
    /// the device (Apple's model has 4K–8K tokens for everything),
    /// generous for a server or the cloud.
    var inputBudget: Int { get }
    func respond(to request: AIRequest) async throws -> String
}

extension AIEngine {
    public var inputBudget: Int { 60_000 }
}

/// The engines in order: each is asked in turn until one answers.
/// Another engine may try only when the one before couldn't answer (no
/// network, busy, a refused key, not available on this device, declined
/// by its guardrails); an answer that came back wrong is an error to see,
/// not to paper over (`AIReachability`).
public struct EngineChain: Sendable {
    public let engines: [any AIEngine]

    public init(_ engines: [any AIEngine]) {
        self.engines = engines
    }

    /// The engines this content may use: a note never goes to a cloud
    /// engine, whoever asks; a work note or a local file to none. The one
    /// place that rule lives.
    public func eligible(for content: AIContent) -> [any AIEngine] {
        guard content != .workNote, content != .localFile else { return [] }
        if content == .code { return engines.filter { $0.provider == .appleIntelligence } }
        return engines.filter { content != .note || !$0.provider.isCloud }
    }

    public func respond(to request: AIRequest) async throws -> AIAnswer {
        let (text, provider) = try await run(for: request.content) { try await $0.respond(to: request) }
        return AIAnswer(text: text, provider: provider)
    }

    /// Runs `work` with each eligible engine in turn until one gets
    /// through, for a job of several requests (a long page summarized in
    /// parts): the whole job moves to the next engine, not one request.
    public func run<T: Sendable>(
        for content: AIContent, _ work: @Sendable (any AIEngine) async throws -> T
    ) async throws -> (T, AIProvider) {
        let eligible = eligible(for: content)
        guard !eligible.isEmpty else { throw AIError.noEngine }
        var last: Error = AIError.noEngine
        for engine in eligible {
            try Task.checkCancellation()
            do {
                return (try await work(engine), engine.provider)
            } catch {
                guard AIReachability.mayFallThrough(error) else { throw error }
                last = error
            }
        }
        throw last
    }
}
