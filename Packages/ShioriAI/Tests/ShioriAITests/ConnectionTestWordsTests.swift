import Foundation
import Testing

@testable import ShioriAI

@Suite struct ConnectionTestWordsTests {
    private func words(_ error: Error) -> String {
        ConnectionTest.plainWords(for: error, provider: "Anthropic", model: "claude-sonnet-5-5")
    }

    @Test func aRefusedKeyIsSaidSo() {
        #expect(words(AIError.badStatus(401, nil)).hasPrefix("Anthropic refused the key."))
    }

    @Test func noAccessNamesTheModel() {
        #expect(words(AIError.badStatus(403, nil)) == "This key has no access to claude-sonnet-5-5.")
        #expect(words(AIError.badStatus(404, nil)).contains("claude-sonnet-5-5"))
    }

    @Test func aRateLimitAndAProviderFaultAreNotTheKeysFault() {
        #expect(words(AIError.badStatus(429, nil)).contains("rate limiting"))
        #expect(words(AIError.badStatus(529, nil)).contains("having trouble"))
    }

    @Test func theProvidersOwnMessageFollows() {
        #expect(words(AIError.badStatus(400, "max_tokens too large")) == "Anthropic turned the request down (status 400). (max_tokens too large)")
    }

    @Test func noNetworkIsSaidSo() {
        #expect(words(URLError(.notConnectedToInternet)).hasPrefix("No network connection."))
        #expect(words(URLError(.timedOut)) == "Anthropic didn't answer in time. Try again.")
    }
}
