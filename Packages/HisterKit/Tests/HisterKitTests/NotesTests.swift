import Foundation
import Testing

@testable import HisterKit

struct NotesTests {
    let cards = [Notes.Card(slug: "example", path: "Projects/Example.md")]

    @Test func notesMapFromNiwaAndKonbini() {
        #expect(Notes.path(of: "https://niwa.example/n/Topics/Sample%20Note", cards: cards) == "Topics/Sample Note.md")
        #expect(Notes.path(of: "https://konbini.example/p/example", cards: cards) == "Projects/Example.md")
        #expect(Notes.path(of: "https://konbini.example/p/other", cards: cards) == nil)
        #expect(Notes.path(of: "https://example.com/x", cards: cards) == nil)
    }

    @Test func linksToObsidianNiwaAndKonbini() {
        #expect(Notes.obsidianURL(vault: "personal", path: "Projects/Garden Plan.md")?.absoluteString
            == "obsidian://open?vault=personal&file=Projects/Garden%20Plan")
        #expect(Notes.niwaURL(base: "https://niwa.example", path: "Projects/Garden Plan.md")?.absoluteString
            == "https://niwa.example/n/Projects/Garden%20Plan")
        #expect(Notes.konbiniURL(base: "https://konbini.example/", path: "Projects/Example.md", cards: cards)?.absoluteString
            == "https://konbini.example/p/example")
        #expect(Notes.konbiniURL(base: "https://konbini.example/", path: "Tools/Tools.md", cards: cards) == nil)
        #expect(Notes.query("garden") == "garden label:vault")
    }
}

struct TagURLTests {
    @Test func aVaultTagLinksToItsKuraPage() {
        #expect(Notes.tagURL(base: "https://kura.example", tag: "topic/docker")?.absoluteString == "https://kura.example/t/topic/docker")
        #expect(Notes.tagURL(base: "https://kura.example/", tag: "#area/home lab")?.absoluteString == "https://kura.example/t/area/home%20lab")
        #expect(Notes.tagURL(base: "", tag: "x") == nil)
    }
}

struct ReaderURLTests {
    @Test func aNoteReadsOnItsOwnReaderPageElseOneBuiltOnTheReader() {
        #expect(Notes.readerURL(page: "https://kura.example/n/Guides/Example", base: "https://kura.example/", path: "Guides/Example.md")?.absoluteString
            == "https://kura.example/n/Guides/Example")
        #expect(Notes.readerURL(page: "https://konbini.example/p/example", base: "https://kura.example/", path: "Projects/Example.md")?.absoluteString
            == "https://kura.example/n/Projects/Example")
    }
}
