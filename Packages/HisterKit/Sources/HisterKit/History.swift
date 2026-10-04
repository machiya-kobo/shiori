import Foundation

// Hister's history: what it indexed when, what you opened from a search
// (which it ranks first the next time), and the counts per day and month
// behind the Library's By Date view. All with `Origin: hister://`, which
// Hister's CSRF check lets through.

/// One page you opened from a search.
public struct OpenedEntry: Sendable, Equatable, Hashable, Identifiable, Decodable {
    public var id: Int
    public var url: String
    public var title: String
    /// The search it was opened from, as Hister keeps it (with
    /// `Notes.exclusion` since notes moved to Kura): the key to forget it by.
    public var query: String
    public var added: Date
    /// The search as it was typed, for showing.
    public var typedQuery: String {
        let shown = Notes.withoutExclusion(query)
        return shown.hasSuffix("*") ? String(shown.dropLast()) : shown
    }

    public init(id: Int, url: String, title: String, query: String, added: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.query = query
        self.added = added
    }

    private enum Keys: String, CodingKey { case id, url, title, query, added }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(Int.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        query = try c.decodeIfPresent(String.self, forKey: .query) ?? ""
        added = Date(timeIntervalSince1970: TimeInterval(try c.decodeIfPresent(Int64.self, forKey: .added) ?? 0))
    }
}

/// Counts per calendar day, then month, as Hister groups them.
public struct Timeline: Sendable, Equatable, Decodable {
    public struct Bucket: Sendable, Equatable, Hashable, Identifiable, Decodable {
        public var id: String { key }
        /// "day:2026-09-28", "month:2026-08", "older".
        public var key: String
        public var from: Date?
        public var to: Date?
        public var count: Int

        public init(key: String, from: Date?, to: Date?, count: Int) {
            self.key = key
            self.from = from
            self.to = to
            self.count = count
        }

        private enum Keys: String, CodingKey { case key, from, to, count }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            key = try c.decode(String.self, forKey: .key)
            count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
            self.from = try c.decodeIfPresent(Int64.self, forKey: .from).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            to = try c.decodeIfPresent(Int64.self, forKey: .to).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
    }

    public var days: [Bucket]
    public var months: [Bucket]
    public var older: Bucket?

    /// Newest first, empty ones left out.
    public var buckets: [Bucket] {
        (days + months + (older.map { [$0] } ?? [])).filter { $0.count > 0 }
    }

    public init(days: [Bucket], months: [Bucket] = [], older: Bucket? = nil) {
        self.days = days
        self.months = months
        self.older = older
    }

    private enum Keys: String, CodingKey { case days, months, older }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        days = try c.decodeIfPresent([Bucket].self, forKey: .days) ?? []
        months = try c.decodeIfPresent([Bucket].self, forKey: .months) ?? []
        older = try? c.decodeIfPresent(Bucket.self, forKey: .older)
    }
}

/// One page of the indexed history, and where the next starts.
public struct HistoryPage: Sendable, Equatable {
    public var documents: [StoredPage]
    /// Pass back for the next page; nil on the last.
    public var next: String?
}

/// One page of what you opened, and where the next starts.
public struct OpenedPage: Sendable, Equatable {
    public struct Cursor: Sendable, Equatable {
        public var lastID: Int
        public var lastUpdatedAt: String
    }
    public var entries: [OpenedEntry]
    public var next: Cursor?
}

/// A stored earlier version of a page: what changed since.
public struct PageVersion: Sendable, Equatable, Identifiable, Decodable {
    public var id: Int
    public var created: Date
    public var textDiff: String
    public var htmlDiff: String

    private enum Keys: String, CodingKey { case id, created_at, text_diff, html_diff }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(Int.self, forKey: .id)
        let stamp = try c.decodeIfPresent(String.self, forKey: .created_at) ?? ""
        created = (try? Date(stamp, strategy: .iso8601)) ?? (try? Date(stamp, strategy: PageVersion.fractional)) ?? .distantPast
        textDiff = try c.decodeIfPresent(String.self, forKey: .text_diff) ?? ""
        htmlDiff = try c.decodeIfPresent(String.self, forKey: .html_diff) ?? ""
    }

    public init(id: Int, created: Date, textDiff: String, htmlDiff: String = "") {
        self.id = id
        self.created = created
        self.textDiff = textDiff
        self.htmlDiff = htmlDiff
    }

    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}

