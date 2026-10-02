import Foundation
import Testing

@testable import HisterKit

/// Notes from Kura: its queries, URLs and replies, as search-core.test.mjs has them.
@Suite struct KuraTests {
    let base = URL(string: "https://kura.example/")!

    @Test func queriesDropHisterSyntaxAndStarIsRecent() {
        #expect(KuraClient.query("shiori label:vault") == "shiori*")
        #expect(KuraClient.query("title:shio* tag:area/projects") == "title:shio* tag:area/projects")
        #expect(KuraClient.query("* label:vault") == "")
        #expect(KuraClient.query("@alpha") == "")
    }

    @Test func urlsForSearchAndRecent() {
        #expect(KuraClient.url(base: base, text: "hister label:vault", sort: .relevance, limit: 5, offset: 0).absoluteString
            == "https://kura.example/api/search?limit=5&offset=0&q=hister*&sort=relevance")
        #expect(KuraClient.url(base: base, text: "hister", sort: .newest, limit: 20, offset: 20).absoluteString
            == "https://kura.example/api/search?limit=20&offset=20&q=hister*&sort=changed")
        #expect(KuraClient.url(base: base, text: "* label:vault", sort: .newest, limit: 30, offset: 0).absoluteString
            == "https://kura.example/api/recent?limit=30&offset=0")
    }

    @Test func repliesBecomeVaultNotesWithTheOffsetAsTheNextKey() throws {
        let json = """
            {"total": 25, "took_ms": 1, "results": [
              {"path": "Projects/Garden Plan.md", "title": "Garden Plan", "url": "https://kura.example/n/Projects/Garden%20Plan",
               "snippet": "<mark>Garden</mark> Plan", "tags": ["type/idea"], "created": 1790380800, "changed": 1790553600,
               "card_url": "https://konbini.example/p/garden-plan"},
              {"path": "x.md", "title": "bad", "url": "javascript:alert(1)"}
            ]}
            """
        let page = try #require(KuraClient.page(from: Data(json.utf8), offset: 0))
        #expect(page.total == 25)
        #expect(page.documents.count == 1)
        let note = try #require(page.documents.first)
        #expect(note.label == Notes.label)
        #expect(note.title == "Garden Plan")
        #expect(note.domain == "kura.example")
        #expect(note.updated == Date(timeIntervalSince1970: 1790553600))
        #expect(note.snippetHTML == "<mark>Garden</mark> Plan")
        #expect(page.nextPageKey == "2")
        let last = try #require(KuraClient.page(from: Data(#"{"total": 2, "results": []}"#.utf8), offset: 2))
        #expect(last.nextPageKey == nil)
        #expect(KuraClient.page(from: Data("not json".utf8), offset: 0) == nil)
    }
}

/// Against the real Kura, read-only, when KURA_LIVE_URL is set (as
/// HISTER_LIVE_URL is for Hister): its replies decode, and paging adds up.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["KURA_LIVE_URL"] != nil))
struct KuraLiveTests {
    let client = KuraClient(serverURL: ProcessInfo.processInfo.environment["KURA_LIVE_URL"] ?? "")!

    @Test func searchAndRecentDecodeAndPage() async throws {
        let first = try await client.search("hister", limit: 5)
        #expect(first.total >= first.documents.count && !first.documents.isEmpty)
        #expect(first.documents.allSatisfy { $0.label == Notes.label && $0.url.contains("/n/") })
        if first.total > 5 {
            let second = try await client.search("hister", pageKey: first.nextPageKey, limit: 5)
            #expect(Set(second.documents.map(\.url)).isDisjoint(with: first.documents.map(\.url)))
        }
        let recent = try await client.search("* label:vault", sort: .newest, limit: 3)
        #expect(recent.documents.count == 3)
        #expect(recent.documents[0].updated >= recent.documents[2].updated)
    }

    /// Save This Note's Links' two calls: a folder's notes come
    /// with their links, and a note's own links match its entry there.
    @Test func linksDecode() async throws {
        let name = ProcessInfo.processInfo.environment["KURA_LIVE_FOLDER"] ?? "Notes"
        let folder = try await client.folderLinks(folder: name, limit: 5)
        #expect(folder.total >= folder.notes.count && !folder.notes.isEmpty)
        #expect(folder.notes.allSatisfy { !$0.externalLinks.isEmpty && $0.path.hasPrefix(name + "/") })
        let first = try #require(folder.notes.first)
        let note = try await client.noteLinks(path: first.path)
        #expect(note.externalLinks == first.externalLinks)
        #expect(!SaveLinks.links(in: folder.notes).isEmpty)
    }
}

