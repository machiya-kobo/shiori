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
    /// hour (labels change as the user files pages).
    func labelHintsIfNeeded() async -> LabelHints {
        if let hints = labelHints, Date().timeIntervalSince(hints.loadedAt) < 30 * 60 { return hints }
        guard let client else { return LabelHints() }
        let hints = await LabelHints.load(using: client)
        labelHints = hints
        return hints
    }
}