/// Index totals, for Settings.
public struct ServerStats: Sendable, Equatable, Decodable {
    public var documents: Int
    public var files: Int
    public var rules: Int
    public var aliases: Int

    private enum Keys: String, CodingKey { case doc_count, file_count, rule_count, alias_count }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        documents = try c.decodeIfPresent(Int.self, forKey: .doc_count) ?? 0
        files = try c.decodeIfPresent(Int.self, forKey: .file_count) ?? 0
        rules = try c.decodeIfPresent(Int.self, forKey: .rule_count) ?? 0
        aliases = try c.decodeIfPresent(Int.self, forKey: .alias_count) ?? 0
    }
}

/// What the server can do, from `api/config`.
public struct ServerCapabilities: Sendable, Equatable {
    /// Meaning-based search is set up on the server.
    public var semantic: Bool

    public init(semantic: Bool) {
        self.semantic = semantic
    }
}

/// One of the server's content extractors that can render a preview.
public struct Extractor: Sendable, Equatable, Hashable, Identifiable, Decodable {
    public var id: String { name }
    public var name: String
    public var summary: String

    private enum Keys: String, CodingKey { case name, description, enabled, capabilities }
    private struct Capabilities: Decodable { var preview: Bool? }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        name = try c.decode(String.self, forKey: .name)
        summary = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }

    public init(name: String, summary: String = "") {
        self.name = name
        self.summary = summary
    }

    /// For filtering the list: enabled, and able to render a preview.
    struct Wire: Decodable {
        var extractor: Extractor
        var usable: Bool
        init(from decoder: any Decoder) throws {
            extractor = try Extractor(from: decoder)
            let c = try decoder.container(keyedBy: Keys.self)
            let enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            let preview = (try? c.decodeIfPresent(Capabilities.self, forKey: .capabilities))??.preview ?? true
            usable = enabled && preview
        }
    }
}

extension HisterClient {
    // MARK: Opened results

