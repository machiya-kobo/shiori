import Foundation

/// One page of search results from `GET /search`.
public struct SearchPage: Sendable, Equatable {
    public var total: Int
    public var documents: [StoredPage]
    /// Pass back to fetch the next page; nil on the last page.
    public var nextPageKey: String?
    /// The server's "did you mean", if any.
    public var suggestion: String?
    /// Results you opened before for this query, best first (first page only).
    public var opened: [OpenedResult]
    /// Counts per filter value, when asked for (`SearchOptions.facets`).
    public var facets: Facets?

    public init(
        total: Int, documents: [StoredPage], nextPageKey: String?, suggestion: String?,
        opened: [OpenedResult] = [], facets: Facets? = nil
    ) {
        self.total = total
        self.documents = documents
        self.nextPageKey = nextPageKey
        self.suggestion = suggestion
        self.opened = opened
        self.facets = facets
    }
}

/// What a search asks for besides its text.
public struct SearchOptions: Sendable, Equatable {
    /// Counts per filter value (domains, languages, types, visits, dates).
    public var facets = false
    /// Only pages updated in this range (a custom range; presets are query words).
    public var dateFrom: Date?
    public var dateTo: Date?
    /// Mix in meaning-based matches, where the server has them on.
    public var semantic = false

    public init(facets: Bool = false, dateFrom: Date? = nil, dateTo: Date? = nil, semantic: Bool = false) {
        self.facets = facets
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.semantic = semantic
    }
}

/// A result you opened for a query before; Hister puts these first.
public struct OpenedResult: Sendable, Equatable, Hashable, Identifiable, Decodable {
    public var id: String { url }
    public var url: String
    public var title: String
    /// How many times you opened it for this query.
    public var count: Int
    /// Pinned in Hister's web UI (a priority rule): shown, never changed here.
    public var pinned: Bool
    /// The stored page's host and dates, when Hister sends them (it does
    /// since 2026-09; older replies had none, and the row showed the
    /// distant past as "2,026 years ago").
    public var domain: String?
    public var added: Date?
    public var updated: Date?

    public init(
        url: String, title: String, count: Int = 1, pinned: Bool = false,
        domain: String? = nil, added: Date? = nil, updated: Date? = nil
    ) {
        self.url = url
        self.title = title
        self.count = count
        self.pinned = pinned
        self.domain = domain
        self.added = added
        self.updated = updated
    }

    private enum Keys: String, CodingKey { case url, title, count, pinned, domain, added, updated }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        domain = (try? c.decodeIfPresent(String.self, forKey: .domain)).flatMap { $0.isEmpty ? nil : $0 }
        func date(_ key: Keys) -> Date? {
            guard let seconds = try? c.decodeIfPresent(Double.self, forKey: key), seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        added = date(.added)
        updated = date(.updated)
    }
}

/// Counts per filter value for one search.
public struct Facets: Sendable, Equatable, Decodable {
    public struct Term: Sendable, Equatable, Hashable, Decodable {
        public var term: String
        public var count: Int
        /// The server's name for a range value ("2 to 4"), if any.
        public var label: String?

        public init(term: String, count: Int, label: String? = nil) {
            self.term = term
            self.count = count
            self.label = label
        }
    }
    public struct TermFacet: Sendable, Equatable, Decodable {
        public var terms: [Term]
        /// Matches in values not listed (past the server's cap).
        public var other: Int

        private enum Keys: String, CodingKey { case terms, other }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            terms = try c.decodeIfPresent([Term].self, forKey: .terms) ?? []
            other = try c.decodeIfPresent(Int.self, forKey: .other) ?? 0
        }

        public init(terms: [Term], other: Int = 0) {
            self.terms = terms
            self.other = other
        }
    }
    public struct Bucket: Sendable, Equatable, Decodable {
        public var name: String
        public var count: Int
    }

    /// Per facet name ("domains", "languages", "types", "visits").
    public var terms: [String: TermFacet]
    /// Per time bucket ("last_24h", "last_7d", "last_30d", "last_year", "older").
    public var dates: [Bucket]

    private enum Keys: String, CodingKey { case terms, date_histogram }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        terms = try c.decodeIfPresent([String: TermFacet].self, forKey: .terms) ?? [:]
        dates = try c.decodeIfPresent([Bucket].self, forKey: .date_histogram) ?? []
    }

    public init(terms: [String: TermFacet], dates: [Bucket] = []) {
        self.terms = terms
        self.dates = dates
    }
}

