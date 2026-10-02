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
    /// without reading the Keychain (this runs as views draw): AI on, and
    /// an engine this content may use. A cloud engine without a key still
    /// offers it; asking then says the key is missing.
    func hasEngine(note: Bool) -> Bool {
        guard enabled else { return false }
        if appleIntelligence, AppleIntelligenceEngine.status == .available { return true }
        if localEnabled, localBaseURL != nil, !localModel.isEmpty { return true }
        return !note && cloud != .none
    }

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
