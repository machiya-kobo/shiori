import Foundation
import os

private let log = Logger(subsystem: logSubsystem, category: "ai")

/// What the cloud clients share: the session, the status check, and the
/// provider's own error message. No SDK (there's none for Swift): plain
/// URLSession, like HisterKit.
public enum AIHTTP {
    public static let timeout: TimeInterval = 30

    /// Ephemeral: no cookies, no cache, nothing of a request kept on disk.
    /// Follows no redirect: its requests carry API keys.
    public static func session(timeout: TimeInterval = timeout) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    /// Keys sorted: the same request is the same bytes every time (what a
    /// provider's prompt cache matches on).
    static func encode(_ body: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(body)
    }

    static func data(for request: URLRequest, session: URLSession) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            // Say why, not "couldn't connect": the fix is the address.
            throw AIError.plainHTTP
        }
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = errorMessage(from: data)
            // The status and the provider's message only: never a key or
            // anything of the page.
            log.notice("AI request failed: \(http.statusCode, privacy: .public) \(message ?? "", privacy: .public)")
            throw AIError.badStatus(http.statusCode, message)
        }
        return data
    }

    /// The provider's message: `{"error":{"message":…}}` from OpenAI and
    /// local servers, `{"type":"error","error":{"message":…}}` from
    /// Anthropic. Trimmed, since Settings shows it inline.
    static func errorMessage(from data: Data) -> String? {
        struct Envelope: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        guard let message = (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message?
            .trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty
        else { return nil }
        return String(message.prefix(200))
    }

    /// Models wrap JSON in ```json fences despite instructions; one
    /// balanced fence comes off, anything else is the caller's to decode.
    static func stripFence(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        trimmed = String(trimmed.dropFirst(3))
        if trimmed.lowercased().hasPrefix("json") { trimmed = String(trimmed.dropFirst(4)) }
        if let end = trimmed.range(of: "```", options: .backwards) { trimmed = String(trimmed[..<end.lowerBound]) }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A base address with the trailing slash `appending(path:)` needs.
    static func base(_ url: URL) -> URL {
        url.absoluteString.hasSuffix("/") ? url : URL(string: url.absoluteString + "/") ?? url
    }
}

/// Follows no redirect (as HisterKit's): a key must never go on to
/// another address.
final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
