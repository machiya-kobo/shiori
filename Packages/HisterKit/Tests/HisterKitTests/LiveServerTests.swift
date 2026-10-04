import Foundation
import Testing

@testable import HisterKit

/// Read-only checks against a real server; skipped unless
/// HISTER_LIVE_URL is set (e.g. from local.env's SHIORI_SERVER_URL).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HISTER_LIVE_URL"] != nil))
struct LiveServerTests {
    let client = HisterClient(serverURL: ProcessInfo.processInfo.environment["HISTER_LIVE_URL"] ?? "")!

    /// The apps offer a sign-in exactly when the sign-in helper on Hister's
    /// host says Hister has users (`hister: "ok"`); without a helper, or with
    /// user handling off, none is offered and Hister answers as before.
    @Test func signInIsOfferedOnlyWhenHisterHasUsers() async throws {
        var request = URLRequest(url: client.baseURL.appending(path: "machiya/healthz"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let state: String? = await {
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                (response as? HTTPURLResponse)?.statusCode == 200
            else { return nil }
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["hister"] as? String
        }()
        #expect(await HisterAccount.available(server: client.baseURL) == (state == "ok"))
        if state != "ok" {
            // No users: an anonymous search works, and nothing reads as signed out.
            _ = try await client.search("*", limit: 1)
        }
    }

    @Test func recentPagesDecodeAndPage() async throws {
        let first = try await client.search("*", sort: .newest, limit: 10)
        #expect(first.documents.count == 10)
        let key = try #require(first.nextPageKey)
        let second = try await client.search("*", sort: .newest, pageKey: key, limit: 10)
        #expect(Set(first.documents.map(\.url)).isDisjoint(with: second.documents.map(\.url)))
    }

    /// The app's own paging: 30 at a time, three pages deep.
    @Test func recentPagesThreeDeep() async throws {
        var page = try await client.search("*", sort: .newest)
        var seen = Set(page.documents.map(\.url))
        for _ in 0..<2 {
            let key = try #require(page.nextPageKey)
            page = try await client.search("*", sort: .newest, pageKey: key)
            #expect(page.documents.count == 30)
            #expect(seen.isDisjoint(with: page.documents.map(\.url)))
            seen.formUnion(page.documents.map(\.url))
        }
    }

    @Test func aSearchHasHighlightedSnippets() async throws {
        let page = try await client.search("concurrency", limit: 5)
        #expect(page.documents.contains { Snippet(html: $0.snippetHTML).runs.contains(where: \.highlighted) })
    }

    @Test func previewAndRulesDecode() async throws {
        let recent = try await client.search("*", sort: .newest, limit: 5)
        for document in recent.documents {
            let preview = try await client.preview(of: document.url)
            #expect(preview.updated.timeIntervalSince1970 > 0)
        }
        let rules = try await client.rules()
        #expect(rules.labels.count > 10)
    }

}