/// What a search sends: the last word a prefix, the notes left out of
/// Hister, and the Library's All merged newest first. search-core.test.mjs
/// has the same cases.
@Suite struct SearchTextAndMergeTests {
    @Test func theLastPlainWordIsAPrefix() {
        #expect(SearchText.prefixLastWord("hist") == "hist*")
        #expect(SearchText.prefixLastWord("raspberry pi") == "raspberry pi*")
        #expect(SearchText.prefixLastWord("raspberry pi ") == "raspberry pi ")
        #expect(SearchText.prefixLastWord("pi 5") == "pi 5")
        #expect(SearchText.prefixLastWord("a") == "a")
        #expect(SearchText.prefixLastWord("hist*") == "hist*")
        #expect(SearchText.prefixLastWord("label:foo") == "label:foo")
        #expect(SearchText.prefixLastWord("c++") == "c++")
        #expect(SearchText.prefixLastWord("\"exact phrase") == "\"exact phrase")
        #expect(SearchText.prefixLastWord("\"exact\" phrase") == "\"exact\" phrase*")
        #expect(SearchText.prefixLastWord("@alpha") == "@alpha")
        #expect(SearchText.prefixLastWord("*") == "*")
        #expect(SearchText.prefixLastWord("") == "")
        #expect(SearchText.prefixLastWord("町家") == "町家*")
    }

    @Test func histerNeverGetsTheNotes() {
        #expect(SearchText.forHister("hist") == "hist* -label:vault -metadata.source:vault")
        #expect(SearchText.forHister("*") == "* -label:vault -metadata.source:vault")
        #expect(SearchText.forHister("") == "-label:vault -metadata.source:vault")
        #expect(SearchText.forHister("x -label:vault -metadata.source:vault") == "x -label:vault -metadata.source:vault")
        #expect(Notes.withoutExclusion("rust* -label:vault -metadata.source:vault") == "rust*")
    }

    private func page(_ url: String, _ at: TimeInterval) -> StoredPage {
        StoredPage(url: url, title: url, domain: "", label: "", added: Date(timeIntervalSince1970: at),
                   updated: Date(timeIntervalSince1970: at), faviconKey: "", snippetHTML: "")
    }

    @Test func mergesNewestFirstAndWaitsForTheOtherList() {
        var merge = NewestFirstMerge()
        merge.add(pages: [page("p9", 9), page("p5", 5)], next: "k")
        merge.add(notes: [page("n7", 7), page("n6", 6), page("n1", 1)], next: nil)
        // p5 is placed; n1 waits: the next page of pages may hold a newer one.
        #expect(merge.take().map(\.url) == ["p9", "n7", "n6", "p5"])
        #expect(merge.needsPages && !merge.needsNotes && !merge.finished)
        merge.add(pages: [page("p3", 3), page("p0", 0)], next: nil)
        #expect(merge.take().map(\.url) == ["p3", "n1", "p0"])
        #expect(merge.finished)
    }

    @Test func anEndedListLetsTheOtherRun() {
        var merge = NewestFirstMerge()
        merge.add(pages: [page("p2", 2), page("p1", 1)], next: "k")
        merge.endNotes()
        #expect(merge.take().map(\.url) == ["p2", "p1"])
        #expect(merge.needsPages)
    }
}

/// Hister's own `@notes` and `@pages` aren't collections in Shiori.
@Suite struct VaultAliasTests {
    @Test func aliasesAboutTheNotesAreLeftOut() {
        let rules = Rules(aliases: [
            "@notes": "label:vault", "@pages": "* -label:vault -metadata.source:vault",
            "@tools": "label:(hammer|wrench|cli)", "@vaulted": "label:vaulted",
        ])
        #expect(rules.aliases.keys.sorted() == ["@tools", "@vaulted"])
        #expect(!rules.labels.contains("vault"))
        #expect(Rules.namesTheVault("label:(books|vault)"))
        #expect(!Rules.namesTheVault("label:(vaulted|books)"))
    }
}

