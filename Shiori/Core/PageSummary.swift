import Foundation
import HisterKit
import Observation
import ShioriAI

/// Where a page's summary is, from asking to reading it.
enum SummaryState: Equatable {
    case none
    case working
    case done(Summary)
    case failed(String)
}

/// Where summaries are read and kept: `SummaryCache` in the app (`.live`,
/// whose write keeps `OfflineStore.keepable`'s rule), anything in tests.
struct SummaryStore {
    var read: (_ url: String, _ updated: Date) -> Summary?
    var write: (_ summary: Summary, _ page: StoredPage, _ updated: Date) -> Void
}

/// Summarize (Settings → AI) for the page on screen: the card above the
/// preview. Its engines, Kura's answer on a private vault and the cache
/// come in as closures, so it runs the same over stubs in tests.
@Observable final class PageSummary {
    private(set) var state: SummaryState = .none

    /// The page this is for: a result that comes back for another is dropped.
    @ObservationIgnored private var url: String?
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    @ObservationIgnored private let chain: () -> EngineChain
    @ObservationIgnored private let isPrivateNow: (String) async -> Bool
    @ObservationIgnored private let store: SummaryStore

    /// `isPrivateNow`: Kura asked afresh whether a note is a private
    /// vault's (a shared vault may be private by now), never a cached answer.
    init(chain: @escaping () -> EngineChain, isPrivateNow: @escaping (String) async -> Bool, store: SummaryStore) {
        self.chain = chain
        self.isPrivateNow = isPrivateNow
        self.store = store
    }

    /// Another page: whatever was under way for the last one stops.
    func reset(for url: String) {
        task?.cancel()
        task = nil
        self.url = url
        state = .none
    }

    /// A summary made before, for this version of the page: shown again.
    func showCached(url: String, updated: Date) {
        guard url == self.url, let cached = store.read(url, updated) else { return }
        state = .done(cached)
    }

    /// `fresh`: Regenerate, past the cache. `isNote`: the page has a
    /// note's links. Each kind goes only where it may (`AIContent.classify`,
    /// then `EngineChain` decides): a file or a private vault's note
    /// reaches no model at all, code stays on the device, a note never
    /// goes to a cloud engine.
    func summarize(document: StoredPage, preview: PagePreview, isNote: Bool, fresh: Bool = false) {
        let url = document.url
        self.url = url
        if !fresh, let cached = store.read(url, preview.updated) {
            task?.cancel()
            state = .done(cached)
            return
        }
        let isNote = isNote || document.label == Notes.label
        let isCode = document.code != nil
        let chain = chain()
        let title = preview.title.isEmpty ? document.displayTitle : preview.title
        task?.cancel()
        state = .working
        task = Task {
            do {
                // Another vault's note is asked of Kura afresh first; a file
                // or code asks nothing.
                let isFile = LocalFiles.isLocalFile(url)
                let isPrivate = isFile || isCode ? false : await isPrivateNow(url)
                let content = AIContent.classify(isLocalFile: isFile, isCode: isCode, isPrivateNote: isPrivate, isNote: isNote)
                let made = try await Summarizer(chain: chain).summarize(
                    title: title, url: url, html: preview.contentHTML, content: content)
                // Never kept for code, a file or a private vault's note
                // (`SummaryCache.write` checks).
                store.write(made, document, preview.updated)
                guard !Task.isCancelled, url == self.url else { return }
                state = .done(made)
            } catch {
                guard let message = Summarizer.failureMessage(error, isNote: isNote),
                      !Task.isCancelled, url == self.url else { return }
                state = .failed(message)
            }
        }
    }

    func close() {
        task?.cancel()
        state = .none
    }
}
