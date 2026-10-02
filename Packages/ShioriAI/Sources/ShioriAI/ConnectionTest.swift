import Foundation

/// An engine that can list the models it offers.
public protocol AIModelListing: AIEngine {
    var model: String { get }
    func models() async throws -> [String]
}

extension AnthropicClient: AIModelListing {}
extension OpenAICompatibleClient: AIModelListing {}

/// Settings → AI → Test Connection: is the key good, is the chosen model
/// one the provider offers, and does it answer? The model check is how a
/// default newer than this code's reference material (Sonnet 5.5, GPT-6
/// Luna) gets confirmed rather than trusted.
public enum ConnectionTest {
    public enum Outcome: Sendable, Equatable {
        /// The model answered, in this many seconds.
        case answered(model: String, seconds: Double)
        /// The provider doesn't offer the model; these look close.
        case modelNotOffered(model: String, nearest: [String])
    }

    public static func run(_ engine: some AIModelListing) async throws -> Outcome {
        let offered = try await engine.models()
        // A server that lists nothing (some local ones) is taken at its
        // word when the model then answers.
        if !offered.isEmpty, !offered.contains(engine.model) {
            return .modelNotOffered(model: engine.model, nearest: nearest(to: engine.model, in: offered))
        }
        let start = Date()
        _ = try await engine.respond(to: ping)
        return .answered(model: engine.model, seconds: Date().timeIntervalSince(start))
    }

    /// Nothing of the user's: a fixed question with a one-word answer.
    /// Room for a model that thinks first (thinking counts against the cap).
    public static let ping = AIRequest(
        system: "You check that a connection works. Reply with the single word OK.",
        user: "Connection test.",
        maxTokens: 256,
        content: .none)

    /// The offered models that share the most name parts with the one
    /// asked for ("claude-sonnet-5-5" → the other Sonnets first), up to 6.
    static func nearest(to model: String, in offered: [String]) -> [String] {
        let wanted = Set(model.lowercased().split(whereSeparator: { $0 == "-" || $0 == "." }))
        func score(_ id: String) -> Int {
            wanted.intersection(id.lowercased().split(whereSeparator: { $0 == "-" || $0 == "." })).count
        }
        return offered
            .map { ($0, score($0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 > $1.0 }
            .prefix(6)
            .map(\.0)
    }
}
