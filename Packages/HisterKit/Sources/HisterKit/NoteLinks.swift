import Foundation

/// A link in a note's body, as Kura lists it (`external_links`: http(s)
/// only, Kura's and the other rooms' hosts left out).
public struct NoteLink: Sendable, Equatable, Hashable, Decodable {
    public var url: String
    public var text: String

    public init(url: String, text: String) {
        self.url = url
        self.text = text
    }

    private enum CodingKeys: String, CodingKey { case url, text }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
    }
}

/// A note and the links in it (Kura's `/api/note`, or one of `/api/links`'
/// notes). Default vault only: Kura answers `[]` for a work note, so no
/// work link can reach a save.
public struct LinkedNote: Sendable, Equatable, Decodable {
    public var path: String
    public var title: String
    public var url: String
    public var tags: [String]
    public var externalLinks: [NoteLink]

    public init(path: String, title: String, url: String, tags: [String] = [], externalLinks: [NoteLink]) {
        self.path = path
        self.title = title
        self.url = url
        self.tags = tags
        self.externalLinks = externalLinks
    }

    private enum CodingKeys: String, CodingKey {
        case path, title, url, tags
        case externalLinks = "external_links"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        // Absent before Kura shipped the field: no links, not an error.
        externalLinks = (try? c.decode([NoteLink].self, forKey: .externalLinks)) ?? []
    }
}

/// One link offered for saving, with the note it was found in first.
public struct LinkToSave: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { url }
    public var url: String
    public var text: String
    public var notePath: String
    public var noteTitle: String

    public init(url: String, text: String, notePath: String, noteTitle: String) {
        self.url = url
        self.text = text
        self.notePath = notePath
        self.noteTitle = noteTitle
    }
}

/// Save This Note's Links: Shiori saves pages into Hister; the other rooms
/// only look up what it holds. The pure part, twin of
/// search-core's `saveLinkRows` / `tagLabelCandidates`, with the same tests.
public enum SaveLinks {
    /// At most this many links a run (a folder can hold hundreds).
    public static let cap = 200

    /// The schemes a note's links are saved from: web pages, and Gemini and
    /// Gopher through the small-web gateway.
    public static let schemes: Set<String> = ["http", "https", "gemini", "gopher"]

    /// A `gemini://` or `gopher://` link: saved through the gateway, never
    /// fetched here.
    public static func isSmallWeb(_ url: String) -> Bool {
        guard let scheme = URLComponents(string: url)?.scheme?.lowercased() else { return false }
        return scheme == "gemini" || scheme == "gopher"
    }

    /// The links to offer from these notes, in order: http(s), gemini and
    /// gopher, each once across all the notes (web links compared without
    /// fragment, "www.", tracking parameters or a trailing slash; small-web
    /// ones only with scheme and host lowercased and the default port
    /// dropped), at most `cap`.
    public static func links(in notes: [LinkedNote], cap: Int = cap) -> [LinkToSave] {
        var seen = Set<String>()
        var out: [LinkToSave] = []
        for note in notes {
            for link in note.externalLinks {
                guard out.count < cap, let u = URLComponents(string: link.url),
                    let scheme = u.scheme?.lowercased(), schemes.contains(scheme), u.host != nil,
                    seen.insert(isSmallWeb(link.url) ? smallWebKey(link.url) : comparable(link.url)).inserted
                else { continue }
                out.append(LinkToSave(url: link.url, text: link.text, notePath: note.path, noteTitle: note.title))
            }
        }
        return out
    }