    /// Tells Hister you opened `url` from a search for `query`, so it ranks
    /// it first the next time. Best effort: a failure changes nothing.
    /// Hister matches the exact query text, so it's recorded as searches
    /// are sent (`SearchText.forHister`: a prefix, no notes).
    public func recordOpened(url: String, title: String, query: String) async throws(HisterError) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let body = try encodeJSON(["url": url, "title": title, "query": SearchText.forHister(trimmed)])
        _ = try await send(makeRequest("api/history", method: "POST", body: body))
    }

    /// Stops ranking `url` first for `query`.
    public func forgetOpened(url: String, query: String) async throws(HisterError) {
        let body = try encodeJSON(["url": url, "query": query, "delete": true] as [String: any Sendable])
        _ = try await send(makeRequest("api/history", method: "POST", body: body))
    }

    // MARK: History lists

    /// Pages indexed in [from, to), newest first; `filter` matches title or URL.
    public func indexedHistory(from: Date? = nil, to: Date? = nil, filter: String = "", after: String? = nil)
        async throws(HisterError) -> HistoryPage
    {
        var items = Self.rangeItems(from: from, to: to, filter: filter)
        if let after, !after.isEmpty { items.append(URLQueryItem(name: "last", value: after)) }
        let response: SearchResponse = try await decode(send(makeRequest("api/history", query: items, accept: "application/json")))
        let documents = (response.documents ?? []).map(\.document)
        // A full page (Hister's is 100) means there may be more.
        return HistoryPage(documents: documents, next: documents.count >= 100 ? documents.last?.url : nil)
    }

    /// Results you opened, newest first.
    public func openedHistory(from: Date? = nil, to: Date? = nil, filter: String = "", after: OpenedPage.Cursor? = nil)
        async throws(HisterError) -> OpenedPage
    {
        struct Reply: Decodable {
            var documents: [OpenedEntry]?
            var last_id: Int?
            var last_updated_at: String?
        }
        var items = [URLQueryItem(name: "opened", value: "true")] + Self.rangeItems(from: from, to: to, filter: filter)
        if let after {
            items.append(URLQueryItem(name: "last_id", value: String(after.lastID)))
            items.append(URLQueryItem(name: "last_updated_at", value: after.lastUpdatedAt))
        }
        let reply: Reply = try await decode(send(makeRequest("api/history", query: items, accept: "application/json")))
        let entries = reply.documents ?? []
        let next = entries.count >= 100 ? reply.last_id.flatMap { id in
            reply.last_updated_at.map { OpenedPage.Cursor(lastID: id, lastUpdatedAt: $0) }
        } : nil
        return OpenedPage(entries: entries, next: next)
    }

    /// Counts per day (the last week) and month, in `timeZone`'s calendar.
    public func timeline(opened: Bool = false, filter: String = "", timeZone: TimeZone = .current)
        async throws(HisterError) -> Timeline
    {
        var items = [URLQueryItem(name: "timezone", value: timeZone.identifier)]
        if opened { items.append(URLQueryItem(name: "opened", value: "true")) }
        if !filter.isEmpty { items.append(URLQueryItem(name: "filter", value: filter)) }
        return try await decode(send(makeRequest("api/history/timeline", query: items, accept: "application/json")))
    }

    /// Hister's own RSS feed of newly indexed pages.
    public var newPagesFeedURL: URL {
        var components = URLComponents(url: baseURL.appending(path: "api/history"), resolvingAgainstBaseURL: false)!
        components.setQueryItems([URLQueryItem(name: "format", value: "rss")])
        return components.url!
    }

    /// Hister's own RSS feed of the results you opened.
    public var openedFeedURL: URL {
        var components = URLComponents(url: baseURL.appending(path: "api/history"), resolvingAgainstBaseURL: false)!
        components.setQueryItems([URLQueryItem(name: "opened", value: "true"), URLQueryItem(name: "format", value: "rss")])
        return components.url!
    }

    static func rangeItems(from: Date?, to: Date?, filter: String) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let from { items.append(URLQueryItem(name: "date_from", value: String(Int(from.timeIntervalSince1970)))) }
        if let to { items.append(URLQueryItem(name: "date_to", value: String(Int(to.timeIntervalSince1970)))) }
        let filter = filter.trimmingCharacters(in: .whitespaces)
        if !filter.isEmpty { items.append(URLQueryItem(name: "filter", value: filter)) }
        return items
    }

    // MARK: Server details

    /// Stored earlier versions of a page, newest first. Empty unless one of
    /// the server's versioning rules covers the URL.
    public func versions(of url: String) async throws(HisterError) -> [PageVersion] {
        let versions: [PageVersion] = try await decode(
            send(makeRequest("api/versions", query: [URLQueryItem(name: "url", value: url)], accept: "application/json")))
        return versions.sorted { $0.created > $1.created }
    }

    /// The sites Hister has the most pages from, most first.
    public func topDomains(limit: Int = 200) async throws(HisterError) -> [String] {
        let items = [URLQueryItem(name: "q", value: SearchText.forHister("*")), URLQueryItem(name: "size_domains", value: String(limit))]
        let facets: Facets = try await decode(send(makeRequest("api/facets", query: items, accept: "application/json")))
        return (facets.terms["domains"]?.terms ?? []).map(\.term)
    }

    public func stats() async throws(HisterError) -> ServerStats {
        try await decode(send(makeRequest("api/stats", accept: "application/json")))
    }

    public func capabilities() async throws(HisterError) -> ServerCapabilities {
        struct Reply: Decodable { var semanticEnabled: Bool? }
        let reply: Reply = try await decode(send(makeRequest("api/config", accept: "application/json")))
        return ServerCapabilities(semantic: reply.semanticEnabled ?? false)
    }

    /// Extractors that can render this page's preview another way.
    public func extractors(for url: String) async throws(HisterError) -> [Extractor] {
        let wires: [Extractor.Wire] = try await decode(
            send(makeRequest("api/extractors", query: [URLQueryItem(name: "url", value: url)], accept: "application/json")))
        return wires.filter(\.usable).map(\.extractor)
    }
}
