import Foundation

/// Kura, the notes' own search and reader: the apps ask it for notes,
/// never Hister's label:vault.
/// Its replies come back as a `SearchPage` of `label: vault` notes, so the
/// lists, grouping and paging built on Hister's pages take them unchanged;
/// the page key is the offset.
public struct KuraClient: Sendable {
    public let baseURL: URL
    let session: URLSession

    public init?(serverURL: String, session: URLSession = HisterClient.defaultSession) {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.hasSuffix("/") { s += "/" }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http", url.host() != nil
        else { return nil }
        self.baseURL = url
        self.session = session
    }

    /// A page of notes: a search, or the newest changed first for "*"
    /// (Kura's recent list). Hister's own operators and @collections are
    /// dropped (Kura reads words, "phrases", -word, word*, title:, tag:,
    /// folder:), as for the web.
    /// `vaults`: one name, a comma list or "all" (Kura's `vault`); nil is
    /// the default vault only. Only Shiori's Notes lists send it.
    public func search(
        _ text: String, sort: SearchSort = .relevance, pageKey: String? = nil, limit: Int = 30, vaults: String? = nil
    ) async throws(HisterError) -> SearchPage {
        let offset = Int(pageKey ?? "") ?? 0
        let url = Self.url(base: baseURL, text: text, sort: sort, limit: limit, offset: offset, vaults: vaults)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: URLRequest(url: url))
        } catch let error as URLError where error.code == .cancelled {
            throw .cancelled
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw HisterError(transport: error)
        }
        guard let http = response as? HTTPURLResponse else { throw .badResponse }
        guard (200..<300).contains(http.statusCode) else { throw .server(status: http.statusCode, message: "") }
        guard let page = Self.page(from: data, offset: offset) else { throw .badResponse }
        return page
    }

    /// Kura's vaults (`/api/vaults`): the default one and the
    /// work vaults, with their titles and Obsidian vault names.
    public func vaults() async throws(HisterError) -> [KuraVault] {
        struct Reply: Decodable { let vaults: [KuraVault] }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: URLRequest(url: baseURL.appending(path: "api/vaults")))
        } catch {
            throw HisterError(transport: error)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            let reply = try? JSONDecoder().decode(Reply.self, from: data)
        else { throw .badResponse }
        return reply.vaults
    }

    /// A note's sanitized HTML from Kura (`/api/note`), for previewing a
    /// work note, which Hister never has. Not cached anywhere.
    public func noteHTML(path: String, vault: String) async throws(HisterError) -> String {
        struct Reply: Decodable { let html: String? }
        var components = URLComponents(url: baseURL.appending(path: "api/note"), resolvingAgainstBaseURL: false)!
        components.setQueryItems([URLQueryItem(name: "path", value: path), URLQueryItem(name: "vault", value: vault)])
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: URLRequest(url: components.url!))
        } catch {
            throw HisterError(transport: error)
        }
        guard let http = response as? HTTPURLResponse else { throw .badResponse }
        guard http.statusCode == 200 else { throw .server(status: http.statusCode, message: "") }
        guard let html = (try? JSONDecoder().decode(Reply.self, from: data))?.html else { throw .badResponse }
        return html
    }

    /// Kura's RSS of notes (`feed.xml`: the 50 most recently changed, or
    /// the newest 50 matching `q`), the Notes lists' feed.
    /// No prefix here: a feed is a saved search, not typing.
    public static func feedURL(serverURL: String, text: String) -> URL? {
        guard let kura = KuraClient(serverURL: serverURL) else { return nil }
        let words = SearxClient.webQuery(text)
        var components = URLComponents(url: kura.baseURL.appending(path: "feed.xml"), resolvingAgainstBaseURL: false)!
        if !words.isEmpty, words != "*" { components.setQueryItems([URLQueryItem(name: "q", value: words)]) }
        return components.url
    }

    /// The words Kura searches for, the last one a prefix
    /// (`SearchText.prefixLastWord`); "" means its recent list.
    static func query(_ text: String) -> String {
        let words = SearxClient.webQuery(text)
        return words == "*" ? "" : SearchText.prefixLastWord(words)
    }

    static func url(base: URL, text: String, sort: SearchSort, limit: Int, offset: Int, vaults: String? = nil) -> URL {
        let words = query(text)
        var items = [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))]
        if let vaults, !vaults.isEmpty { items.append(URLQueryItem(name: "vault", value: vaults)) }
        if !words.isEmpty {
            items.append(URLQueryItem(name: "q", value: words))
            // Newest first is Kura's "changed" (the note's latest commit).
            items.append(URLQueryItem(name: "sort", value: sort == .newest ? "changed" : "relevance"))
        }
        var components = URLComponents(url: base.appending(path: words.isEmpty ? "api/recent" : "api/search"), resolvingAgainstBaseURL: false)!
        components.setQueryItems(items)
        return components.url!
    }

    /// Kura's reply as Hister's page: each note a `label: vault` document,
    /// its snippet (escaped HTML whose only markup is <mark>) as Hister's.
    static func page(from data: Data, offset: Int) -> SearchPage? {
        struct Reply: Decodable {
            struct Note: Decodable {
                let url: String
                let title: String?
                let path: String?
                let snippet: String?
                let summary: String?
                let created: Double?
                let changed: Double?
            }
            let total: Int?
            let results: [Note]
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        let notes = reply.results.filter { $0.url.hasPrefix("https://") || $0.url.hasPrefix("http://") }
        let documents = notes.map { note in
            let changed = note.changed ?? note.created ?? 0
            return StoredPage(
                url: note.url, title: note.title ?? note.path ?? "", domain: URL(string: note.url)?.host() ?? "",
                label: Notes.label, added: Date(timeIntervalSince1970: note.created ?? changed),
                updated: Date(timeIntervalSince1970: changed), faviconKey: "", snippetHTML: note.snippet ?? note.summary ?? "")
        }
        let total = max(reply.total ?? documents.count, documents.count)
        let next = offset + reply.results.count
        return SearchPage(
            total: total, documents: documents, nextPageKey: next < total && !reply.results.isEmpty ? String(next) : nil,
            suggestion: nil)
    }
}

/// One of Kura's vaults (`/api/vaults`).
public struct KuraVault: Sendable, Equatable, Hashable, Identifiable, Decodable {
    public var id: String { name }
    public var name: String
    public var title: String
    public var isDefault: Bool
    /// A work vault: kept out of Hister, AI, caches, exports and feeds.
    public var isPrivate: Bool
    /// Its name in Obsidian, for obsidian://open.
    public var obsidian: String
    public var notes: Int?

    public init(name: String, title: String, isDefault: Bool, isPrivate: Bool, obsidian: String, notes: Int? = nil) {
        self.name = name
        self.title = title
        self.isDefault = isDefault
        self.isPrivate = isPrivate
        self.obsidian = obsidian
        self.notes = notes
    }

    private enum Keys: String, CodingKey { case name, title, notes, obsidian, isDefault = "default", isPrivate = "private" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        name = try c.decode(String.self, forKey: .name)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? name
        isDefault = (try? c.decodeIfPresent(Bool.self, forKey: .isDefault)) ?? false
        isPrivate = (try? c.decodeIfPresent(Bool.self, forKey: .isPrivate)) ?? !isDefault
        obsidian = (try? c.decodeIfPresent(String.self, forKey: .obsidian)) ?? name
        notes = try? c.decodeIfPresent(Int.self, forKey: .notes)
    }
}
