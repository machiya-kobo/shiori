import Foundation
import Testing

@testable import HisterKit

/// The web engines that didn't answer, on scripts/engine-health-cases.json:
/// the cases search-core's `S.unansweredEngines` is tested against too.
struct EngineHealthTests {
    static func cases() throws -> [[String: Any]] {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/engine-health-cases.json")
        let all = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        return try #require(all["cases"] as? [[String: Any]])
    }

    @Test func theEnginesThatDidntAnswerAndTheLine() throws {
        let cases = try Self.cases()
        #expect(!cases.isEmpty)
        for c in cases {
            let reply = try JSONSerialization.data(withJSONObject: try #require(c["reply"]))
            let names = EngineHealth.names(inReply: reply)
            #expect(names == c["names"] as? [String], "\(c)")
            #expect(EngineHealth.line(names) == c["line"] as? String, "\(c)")
        }
    }

    @Test func anOddEntryNeverSinksTheReply() throws {
        let reply = Data(#"{"results": [], "unresponsive_engines": [{"name": "alpha"}, ["beta", "timeout"]]}"#.utf8)
        #expect(EngineHealth.names(inReply: reply) == ["beta"])
        #expect(EngineHealth.names(inReply: Data("not json".utf8)) == [])
    }
}
