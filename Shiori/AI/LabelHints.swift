import Foundation
import HisterKit
import ShioriAI

/// What the label suggestions learn from the user's own filing: a few
/// titles under each label, and which labels each site's pages carry.
/// Label names alone aren't enough: labels follow their own conventions,
/// which names alone don't say.
struct LabelHints: Sendable {
    struct Filed: Sendable {
        let url: String
        let title: String
        let label: String
        let host: String
    }

    /// The newest labelled pages, newest first.
    var pages: [Filed] = []
    var loadedAt = Date.distantPast

    /// How many pages the hints read: enough for two examples of most
    /// labels and the busy sites' habits, in ten requests.
    static let pageLimit = 1_000

    /// The label list for one page, each with up to two example titles,
    /// never the page itself.
    func choices(_ labels: [String], collections: (String) -> [String], excluding url: String) -> [LabelChoice] {
        labels.map { label in
            LabelChoice(
                name: label, collections: collections(label),
                examples: Array(pages.lazy.filter { $0.label == label && $0.url != url && !$0.title.isEmpty }.prefix(2).map(\.title)))
        }
    }

    /// The labels on the user's other pages from this page's site.
    func siteLabels(for url: String) -> [String: Int] {
        guard let host = URL(string: url)?.host() else { return [:] }
        var counts: [String: Int] = [:]
        for page in pages where page.host == host && page.url != url { counts[page.label, default: 0] += 1 }
        return counts
    }

    static func load(using client: HisterClient) async -> LabelHints {
        var hints = LabelHints()
        var key: String?
        var read = 0
        repeat {
            guard let page = try? await client.search("*", sort: .newest, pageKey: key, limit: 100) else { break }
            for document in page.documents where !document.label.isEmpty && !LabelClassifier.notTopics.contains(document.label) {
                hints.pages.append(
                    Filed(url: document.url, title: document.displayTitle, label: document.label, host: URL(string: document.url)?.host() ?? ""))
            }
            read += page.documents.count
            key = page.nextPageKey
        } while key != nil && read < pageLimit
        hints.loadedAt = Date()
        return hints
    }
}

extension AppState {
    /// Loaded when a suggestion is first wanted, then kept for half an
    /// hour (labels change as the user files pages), or as long as
    /// `maxAge` allows. Gone when the account changes.
    func labelHintsIfNeeded(maxAge: TimeInterval = 30 * 60) async -> LabelHints {
        if let hints = labelHints, Date().timeIntervalSince(hints.loadedAt) < maxAge { return hints }
        guard let client else { return LabelHints() }
        let account = labelAccount
        let hints = await LabelHints.load(using: client)
        // Another account's by now (signed in elsewhere meanwhile): not kept.
        guard account == labelAccount else { return hints }
        labelHints = hints
        return hints
    }

    /// The labels a suggestion may offer: the server's, less the ones that
    /// aren't topics and the ones never suggested.
    var suggestableLabels: [String] {
        let excluded = Set(ai.neverSuggest)
        return rules.labels.filter { !LabelClassifier.notTopics.contains($0) && !excluded.contains($0) }
    }

    /// One page's label question, built the one way Edit Label and Label
    /// New Pages share: what the page is (`AIContent.classify`, another
    /// vault's note asked of Kura afresh) decides where it may go, through
    /// `EngineChain.eligible`, whichever path asks. Nil when no model may
    /// see the page at all (a file, a private vault's note).
    func labelQuestion(
        url: String, title fallback: String, label: String, isCode: Bool, preview: PagePreview, labels: [String],
        hints: LabelHints, corrections: [LabelCorrection]
    ) async -> LabelQuestion? {
        guard let client else { return nil }
        let isFile = LocalFiles.isLocalFile(url)
        let content = AIContent.classify(
            isLocalFile: isFile, isCode: isCode,
            isPrivateNote: isFile || isCode ? false : await isWorkNoteNow(url),
            isNote: label == Notes.label || isNotePage(url))
        if content == .workNote || content == .localFile { return nil }
        let title = preview.title.isEmpty ? fallback : preview.title
        let rules = rules
        let similar = await AutoLabeller.neighbours(of: url, title: title, labels: Set(labels), client: client)
        return LabelQuestion(
            url: url, title: title, text: await Self.plainText(preview.contentHTML),
            choices: hints.choices(labels, collections: { rules.collections(containing: $0) }, excluding: url),
            siteLabels: hints.siteLabels(for: url), neighbours: similar, corrections: corrections, content: content)
    }

    /// Off the main thread, once for every engine asked: a long page's
    /// markup takes a moment.
    @concurrent nonisolated static func plainText(_ html: String) async -> String {
        PageText.plain(fromHTML: html)
    }
}

/// A page's label question (`AppState.labelQuestion`), asked of one
/// engine chain or another.
struct LabelQuestion {
    let url: String
    let title: String
    let text: String
    let choices: [LabelChoice]
    let siteLabels: [String: Int]
    let neighbours: [LabelNeighbour]
    let corrections: [LabelCorrection]
    let content: AIContent

    func ask(_ chain: EngineChain) async throws -> LabelSuggestion {
        try await LabelClassifier(chain: chain).suggest(
            title: title, url: url, text: text, choices: choices, siteLabels: siteLabels, neighbours: neighbours,
            corrections: corrections, content: content)
    }
}
