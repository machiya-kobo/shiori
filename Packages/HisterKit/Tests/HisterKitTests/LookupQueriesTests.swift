import Foundation
import Testing

@testable import HisterKit

/// The same cases as search-core.test.mjs's "the saved-page lookup goes in batches" test.
struct LookupQueriesTests {
    @Test func batchesShortEnoughToSend() {
        let urls = (0..<130).map { "https://code.example.com/project/issues/\(1000 + $0)?tab=comments&sort=newest-first-\($0)" }
        let queries = HisterClient.lookupQueries(urls)
        #expect(queries.count > 1)
        for q in queries {
            #expect(q.count <= HisterClient.lookupMax)
            var components = URLComponents(string: "https://h.example/search")!
            let json = String(decoding: try! JSONSerialization.data(withJSONObject: ["text": SearchText.forHister(q), "limit": 100]), as: UTF8.self)
            components.setQueryItems([URLQueryItem(name: "query", value: json)])
            #expect((components.percentEncodedPath + "?" + (components.percentEncodedQuery ?? "")).count < 4096)
        }
        for u in urls { #expect(queries.contains { $0.contains("(\(u)|\(u)/") || $0.contains("|\(u)|\(u)/") }) }
    }

    @Test func edges() {
        #expect(HisterClient.lookupQueries(["https://a.example/" + String(repeating: "x", count: 2100), "https://b.example/"]) == ["url:(https://b.example/|https://b.example)"])
        #expect(HisterClient.lookupQueries(["https://w.example/a_(b)"]) == [])
        #expect(HisterClient.lookupQueries([]) == [])
        #expect(HisterClient.lookupQueries(["https://a.example/x", "https://b.example/"]) == ["url:(https://a.example/x|https://a.example/x/|https://b.example/|https://b.example)"])
    }
}
