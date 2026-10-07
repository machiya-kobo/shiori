import Foundation
import HisterKit
import Testing

/// Offline reading's copies: kept and read back per server, never a private
/// vault's note, a file or code, and only the newest previews.
@Suite(.serialized)
struct OfflineStoreTests {
    let origin = OfflineStore.origin(server: "https://hister.example/", kura: "https://kura.example/")

    init() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "OfflineStoreTests-\(UUID().uuidString)")
        OfflineStore.testDirectory = folder
        Notes.useVaults([])
    }

    private func page(_ url: String, label: String = "") -> StoredPage {
        StoredPage(url: url, title: "Title", domain: "example.com", label: label, added: .now, updated: .now,
                   faviconKey: "", snippetHTML: "a <mark>hit</mark>")
    }

    private func preview(_ text: String) -> PagePreview {
        PagePreview(title: "Title", contentHTML: "<p>\(text)</p>", added: .now, updated: .now, label: "", visits: 1,
                    author: nil, summary: nil)
    }

    @Test func aListComesBackForItsOwnServerOnly() async throws {
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        OfflineStore.saveList("pages", origin: origin, pages: [page("https://example.com/a"), page("https://example.com/b")], now: saved)
        await OfflineStore.settled()
        let copy = try #require(OfflineStore.list("pages", origin: origin))
        #expect(copy.pages.map(\.url) == ["https://example.com/a", "https://example.com/b"])
        #expect(copy.pages.first?.snippetHTML == "a <mark>hit</mark>")
        #expect(copy.savedAt == saved)
        #expect(OfflineStore.list("pages", origin: OfflineStore.origin(server: "https://other.example/", kura: "")) == nil)
        #expect(OfflineStore.list("notes", origin: origin) == nil)
    }

    @Test func neverAPrivateVaultsNoteAFileOrCode() async {
        var code = page("https://forge.example/repo")
        code.code = CodeInfo(kind: "repo")
        let pages = [page("https://kura.example/v/work/n/plan", label: "vault"), page("file:///srv/docs/a.pdf"), code]
        for page in pages {
            #expect(!OfflineStore.keepable(page))
            OfflineStore.savePreview(preview("secret"), for: page, origin: origin)
            await OfflineStore.settled()
            #expect(OfflineStore.preview(for: page, origin: origin) == nil)
        }
        OfflineStore.saveList("all", origin: origin, pages: pages)
        await OfflineStore.settled()
        #expect(OfflineStore.list("all", origin: origin) == nil)
        // The default vault's notes may be kept.
        #expect(OfflineStore.keepable(page("https://kura.example/n/Projects/Plan", label: "vault")))
    }

    @Test func aVaultTurnedPrivateIsNotReadBack() async {
        let note = page("https://kura.example/v/team/n/plan", label: "vault")
        Notes.useVaults([KuraVault(name: "team", title: "Team", isDefault: false, isPrivate: false, obsidian: "Team")])
        OfflineStore.savePreview(preview("shared"), for: note, origin: origin)
        await OfflineStore.settled()
        #expect(OfflineStore.preview(for: note, origin: origin)?.preview.contentHTML == "<p>shared</p>")
        Notes.useVaults([])
        #expect(OfflineStore.preview(for: note, origin: origin) == nil)
    }

    @Test func onlyTheNewestPreviewsStay() async throws {
        for i in 0..<(OfflineStore.previewLimit + 3) {
            OfflineStore.savePreview(preview("\(i)"), for: page("https://example.com/\(i)"), origin: origin)
        }
        await OfflineStore.settled()
        let folder = try #require(OfflineStore.directory?.appending(path: "previews"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == OfflineStore.previewLimit)
    }

    @Test func forgetAndClear() async {
        let a = page("https://example.com/a")
        OfflineStore.savePreview(preview("a"), for: a, origin: origin)
        await OfflineStore.settled()
        #expect(OfflineStore.preview(for: a, origin: origin) != nil)
        OfflineStore.forget(url: a.url)
        await OfflineStore.settled()
        #expect(OfflineStore.preview(for: a, origin: origin) == nil)
        // In the order asked: a save asked for before the clear is gone too.
        OfflineStore.saveList("pages", origin: origin, pages: [a])
        OfflineStore.clear()
        await OfflineStore.settled()
        #expect(OfflineStore.list("pages", origin: origin) == nil)
    }

    @Test func aPreviewIsForgottenWhicheverServerItCameFrom() async {
        let a = page("https://example.com/a")
        let other = OfflineStore.origin(server: "https://other.example/", kura: "")
        OfflineStore.savePreview(preview("a"), for: a, origin: other)
        await OfflineStore.settled()
        #expect(OfflineStore.preview(for: a, origin: origin) == nil)
        #expect(OfflineStore.preview(for: a, origin: other) != nil)
        OfflineStore.forget(url: a.url)
        await OfflineStore.settled()
        #expect(OfflineStore.preview(for: a, origin: other) == nil)
    }
}
