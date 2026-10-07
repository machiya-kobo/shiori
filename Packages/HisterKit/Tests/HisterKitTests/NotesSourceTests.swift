import Foundation
import Testing

@testable import HisterKit

/// Notes from Kura or from Hister, on scripts/notes-source-cases.json: the
/// cases search-core and the Haiku and classic cores are tested against too.
struct NotesSourceTests {
    static func cases() throws -> [String: Any] {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/notes-source-cases.json")
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }

    @Test func theChosenSourceElseKuraWhenOneIsSetUp() throws {
        let cases = try #require(try Self.cases()["source"] as? [[String: Any]])
        #expect(!cases.isEmpty)
        for c in cases {
            let choice = try #require(c["choice"] as? String), kura = try #require(c["kura"] as? Bool)
            #expect(NotesSource.effective(choice: choice, kuraConfigured: kura).rawValue == c["want"] as? String, "\(c)")
        }
    }

    @Test func histersQueryForNotes() throws {
        let cases = try #require(try Self.cases()["text"] as? [[String: Any]])
        for c in cases {
            let q = try #require(c["q"] as? String)
            #expect(SearchText.forHisterNotes(q) == c["want"] as? String, "\(q)")
        }
    }

    @Test func onlyTheDefaultVaultsNotes() throws {
        let cases = try #require(try Self.cases()["keep"] as? [[String: Any]])
        for c in cases {
            let url = try #require(c["url"] as? String)
            #expect(Notes.histerNoteShown(url) == c["keep"] as? Bool, "\(url)")
        }
    }
}

@Suite(.serialized)
struct HisterNotesClientTests {
    static let host = "notes-client.example"

    @Test func notesFromHisterInKurasShape() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let client = try #require(HisterClient(serverURL: "https://\(Self.host)", session: URLSession(configuration: config)))
        StubProtocol.reset(Self.host)
        let reply = try #require(try NotesSourceTests.cases()["documents"] as? [String: Any])["reply"]
        let json = try JSONSerialization.data(withJSONObject: try #require(reply))
        StubProtocol.handle(Self.host) { _ in (200, json) }

        let page = try await client.searchNotes("lantern")
        #expect(page.total == 2)
        #expect(page.documents.map(\.url) == [
            "https://kura.example/n/Projects/Lantern%20festival%20kit", "https://kura.example/n/Workshop/Chochin%20build%20log",
        ])
        #expect(page.documents.allSatisfy { $0.label == Notes.label })
        // asked as notes: label:vault, never the notes exclusion
        let sent = try #require(StubProtocol.requests(Self.host).first?.url?.absoluteString.removingPercentEncoding)
        #expect(sent.contains("(lantern|lantern*) label:vault") && !sent.contains("-label:vault"))
    }
}