/// A stored page, as search results describe it.
public struct StoredPage: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { url }
    public var url: String
    public var title: String
    public var domain: String
    /// A topic label; empty for pages that were only visited.
    public var label: String
    public var added: Date
    public var updated: Date
    /// Key for `GET /api/favicon`; empty when the page has none.
    public var faviconKey: String
    /// Matching text with `<mark>` around the hits (see `Snippet`).
    public var snippetHTML: String {
        didSet { snippet = Snippet(html: snippetHTML) }
    }
    /// `snippetHTML` parsed, once, when the page is made (not by every
    /// redraw of the row that shows it).
    public private(set) var snippet: Snippet

    public init(
        url: String, title: String, domain: String, label: String, added: Date, updated: Date,
        faviconKey: String, snippetHTML: String
    ) {
        self.url = url
        self.title = title
        self.domain = domain
        self.label = label
        self.added = added
        self.updated = updated
        self.faviconKey = faviconKey
        self.snippetHTML = snippetHTML
        self.snippet = Snippet(html: snippetHTML)
    }

    /// The title, or the URL when the page has none.
    public var displayTitle: String { title.isEmpty ? url : title }
}

/// `GET /api/preview`: Hister's readable copy of a page.
public struct PagePreview: Sendable, Equatable {
    public var title: String
    /// Sanitised article HTML, for display with scripts off.
    public var contentHTML: String
    public var added: Date
    public var updated: Date
    public var label: String
    public var visits: Int
    public var author: String?
    public var summary: String?
    /// A vault note's Obsidian tags (Konbini puts them in `metadata.tags`).
    public var tags: [String]

    public init(
        title: String, contentHTML: String, added: Date, updated: Date, label: String, visits: Int,
        author: String?, summary: String?, tags: [String] = []
    ) {
        self.tags = tags
        self.title = title
        self.contentHTML = contentHTML
        self.added = added
        self.updated = updated
        self.label = label
        self.visits = visits
        self.author = author
        self.summary = summary
    }
}

/// `GET /api/rules`, reduced to what a search client needs. Rules are read
/// only here: the server's files are the source of truth.
public struct Rules: Sendable, Equatable {
    /// Query shortcuts the server expands, e.g. `tech` → `label:(tech|...)`.
    public let aliases: [String: String]
    /// Every topic label the aliases name, sorted. Hister has no "list
    /// labels" endpoint, and an alias that names every label spells them all out. Found
    /// once here: the sidebar reads it on every frame of a column drag.
    public let labels: [String]

    /// The collections a label picker groups by: each "@" alias that names
    /// labels (`isCollectionKeyword`), with its labels sorted. Not one that
    /// names every label: grouped under it, everything would say its name
    /// and tell nothing.
    public let collections: [(name: String, labels: [String])]

    public init(aliases all: [String: String]) {
        // Not an alias about the notes (Hister's `@notes`, `@pages`, for
        // its own UI): Shiori has Notes and Pages already,
        // and they'd read as collections called "notes" and "pages".
        let aliases = all.filter { !Self.namesTheVault($0.value) }
        self.aliases = aliases
        var found = Set<String>()
        var byAlias: [String: Set<String>] = [:]
        for (alias, expansion) in aliases {
            for group in expansion.matches(of: /label:\(([^)]*)\)|label:([A-Za-z0-9_-]+)/) {
                let names = group.output.1.map(String.init) ?? group.output.2.map(String.init) ?? ""
                for name in names.split(separator: "|") where !name.isEmpty {
                    found.insert(String(name))
                    byAlias[alias, default: []].insert(String(name))
                }
            }
        }
        labels = found.sorted()
        let candidates = byAlias.filter { Self.isCollectionKeyword($0.key) }
        collections = candidates
            .filter { candidates.count == 1 || $0.value.count < found.count }
            .map { (name: $0.key, labels: $0.value.sorted()) }
            .sorted { $0.name < $1.name }
    }

    /// Whether an alias is a collection: only "@" keywords are (a Machiya
    /// convention; search-core's `isCollectionKeyword` is the twin). A plain
    /// alias is the user's own query, never listed or edited as one.
    public static func isCollectionKeyword(_ alias: String) -> Bool {
        alias.count > 1 && alias.hasPrefix("@") && !alias.dropFirst().first!.isWhitespace
    }

    /// An expansion that picks or drops the vault's notes by label or
    /// source (`label:vault`, `-metadata.source:vault`).
    public static func namesTheVault(_ expansion: String) -> Bool {
        expansion.range(of: #"(label|source):(\([^)]*)?\bvault\b"#, options: .regularExpression) != nil
    }

    /// The collections a page with this label shows up in.
    public func collections(containing label: String) -> [String] {
        collections.filter { $0.labels.contains(label) }.map(\.name)
    }

    /// Labels in none of `collections`.
    public var ungroupedLabels: [String] {
        let grouped = Set(collections.flatMap(\.labels))
        return labels.filter { !grouped.contains($0) }
    }

    public static func == (a: Rules, b: Rules) -> Bool { a.aliases == b.aliases }
}

