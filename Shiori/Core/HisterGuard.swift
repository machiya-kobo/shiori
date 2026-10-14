import Foundation
import HisterKit

/// What may go to Hister about a page, in one place the tests reach: a
/// private vault's note never (its address or title), a file never (what
/// you open there stays here). Callers that can wait still ask Kura afresh
/// (`AppState.isWorkNoteNow`) before sending; these are the checks that
/// need no answer.
enum HisterGuard {
    /// Remember What You Open: only a real search (not the Library's `*`),
    /// never a private vault's note or a file.
    static func mayRecordOpened(url: String, query: String) -> Bool {
        remembers(query) && mayReach(url)
    }

    static func remembers(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return !q.isEmpty && q != "*"
    }

    /// A label from here (Edit Label, Label New Pages, their Undo).
    static func mayLabel(url: String) -> Bool { mayReach(url) }

    /// An export's pages: no private vault's note leaves the device.
    static func exportable(_ pages: [StoredPage]) -> [StoredPage] {
        pages.filter { !Notes.isPrivateNote($0.url) }
    }

    private static func mayReach(_ url: String) -> Bool {
        !Notes.isPrivateNote(url) && !LocalFiles.isLocalFile(url)
    }
}
