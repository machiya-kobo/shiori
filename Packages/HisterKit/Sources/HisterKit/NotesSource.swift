import Foundation

/// Where notes come from: Kura (its own search and reader) or Hister, which
/// holds the default vault's notes (and a shared vault's, never a private
/// one's) because Kura pushes them there as `label: vault` documents. The
/// person chooses (Settings → Notes: Notes From); until they do, Kura when
/// one is set up, else Hister. search-core's `notesSource`,
/// `histerNotesText`, `histerNoteShown` and `histerNoteDocuments` are the
/// twins, with scripts/notes-source-cases.json's cases.
public enum NotesSource: String, Sendable, CaseIterable {
    case kura, hister

    /// The source in use: `choice` is the setting ("" until chosen).
    /// Hister when chosen, or when there's no Kura to use.
    public static func effective(choice: String, kuraConfigured: Bool) -> NotesSource {
        if choice == NotesSource.hister.rawValue { return .hister }
        return kuraConfigured ? .kura : .hister
    }
}

extension SearchText {
    /// Hister's query for notes: the words (the last a prefix), `*` for the
    /// newest, and `label:vault`.
    public static func forHisterNotes(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        let words = t.isEmpty || t == "*" ? "*" : prefixLastWord(closeQuote(t), union: true)
        return "\(words) label:vault"
    }
}

extension Notes {
    /// Whether one of Hister's notes may be shown: the default vault's
    /// alone. The address decides (`otherVault`): `/v/<vault>/` is another
    /// vault's, shared or private, and without Kura a shared vault can't be
    /// told from a private one. Only an http(s) address Kura's reading of
    /// it accepts.
    public static func histerNoteShown(_ url: String) -> Bool {
        let lower = url.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return false }
        return kuraPath(of: url) != nil && otherVault(of: url) == nil
    }
}

extension HisterClient {
    /// A page of notes from Hister (`SearchText.forHisterNotes`), as
    /// `KuraClient.search` returns them: `label: vault` notes, the default
    /// vault's alone (`Notes.histerNoteShown`). The total is Hister's less
    /// what this page dropped: Hister can't leave other vaults out itself.
    public func searchNotes(
        _ text: String, sort: SearchSort = .relevance, pageKey: String? = nil, limit: Int = 30
    ) async throws(HisterError) -> SearchPage {
        let raw = try await search(sentText: SearchText.forHisterNotes(text), sort: sort, pageKey: pageKey, limit: limit)
        let kept = raw.documents.filter { Notes.histerNoteShown($0.url) }.map { page -> StoredPage in
            var note = page
            note.label = Notes.label
            return note
        }
        return SearchPage(
            total: max(0, raw.total - (raw.documents.count - kept.count)), documents: kept,
            nextPageKey: raw.nextPageKey, suggestion: nil)
    }
}