    /// The note's tags that name an existing label: "music" or a nested
    /// "topic/music" for the label `music`, case aside. Never an invented
    /// label: anything else is the picker's.
    public static func labelCandidates(tags: [String], labels: [String]) -> [String] {
        let known = Dictionary(labels.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        var out: [String] = []
        for tag in tags {
            let bare = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
            let last = bare.split(separator: "/").last.map(String.init) ?? bare
            if let label = known[last.lowercased()], !out.contains(label) { out.append(label) }
        }
        return out
    }

    /// File types a link can name that aren't web pages (packages, archives,
    /// disk images, media, PDFs for now): offered as "a file", not saved.
    public static let fileExtensions: Set<String> = [
        "deb", "rpm", "apk", "pkg", "dmg", "exe", "msi", "iso", "img", "zip", "tgz", "gz", "xz", "bz2", "7z", "rar", "tar",
        "jar", "whl", "png", "jpg", "jpeg", "gif", "webp", "mp3", "mp4", "mkv", "mov", "webm", "pdf",
    ]

    /// Whether a link names a file rather than a page, by its path's
    /// extension (search-core's `linkLooksLikeFile`).
    public static func looksLikeFile(_ raw: String) -> Bool {
        guard let path = URLComponents(string: raw)?.path, let dot = path.lastIndex(of: "."),
            !path[dot...].contains("/")
        else { return false }
        return fileExtensions.contains(path[path.index(after: dot)...].lowercased())
    }

    /// A gemini:// or gopher:// link compared conservatively: scheme and host
    /// lowercased, the default port (1965, 70) dropped, nothing else
    /// (search-core's `smallWebKey`).
    public static func smallWebKey(_ raw: String) -> String {
        guard var u = URLComponents(string: raw), let scheme = u.scheme?.lowercased() else { return raw }
        u.scheme = scheme
        u.host = u.host?.lowercased()
        if (scheme == "gemini" && u.port == 1965) || (scheme == "gopher" && u.port == 70) { u.port = nil }
        return u.string ?? raw
    }

    /// The form two links are compared in (search-core's `normalizeURL`).
    static func comparable(_ raw: String) -> String {
        guard let u = URLComponents(string: raw), let host = u.host?.lowercased() else { return raw }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var path = u.path
        while path.hasSuffix("/") { path.removeLast() }
        let tracking = /^(utm_\w+|fbclid|gclid|mc_cid|mc_eid|ref_src)$/.ignoresCase()
        let items = (u.queryItems ?? []).filter { (try? tracking.wholeMatch(in: $0.name)) == nil }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
        return bareHost + path + (items.isEmpty ? "" : "?" + items.joined(separator: "&"))
    }
}

extension KuraClient {
    /// A note's outside links, with its title and tags (`/api/note`, the
    /// default vault).
    public func noteLinks(path: String) async throws(HisterError) -> LinkedNote {
        try await get("api/note", [URLQueryItem(name: "path", value: path)])
    }

    /// The links of every note under a folder of the default vault
    /// (`/api/links`), a page at a time. Notes without links aren't listed.
    public func folderLinks(folder: String, limit: Int = 100, offset: Int = 0) async throws(HisterError) -> (total: Int, notes: [LinkedNote]) {
        struct Reply: Decodable {
            var total: Int?
            var notes: [LinkedNote]?
        }
        let reply: Reply = try await get("api/links", [
            URLQueryItem(name: "folder", value: folder),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return (reply.total ?? 0, reply.notes ?? [])
    }

    /// Every note under a folder that has links, paging through
    /// `/api/links` until `SaveLinks.cap` links are in hand or none are left.
    public func allFolderLinks(folder: String) async throws(HisterError) -> [LinkedNote] {
        var notes: [LinkedNote] = []
        var offset = 0
        var links = 0
        while links < SaveLinks.cap {
            let page = try await folderLinks(folder: folder, limit: 100, offset: offset)
            notes += page.notes
            links += page.notes.reduce(0) { $0 + $1.externalLinks.count }
            offset += page.notes.count
            if page.notes.isEmpty || offset >= page.total { break }
        }
        return notes
    }

    private func get<T: Decodable>(_ path: String, _ items: [URLQueryItem]) async throws(HisterError) -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.setQueryItems(items)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: URLRequest(url: components.url!))
        } catch {
            throw HisterError(transport: error)
        }
        guard let http = response as? HTTPURLResponse else { throw .badResponse }
        guard http.statusCode == 200 else { throw .server(status: http.statusCode, message: "") }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw .badResponse
        }
    }
}
