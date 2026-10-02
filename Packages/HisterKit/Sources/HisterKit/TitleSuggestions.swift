import Foundation

/// Your pages and notes whose titles match what's being typed, for the
/// search field's suggestions: the same rules as search-core.js's
/// `suggestionQueries` and `titleMatches` (the web app and the search page
/// use those).
public enum TitleSuggestions {
    /// The Hister queries to run, or none: the last word as a title prefix
    /// (a word being typed matches nothing whole), then the words as plain
    /// text (a joined "helloworld" is no title's prefix). Nothing for
    /// under two characters or any query syntax.
    public static func queries(for text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard trimmed.count >= 2, let last = words.last,
            !words.contains(where: { $0.contains(where: ":\"'*~()|".contains) || $0.hasPrefix("-") || $0.hasPrefix("+") })
        else { return [] }
        return [(words.dropLast() + ["title:\(last)*"]).joined(separator: " "), words.joined(separator: " ")]
    }

    /// Whether a title holds every typed word, ignoring case and spaces:
    /// "helloworld" matches "Hello World", "pytho" "Learn Python".
    public static func matches(title: String, text: String) -> Bool {
        let compact = title.lowercased().filter { !$0.isWhitespace }
        let words = text.lowercased().split(whereSeparator: \.isWhitespace)
        return !words.isEmpty && words.allSatisfy { compact.contains($0) }
    }
}

extension HisterClient {
    /// Pages and notes for the typed text whose titles match it (up to
    /// `pages` and `notes` of each), from both `TitleSuggestions` queries.
    public func titleSuggestions(for text: String, pages: Int = 4, notes: Int = 3) async -> (pages: [StoredPage], notes: [StoredPage]) {
        var seen = Set<String>()
        var found: [StoredPage] = []
        for query in TitleSuggestions.queries(for: text) {
            guard let page = try? await search(query, limit: 20) else { continue }
            found += page.documents.filter { TitleSuggestions.matches(title: $0.displayTitle, text: text) && seen.insert($0.url).inserted }
        }
        let isNote = { (page: StoredPage) in page.label == Notes.label }
        return (Array(found.filter { !isNote($0) }.prefix(pages)), Array(found.filter(isNote).prefix(notes)))
    }
}

extension SearxClient {
    /// Search suggestions for what's typed, from SearXNG's autocompleter
    /// (OpenSearch shape: `["typed", ["one", "two"], …]`); none on failure.
    public func autocomplete(_ text: String) async -> [String] {
        var components = URLComponents(url: baseURL.appending(path: "autocompleter"), resolvingAgainstBaseURL: false)!
        components.setQueryItems([URLQueryItem(name: "q", value: text)])
        guard let (data, response) = try? await session.data(from: components.url!),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return [] }
        return Self.parseAutocomplete(data, typed: text)
    }

    /// Up to five suggestions, leaving out the typed text itself.
    static func parseAutocomplete(_ data: Data, typed: String, limit: Int = 5) -> [String] {
        guard let reply = try? JSONSerialization.jsonObject(with: data) as? [Any], reply.count > 1,
            let list = reply[1] as? [Any]
        else { return [] }
        let mine = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return Array(list.compactMap { $0 as? String }
            .filter { $0.trimmingCharacters(in: .whitespaces).lowercased() != mine }
            .prefix(limit))
    }
}

/// Labels and collections whose names hold the word being typed, for the
/// search field's suggestions: the same rule as search-core.js's
/// `labelSuggestions` (collections first, then labels; names that start
/// with the word before ones that only contain it). Picking one searches
/// its query, so a label is findable among hundreds without scrolling.
public enum LabelSuggestions {
    public struct Item: Sendable, Equatable, Hashable, Identifiable {
        public enum Kind: Sendable, Hashable { case label, collection }
        public var kind: Kind
        /// As shown: a label's name, a collection's without its "@".
        public var name: String
        /// What picking it searches: `label:topic`, `@alpha`.
        public var query: String
        public var id: String { query }
    }

    public static func items(for text: String, rules: Rules, limit: Int = 6) -> [Item] {
        guard let word = text.lowercased().split(whereSeparator: \.isWhitespace).last.map(String.init),
            word.count >= 2, !word.contains(where: ":\"*~()|".contains)
        else { return [] }
        func rank(_ name: String) -> Int? {
            let lower = name.lowercased()
            return lower.hasPrefix(word) ? 0 : lower.contains(word) ? 1 : nil
        }
        let collections = rules.collections.map(\.name).compactMap { key -> (Int, Item)? in
            let name = key.hasPrefix("@") ? String(key.dropFirst()) : key
            return rank(name).map { ($0, Item(kind: .collection, name: name, query: key)) }
        }
        let labels = rules.labels.compactMap { label -> (Int, Item)? in
            rank(label).map { ($0, Item(kind: .label, name: label, query: "label:\(label)")) }
        }
        let order: ((Int, Item), (Int, Item)) -> Bool = { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.name < $1.1.name }
        return Array((collections.sorted(by: order) + labels.sorted(by: order)).map(\.1).prefix(limit))
    }
}
