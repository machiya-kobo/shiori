import Foundation
import Testing

@testable import HisterKit

/// A page you opened stays in its search, on scripts/opened-first-cases.json
/// (search-core's `S.openedFirst` runs the same cases).
struct OpenedFirstTests {
    struct Cases: Decodable {
        struct Case: Decodable {
            struct Entry: Decodable {
                let url: String
                let title: String?
            }
            let name: String
            let history: [Entry]
            let documents: [Entry]
            let skip: [String]
            let want: [String]
        }
        let cases: [Case]
    }

    @Test func openedFirstAndOnce() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/opened-first-cases.json")
        let cases = try JSONDecoder().decode(Cases.self, from: Data(contentsOf: file)).cases
        #expect(!cases.isEmpty)
        for c in cases {
            let opened = c.history.map { OpenedResult(url: $0.url, title: $0.title ?? "") }
            let documents = c.documents.map {
                StoredPage(url: $0.url, title: $0.title ?? "", domain: "", label: "", added: .now, updated: .now, faviconKey: "", snippetHTML: "")
            }
            let got = OpenedFirst.pages(opened: opened, documents: documents) { !c.skip.contains($0) }
            #expect(got.map(\.url) == c.want, "\(c.name)")
        }
    }
}
