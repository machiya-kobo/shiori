import Foundation
import Testing

@testable import HisterKit

/// Save This Note's Links: the pure part (twin of search-core's tests) and
/// Kura's two calls, against a stub.
@Suite(.serialized)
struct NoteLinksTests {
    static let host = "kura-links.example"
    let kura: KuraClient

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        kura = KuraClient(serverURL: "https://\(Self.host)/", session: URLSession(configuration: config))!
        StubProtocol.reset(Self.host)
    }

    func note(_ path: String, _ urls: [String], tags: [String] = []) -> LinkedNote {
        LinkedNote(path: path, title: path, url: "https://kura.example/n/\(path)", tags: tags,
                   externalLinks: urls.map { NoteLink(url: $0, text: "t") })
    }

    @Test func linksAreDeduplicatedAcrossNotesAndCapped() {
        let notes = [
            note("A", ["https://example.com/a", "https://www.example.com/a/#top", "ftp://example.com/x", "mailto:x@y"]),
            note("B", ["https://example.com/a?utm_source=x", "https://example.org/b"]),
        ]
        let links = SaveLinks.links(in: notes)
        #expect(links.map(\.url) == ["https://example.com/a", "https://example.org/b"])
        #expect(links.map(\.notePath) == ["A", "B"])
        let many = note("C", (0..<250).map { "https://example.net/\($0)" })
        #expect(SaveLinks.links(in: [many]).count == SaveLinks.cap)
    }

    @Test func geminiAndGopherLinksAreOfferedComparedConservatively() {
        let links = SaveLinks.links(in: [
            note("A", ["gemini://Example.org:1965/log/", "gopher://hole.example:70/1/users", "https://example.com/"]),
            note("B", ["gemini://example.org/log/", "gemini://example.org/log", "GOPHER://HOLE.EXAMPLE/1/users", "mailto:x@y"]),
        ])
        #expect(links.map(\.url) == ["gemini://Example.org:1965/log/", "gopher://hole.example:70/1/users", "https://example.com/", "gemini://example.org/log"])
        #expect(SaveLinks.isSmallWeb("gemini://a/"))
        #expect(!SaveLinks.isSmallWeb("https://a/"))
        #expect(SaveLinks.smallWebKey("gemini://Example.org:1965/Log/") == "gemini://example.org/Log/")
        #expect(SaveLinks.smallWebKey("gopher://h:7070/x") == "gopher://h:7070/x")
    }

    @Test func aLinkToAFileIsNotAPage() {
        #expect(SaveLinks.looksLikeFile("https://files.example/debian/pool/main/x_1.0+git_armhf.deb"))
        #expect(SaveLinks.looksLikeFile("https://example.com/a/paper.PDF"))
        #expect(SaveLinks.looksLikeFile("https://example.com/files.tar.gz"))
        #expect(!SaveLinks.looksLikeFile("https://github.com/mpv-player/mpv/releases/tag/v0.35.1"))
        #expect(!SaveLinks.looksLikeFile("https://example.com/index.html"))
        #expect(!SaveLinks.looksLikeFile("https://example.com/v1.2/notes"))
        #expect(!SaveLinks.looksLikeFile("not a url"))
    }

    @Test func tagsOfferOnlyLabelsThatExist() {
        let labels = ["alpha-one", "books", "Unix"]
        #expect(SaveLinks.labelCandidates(tags: ["type/idea", "topic/alpha-one", "#books", "unix", "made-up"], labels: labels)
            == ["alpha-one", "books", "Unix"])
        #expect(SaveLinks.labelCandidates(tags: ["books", "Books"], labels: labels) == ["books"])
        #expect(SaveLinks.labelCandidates(tags: [], labels: labels).isEmpty)
    }

    @Test func aNoteDecodesWithOrWithoutItsLinks() throws {
        let with = #"{"path":"P/N.md","title":"N","url":"https://k/n/P/N","tags":["alpha"],"external_links":[{"url":"https://a.example/","text":"A"}],"html":"x"}"#
        let note = try JSONDecoder().decode(LinkedNote.self, from: Data(with.utf8))
        #expect(note.externalLinks == [NoteLink(url: "https://a.example/", text: "A")])
        #expect(note.tags == ["alpha"])
        // Before Kura shipped the field: no links, not an error.
        let without = try JSONDecoder().decode(LinkedNote.self, from: Data(#"{"path":"P/N.md","title":"N","url":"u"}"#.utf8))
        #expect(without.externalLinks.isEmpty)
    }

    @Test func folderLinksPageUntilDone() async throws {
        StubProtocol.handle(Self.host) { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
            let offset = Int(items.first { $0.name == "offset" }?.value ?? "0") ?? 0
            #expect(request.url!.path == "/api/links")
            #expect(items.first { $0.name == "folder" }?.value == "Reading")
            let body = offset == 0
                ? #"{"total":2,"notes":[{"path":"Reading/A.md","title":"A","url":"u","external_links":[{"url":"https://a.example/","text":"a"}]}]}"#
                : #"{"total":2,"notes":[{"path":"Reading/B.md","title":"B","url":"u","external_links":[{"url":"https://b.example/","text":"b"}]}]}"#
            return (200, Data(body.utf8))
        }
        let notes = try await kura.allFolderLinks(folder: "Reading")
        #expect(notes.map(\.path) == ["Reading/A.md", "Reading/B.md"])
        #expect(StubProtocol.requests(Self.host).count == 2)
    }

    @Test func aBulkSaveHonoursSkipRulesAndRecordsTheNote() {
        let bulk = NewPage(url: "https://a.example/", title: "A", via: "note-links", ignoreSkipRules: false,
                           extra: ["from_note": "Reading/A.md"])
        #expect(bulk.metadata["ignore_skip_rules"] == nil)
        #expect(bulk.metadata["via"] == .string("note-links"))
        #expect(bulk.metadata["from_note"] == .string("Reading/A.md"))
        #expect(bulk.metadata["source"] == .string("shiori"))
        // A share, as before: a deliberate save overrides the skip rules.
        #expect(NewPage(url: "https://a.example/", title: "A", via: "share").metadata["ignore_skip_rules"] == .bool(true))
    }
}

/// The source link (AGPL-3.0 section 13): search-core's sourceLink cases.
struct SourceLinkTests {
    @Test func onlyAPlainWebAddress() {
        #expect(SourceLink.url("https://github.com/example/shiori")?.absoluteString == "https://github.com/example/shiori")
        #expect(SourceLink.url(" http://git.example/shiori ")?.absoluteString == "http://git.example/shiori")
        #expect(SourceLink.url("") == nil)
        #expect(SourceLink.url(nil) == nil)
        #expect(SourceLink.url("javascript:alert(1)") == nil)
        #expect(SourceLink.url("ftp://example.com/x") == nil)
        #expect(SourceLink.url("https://user:pw@example.com/") == nil)
        #expect(SourceLink.url("https://exa mple.com/") == nil)
        #expect(SourceLink.url("$(SHIORI_SOURCE_URL)") == nil)
    }
}