// MARK: - Wire format

struct SearchResponse: Decodable {
    var total: Int
    var documents: [DocumentWire]?
    var page_key: String?
    var query_suggestion: String?
    var history: [OpenedResult]?
    var facets: Facets?

    private enum Keys: String, CodingKey { case total, documents, page_key, query_suggestion, history, facets }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        documents = try c.decodeIfPresent([DocumentWire].self, forKey: .documents)
        page_key = try c.decodeIfPresent(String.self, forKey: .page_key)
        query_suggestion = try c.decodeIfPresent(String.self, forKey: .query_suggestion)
        // Extras: never the reason a search fails.
        history = try? c.decodeIfPresent([OpenedResult].self, forKey: .history)
        facets = try? c.decodeIfPresent(Facets.self, forKey: .facets)
    }
}

struct DocumentWire: Decodable {
    var url: String
    var title: String?
    var domain: String?
    var label: String?
    var added: Int64?
    var updated: Int64?
    var favicon_key: String?
    var text: String?

    var document: StoredPage {
        StoredPage(
            url: url,
            title: title ?? "",
            // The history list sends "" rather than leaving it out.
            domain: domain.flatMap { $0.isEmpty ? nil : $0 } ?? URL(string: url)?.host() ?? "",
            label: label ?? "",
            added: Date(timeIntervalSince1970: TimeInterval(added ?? 0)),
            updated: Date(timeIntervalSince1970: TimeInterval(updated ?? added ?? 0)),
            faviconKey: favicon_key ?? "",
            snippetHTML: text ?? "")
    }
}

struct PreviewResponse: Decodable {
    struct Details: Decodable {
        /// Metadata is whatever each client sent: only a list of strings
        /// counts as tags, and nothing else here can fail the preview.
        struct Metadata: Decodable {
            var tags: [String]?
            private enum Keys: String, CodingKey { case tags }
            init(from decoder: any Decoder) throws {
                let c = try? decoder.container(keyedBy: Keys.self)
                tags = try? c?.decodeIfPresent([String].self, forKey: .tags)
            }
        }
        var label: String?
        var visits: Int?
        var metadata: Metadata?

        private enum Keys: String, CodingKey { case label, visits, metadata }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            label = try c.decodeIfPresent(String.self, forKey: .label)
            visits = try c.decodeIfPresent(Int.self, forKey: .visits)
            metadata = try? c.decodeIfPresent(Metadata.self, forKey: .metadata)
        }
    }
    struct Meta: Decodable {
        var author: String?
        var description: String?
    }
    var title: String?
    var content: String?
    var added: Int64?
    var updated: Int64?
    var details: Details?
    var meta: Meta?

    var preview: PagePreview {
        PagePreview(
            title: title ?? "",
            contentHTML: content ?? "",
            added: Date(timeIntervalSince1970: TimeInterval(added ?? 0)),
            updated: Date(timeIntervalSince1970: TimeInterval(updated ?? added ?? 0)),
            label: details?.label ?? "",
            visits: details?.visits ?? 0,
            author: meta?.author.flatMap { $0.isEmpty ? nil : $0 },
            summary: meta?.description.flatMap { $0.isEmpty ? nil : $0 },
            tags: details?.metadata?.tags ?? [])
    }
}

struct RulesResponse: Decodable {
    var aliases: [String: String]?
}
