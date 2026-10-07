import Foundation
import ShioriAI
import ShioriAIOnDevice

extension AISettings {
    /// The engines switched on, in the fixed order (docs/ai.md):
    /// Apple Intelligence, the local server, the cloud engine. Empty
    /// while AI is off: every feature asks here, so the one switch stops
    /// them all (a background path that kept its own engine could run
    /// one while AI was off).
    func engines() -> [any AIEngine] {
        guard enabled else { return [] }
        var out: [any AIEngine] = []
        if appleIntelligence { out.append(AppleIntelligenceEngine()) }
        if let local = localEngine { out.append(local) }
        if let cloud = cloudEngine { out.append(cloud) }
        return out
    }

    var chain: EngineChain { EngineChain(engines()) }

    /// Whether an AI action (Summarize, suggested labels) can be offered,
    /// without reading the Keychain or building an engine (this runs as
    /// views draw): AI on, and an engine this content may use, by
    /// `EngineChain.eligible` itself over stand-ins for the engines set
    /// up. A cloud engine without a key still offers it; asking then says
    /// the key is missing.
    func hasEngine(for content: AIContent) -> Bool {
        guard enabled else { return false }
        var offered: [any AIEngine] = []
        if appleIntelligence, AppleIntelligenceEngine.status == .available { offered.append(Offered(provider: .appleIntelligence)) }
        if localEnabled, localBaseURL != nil, !localModel.isEmpty { offered.append(Offered(provider: .local)) }
        switch cloud {
        case .none: break
        case .anthropic: offered.append(Offered(provider: .anthropic))
        case .openAI: offered.append(Offered(provider: .openAI))
        }
        return !EngineChain(offered).eligible(for: content).isEmpty
    }

    func hasEngine(note: Bool) -> Bool { hasEngine(for: note ? .note : .page) }

    var localEngine: OpenAICompatibleClient? {
        guard localEnabled, let url = localBaseURL else { return nil }
        return OpenAICompatibleClient(localBaseURL: url, apiKey: AIKeychain.read(.local), model: localModel)
    }

    var cloudEngine: (any AIModelListing)? {
        switch cloud {
        case .none: nil
        case .anthropic: AnthropicClient(apiKey: AIKeychain.read(.anthropic), model: anthropicModel)
        case .openAI: OpenAICompatibleClient(apiKey: AIKeychain.read(.openAI), model: openAIModel)
        }
    }
}

/// An engine's provider alone, for `hasEngine(for:)`: never asked.
private nonisolated struct Offered: AIEngine {
    let provider: AIProvider
    func respond(to request: AIRequest) async throws -> String { throw AIError.noEngine }
}
