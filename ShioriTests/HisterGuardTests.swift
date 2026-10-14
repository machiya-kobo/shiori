import Foundation
import HisterKit
import Testing

/// The app's checks before anything about a page goes to Hister: a private
/// vault's note and a file never, the Library's `*` never remembered.
struct HisterGuardTests {
    static let work = "https://kura.example/v/work/n/plan"
    static let file = "file:///home/user/notes.txt"
    static let page = "https://example.com/post"
    static let note = "https://kura.example/n/garden"

    private func stored(_ url: String) -> StoredPage {
        StoredPage(url: url, title: "Title", domain: "example.com", label: "", added: .now, updated: .now,
                   faviconKey: "", snippetHTML: "")
    }

    @Test func rememberWhatYouOpenSkipsPrivateNotesFilesAndBrowsing() {
        #expect(HisterGuard.mayRecordOpened(url: Self.page, query: "rust"))
        #expect(HisterGuard.mayRecordOpened(url: Self.note, query: "garden"))
        #expect(!HisterGuard.mayRecordOpened(url: Self.work, query: "plan"))
        #expect(!HisterGuard.mayRecordOpened(url: "https://kura.example/v/%77ork/n/plan", query: "plan"))
        #expect(!HisterGuard.mayRecordOpened(url: Self.file, query: "notes"))
        #expect(!HisterGuard.mayRecordOpened(url: Self.page, query: "*"))
        #expect(!HisterGuard.mayRecordOpened(url: Self.page, query: "  "))
    }

    @Test func labelsNeverGoToAPrivateNoteOrAFile() {
        #expect(HisterGuard.mayLabel(url: Self.page))
        #expect(!HisterGuard.mayLabel(url: Self.work))
        #expect(!HisterGuard.mayLabel(url: Self.file))
    }

    @Test func anExportLeavesPrivateNotesOut() {
        let pages = [Self.page, Self.work, Self.note, "https://kura.example/v/team/f/folder"].map(stored)
        #expect(HisterGuard.exportable(pages).map(\.url) == [Self.page, Self.note])
    }
}
