import Foundation
import Testing

@testable import HisterKit

/// Nogon's AND, OR and NOT, on scripts/operator-cases.json: the cases
/// search-core and the Haiku and classic cores are tested against too.
struct OperatorTests {
    static func cases() throws -> [[String: String]] {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/operator-cases.json")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        return try #require(object["cases"] as? [[String: String]])
    }

    @Test func strayOperatorsAreQuotedAndAnOrIsGrouped() throws {
        let cases = try Self.cases()
        #expect(cases.count > 20)
        for c in cases {
            let typed = try #require(c["typed"])
            #expect(SearchText.quoteStrayOperators(typed) == c["stray"], "\(typed)")
            #expect(SearchText.groupWords(typed) == c["grouped"], "\(typed)")
            #expect(SearchText.forHister(typed) == c["sent"], "\(typed)")
            #expect(SearchText.forHisterNotes(typed) == c["notes"], "\(typed)")
            let opened = OpenedEntry(id: 1, url: "https://a.example/", title: "", query: SearchText.forHister(typed), added: .distantPast)
            #expect(opened.typedQuery == c["shown"], "\(typed)")
        }
    }

    @Test func theExclusionsApplyToEveryAlternative() {
        // "a OR b -label:vault" would be "a OR (b -label:vault)": a's notes in.
        #expect(SearchText.forHister("a OR b") == "(a OR b) -label:vault -metadata.source:vault -type:local -metadata.source:code")
        #expect(LocalFiles.query("a OR b") == "type:local (a OR b)")
        #expect(CodeDocs.query("bug OR crash") == "metadata.source:code (bug OR crash)")
        #expect(SearchText.forHister(SearchText.forHister("a OR b")) == SearchText.forHister("a OR b"))
    }
}
