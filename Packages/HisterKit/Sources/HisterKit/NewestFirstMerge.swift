import Foundation

/// Two lists that each come newest first, a page at a time, as one: the
/// Library's All, your pages from Hister and your notes from Kura. A result is placed only once the
/// other list's next one is known (or that list has ended), so a later
/// page from either side never lands above what's already shown.
/// search-core.js's `NewestFirstMerge` is its twin, with the same tests.
public struct NewestFirstMerge: Sendable {
    /// Fetched, not yet placed.
    private var pages: [StoredPage] = []
    private var notes: [StoredPage] = []
    public private(set) var pagesDone = false
    public private(set) var notesDone = false
    /// Each list's next page key (Hister's key; Kura's offset).
    public var pagesKey: String?
    public var notesKey: String?

    public init() {}

    public mutating func add(pages more: [StoredPage], next: String?) {
        pages += more
        pagesKey = next
        pagesDone = next == nil
    }

    public mutating func add(notes more: [StoredPage], next: String?) {
        notes += more
        notesKey = next
        notesDone = next == nil
    }

    /// A list that failed or isn't there counts as ended.
    public mutating func endNotes() {
        notesKey = nil
        notesDone = true
    }

    /// Needs the next page of pages (or of notes) before it can place more.
    public var needsPages: Bool { pages.isEmpty && !pagesDone }
    public var needsNotes: Bool { notes.isEmpty && !notesDone }
    /// Everything placed and both lists ended.
    public var finished: Bool { pages.isEmpty && notes.isEmpty && pagesDone && notesDone }

    /// Places what can be placed now, newest first (a page before a note
    /// of the same moment).
    public mutating func take() -> [StoredPage] {
        var out: [StoredPage] = []
        while true {
            if let page = pages.first, let note = notes.first {
                if note.updated > page.updated { out.append(notes.removeFirst()) } else { out.append(pages.removeFirst()) }
            } else if !pages.isEmpty, notesDone {
                out.append(pages.removeFirst())
            } else if !notes.isEmpty, pagesDone {
                out.append(notes.removeFirst())
            } else {
                return out
            }
        }
    }
}