/// Kura's work vaults: known by the address alone. Serialized: the shared
/// set (`Notes.useVaults`) is the process's own.
@Suite(.serialized) struct VaultTests {
    @Test func workNotesAreKnownByTheirAddress() {
        #expect(Notes.otherVault(of: "https://kura.example/v/work/n/Literature%20Notes/Weekly") == "work")
        #expect(Notes.otherVault(of: "https://kura.example/n/Projects/Example") == nil)
        #expect(Notes.otherVault(of: "https://example.com/v/x") == nil)
        #expect(Notes.otherVault(of: "https://example.com/") == nil)
        #expect(Notes.path(of: "https://kura.example/v/work/n/Literature%20Notes/Weekly", cards: []) == "Literature Notes/Weekly.md")
        #expect(Notes.path(of: "https://kura.example/n/Projects/Example", cards: []) == "Projects/Example.md")
        #expect(Notes.readerURL(page: "https://kura.example/v/work/n/X", base: "https://kura.example/", path: "X.md")?.absoluteString
            == "https://kura.example/v/work/n/X")
    }

    @Test func aVaultIsPrivateUntilKuraMarksItShared() {
        let work = "https://kura.example/v/work/n/X"
        let client = "https://kura.example/v/client/n/X"
        Notes.useVaults([])
        #expect(Notes.isPrivateNote(work))
        #expect(!Notes.isPrivateNote("https://kura.example/n/Projects/Example"))
        #expect(!Notes.isPrivateNote("https://example.com/"))
        Notes.useVaults([
            KuraVault(name: "personal", title: "Personal", isDefault: true, isPrivate: false, obsidian: "personal"),
            KuraVault(name: "work", title: "Work", isDefault: false, isPrivate: false, obsidian: "work"),
            KuraVault(name: "client", title: "Client", isDefault: false, isPrivate: true, obsidian: "client"),
        ])
        #expect(!Notes.isPrivateNote(work))
        #expect(Notes.isPrivateNote(client))
        #expect(Notes.isPrivateNote("https://kura.example/v/new/n/X"), "not listed: private")
        Notes.useVaults([])
        #expect(Notes.isPrivateNote(work), "a failed read shares nothing")
    }

    @Test func kuraIsAskedAgainBeforeAnythingIsSent() async {
        let work = "https://kura.example/v/work/n/X"
        let shared = [KuraVault(name: "work", title: "Work", isDefault: false, isPrivate: false, obsidian: "work")]
        let madePrivate = [KuraVault(name: "work", title: "Work", isDefault: false, isPrivate: true, obsidian: "work")]
        Notes.useVaults(shared)
        #expect(!Notes.isPrivateNote(work))
        let flipped = await Notes.isPrivateNoteNow(work, read: { madePrivate })
        #expect(flipped, "shared when cached, private when asked: refused")
        #expect(Notes.isPrivateNote(work), "the fresh answer is kept")
        Notes.useVaults(shared)
        let unanswered = await Notes.isPrivateNoteNow(work, read: { throw HisterError.unreachable })
        #expect(unanswered, "Kura out of reach: private")
        let noKura = await Notes.isPrivateNoteNow(work, kura: nil)
        #expect(noKura, "no Kura: private")
        let stillShared = await Notes.isPrivateNoteNow(work, read: { shared })
        #expect(!stillShared)
        let defaultVault = await Notes.isPrivateNoteNow("https://kura.example/n/X", read: { throw HisterError.unreachable })
        #expect(!defaultVault, "the default vault's notes ask nothing")
        Notes.useVaults([])
    }

    @Test func aVaultWithoutThePrivateFlagIsPrivate() throws {
        let reply = Data(#"[{"name":"personal","default":true},{"name":"work"}]"#.utf8)
        let vaults = try JSONDecoder().decode([KuraVault].self, from: reply)
        #expect(vaults.map(\.isPrivate) == [false, true])
    }

    @Test func aNotesChipNamesItsVault() {
        let vaults = [KuraVault(name: "personal", title: "Personal", isDefault: true, isPrivate: false, obsidian: "personal"),
                      KuraVault(name: "work", title: "Work", isDefault: false, isPrivate: true, obsidian: "work")]
        #expect(Notes.vaultChip(of: "https://kura.example/n/Projects/Example", vaults: vaults) == ("personal", "Personal vault"))
        #expect(Notes.vaultChip(of: "https://kura.example/v/work/n/X", vaults: vaults) == ("work", "Work vault"))
        #expect(Notes.vaultChip(of: "https://kura.example/v/client/n/X", vaults: vaults) == ("client", "client vault"))
        #expect(Notes.vaultChip(of: "https://kura.example/n/X", vaults: []) == ("", "vault"))
    }

    @Test func searchesAskForTheVaultsOnlyWhenTold() {
        let base = URL(string: "https://kura.example/")!
        #expect(!KuraClient.url(base: base, text: "cost", sort: .relevance, limit: 5, offset: 0).absoluteString.contains("vault="))
        #expect(KuraClient.url(base: base, text: "cost", sort: .relevance, limit: 5, offset: 0, vaults: "all").absoluteString.contains("vault=all"))
    }

    @Test func vaultsDecode() throws {
        let json = #"{"vaults": [{"name": "personal", "title": "Personal", "default": true, "private": false, "obsidian": "personal", "notes": 10}, {"name": "work", "title": "Work", "default": false, "private": true, "obsidian": "work"}]}"#
        struct Reply: Decodable { let vaults: [KuraVault] }
        let vaults = try JSONDecoder().decode(Reply.self, from: Data(json.utf8)).vaults
        #expect(vaults.map(\.name) == ["personal", "work"])
        #expect(vaults[0].isDefault && !vaults[0].isPrivate)
        #expect(vaults[1].isPrivate && vaults[1].title == "Work")
    }
}
