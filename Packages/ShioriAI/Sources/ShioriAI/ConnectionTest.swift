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

    /// What went wrong, in plain words for Settings: a refused key, no
    /// access to the model, a rate limit, a provider fault, no network.
    /// The provider's own message follows when it sent one. Never the key
    /// (the clients send it in a header, and no error holds it).
    public static func plainWords(for error: Error, provider: String, model: String) -> String {
        func with(_ text: String, _ detail: String?) -> String {
            guard let detail, !detail.isEmpty else { return text }
            return "\(text) (\(detail))"
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "No network connection. Check this device's connection and try again."
            case .timedOut:
                return "\(provider) didn't answer in time. Try again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Couldn't reach \(provider). Check the network and try again."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
                return "Couldn't make a secure connection to \(provider)."
            default:
                return "Couldn't reach \(provider): \(urlError.localizedDescription)"
            }
        }
        if case AIError.badStatus(let code, let message) = error {
            switch code {
            case 401:
                return with("\(provider) refused the key. Check that it's right and not revoked.", message)
            case 403:
                return with("This key has no access to \(model).", message)
            case 404:
                return with("\(provider) has no model called \(model), or this key can't use it.", message)
            case 429:
                return with("\(provider) is rate limiting this key, or its quota is used up. Try again in a minute.", message)
            case 500...599:
                return with("\(provider) is having trouble right now (status \(code)). Try again later.", message)
            default:
                return with("\(provider) turned the request down (status \(code)).", message)
            }
        }
        return error.localizedDescription
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
