import Foundation

/// One media service's address and token (from the Keychain; never logged,
/// never in a URL). Each service is optional.
public struct MediaAccount: Sendable, Equatable {
    public var base: String
    public var token: String

    /// Nil unless `base` is an absolute http(s) address and there's a token.
    public init?(base: String, token: String) {
        let b = Media.base(base)
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard b.hasPrefix("http"), let url = URL(string: b), url.host() != nil, !t.isEmpty, !t.contains(where: \.isNewline) else { return nil }
        self.base = b
        self.token = t
    }
}

/// A search's answer: one card per item, and the services that failed.
public struct MediaResults: Sendable, Equatable {
    public var items: [MediaItem]
    public var failures: [String]
    public init(items: [MediaItem] = [], failures: [String] = []) {
        self.items = items
        self.failures = failures
    }
}

/// The Media tab before a search.
public struct MediaShelves: Sendable, Equatable {
    public var nowPlaying: [MediaItem] = []
    public var listens: [MediaItem] = []
    public var watched: [MediaItem] = []
    public var artists: [MediaItem] = []
    public var albums: [MediaItem] = []
    public var tracks: [MediaItem] = []
    public var watchlist: [MediaItem] = []
    public var added: [MediaItem] = []
    public var period = "month"
    public var failures: [String] = []
    public init() {}
}

extension Media {
    /// "Plex didn't answer", or "Plex refused Shiori's token" for a 401 or 403.
    public static func failure(_ service: MediaService, status: Int?) -> String {
        "\(service.name) " + (status == 401 || status == 403 ? "refused Shiori's token" : "didn't answer")
    }
}

/// Asks the media services (search-core's `mediaSearch` and `mediaBrowse`).
/// Only GETs to read endpoints; each request carries its own service's
/// token and follows no redirect, so a token never leaves its service.
public actor MediaClient {
    struct Failed: Error {
        var status: Int?
    }

    nonisolated let accounts: [MediaService: MediaAccount]
    nonisolated let session: URLSession
    /// Each service's facts (Movary's user, Jellyfin's user and server, Plex's machine), asked once.
    var contexts: [MediaService: MediaContext] = [:]
    var factStatus: [MediaService: Int?] = [:]
    /// How many of Koito's matches get their play counts asked.
    static let koitoCounts = 12

    public init(accounts: [MediaService: MediaAccount], session: URLSession = HisterClient.defaultSession) {
        self.accounts = accounts
        self.session = session
    }

    public nonisolated var services: Set<MediaService> { Set(accounts.keys) }
    public nonisolated var isConfigured: Bool { !accounts.isEmpty }

    /// A card's art, from one of the services or TMDB only (`Media.imageURL`
    /// made the address): Plex's carries its token in a header, never the
    /// address; no redirect is followed; nothing past 5 MB. Nil for anything else.
    public nonisolated func imageData(_ address: String) async -> Data? {
        guard let url = URL(string: address), url.scheme == "https" || url.scheme == "http" else { return nil }
        let own = accounts.first { address.hasPrefix($0.value.base) }
        guard own != nil || address.hasPrefix("https://image.tmdb.org/t/p/") else { return nil }
        var request = URLRequest(url: url)
        if let own, own.key == .plex { request.setValue(own.value.token, forHTTPHeaderField: "X-Plex-Token") }
        guard let (data, response) = try? await session.data(for: request, delegate: NoRedirects()),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            (http.value(forHTTPHeaderField: "Content-Type") ?? "").hasPrefix("image/"), data.count <= 5 << 20
        else { return nil }
        return data
    }

    /// Settings' Test Connection: one read with the account's token, and what it says.
    public enum Check: Sendable, Equatable {
        /// It answered with the token: who or what, in a few words ("Signed in as shiori").
        case works(String)
        /// 401 or 403: the service doesn't take the token.
        case refused
        /// Nothing answered (address, network, certificate).
        case unreachable
        /// Something answered, but not as this service would.
        case unexpected(Int?)
    }

    /// Asks one service a read that needs its token: Jellyfin and Movary who
    /// the token is, Koito how many listens it holds, Plex its newest item.
    public nonisolated func check(_ service: MediaService) async -> Check {
        guard let account = accounts[service] else { return .unreachable }
        let url: String
        switch service {
        case .jellyfin: url = Media.requestURL(.jellyfin, "me", base: account.base)
        case .movary: url = Media.requestURL(.movary, "me", base: account.base)
        case .koito: url = Media.requestURL(.koito, "listens", base: account.base, args: MediaArgs(limit: 1))
        case .plex: url = Media.requestURL(.plex, "recent", base: account.base, args: MediaArgs(limit: 1))
        }
        let reply: Any
        do {
            reply = try await get(service, url)
        } catch {
            if error.status == 401 || error.status == 403 { return .refused }
            return error.status == nil ? .unreachable : .unexpected(error.status)
        }
        let r = Media.obj(reply)
        switch service {
        case .jellyfin:
            let name = Media.str(r["Name"])
            return Media.parseFacts(.jellyfin, "me", reply: reply)["user"] == nil ? .unexpected(nil) : .works(name.isEmpty ? "Signed in" : "Signed in as \(name)")
        case .movary:
            guard let user = Media.parseFacts(.movary, "me", reply: reply)["user"] as? String else { return .unexpected(nil) }
            return .works("Signed in as \(user)")
        case .koito:
            guard r["items"] is [Any] else { return .unexpected(nil) }
            guard let n = Media.int(r["total_record_count"]) else { return .works("Your listens answer") }
            return .works("\(n.formatted()) \(n == 1 ? "listen" : "listens")")
        case .plex:
            guard r["MediaContainer"] is [String: Any] else { return .unexpected(nil) }
            return .works("Your libraries answer")
        }
    }

    func context(_ service: MediaService) -> MediaContext {
        contexts[service] ?? MediaContext(api: accounts[service]?.base ?? "")
    }

    nonisolated func get(_ service: MediaService, _ address: String) async throws(Failed) -> Any {
        guard let account = accounts[service], !address.isEmpty, address.hasPrefix(account.base), let url = URL(string: address) else {
            throw Failed()
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch service {
        case .koito: request.setValue("Token \(account.token)", forHTTPHeaderField: "Authorization")
        case .movary: request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        case .jellyfin: request.setValue("MediaBrowser Token=\(account.token)", forHTTPHeaderField: "Authorization")
        case .plex: request.setValue(account.token, forHTTPHeaderField: "X-Plex-Token")
        }
        let data: Data
        let response: URLResponse
        do {
            // No redirect is followed (Machiya.swift's `NoRedirects`): a token stays on its service.
            (data, response) = try await session.data(for: request, delegate: NoRedirects())
        } catch {
            throw Failed()
        }
        guard let http = response as? HTTPURLResponse else { throw Failed() }
        guard (200..<300).contains(http.statusCode) else { throw Failed(status: http.statusCode) }
        let readable = data.contains { $0 < 0x20 && $0 != 0x0A && $0 != 0x0D && $0 != 0x09 } ? HisterClient.blankingControlCharacters(data) : data
        guard let json = try? JSONSerialization.jsonObject(with: readable) else {
            HisterClient.log.error("\(service.name, privacy: .public)'s reply wasn't JSON")
            throw Failed()
        }
        return json
    }

    func facts() async {
        func ask(_ service: MediaService, _ what: String, _ have: (MediaContext) -> Bool) async {
            guard let account = accounts[service], !have(context(service)) else { return }
            do {
                let reply = try await get(service, Media.requestURL(service, what, base: account.base))
                let f = Media.parseFacts(service, what, reply: reply)
                var c = context(service)
                if let user = f["user"] as? String { c.user = user }
                if let server = f["serverId"] as? String { c.serverId = server }
                if let machine = f["machine"] as? String { c.machine = machine }
                contexts[service] = c
                factStatus[service] = nil
            } catch {
                factStatus[service] = .some(error.status)
            }
        }
        async let movary: Void = ask(.movary, "me") { !$0.user.isEmpty }
        async let jellyfin: Void = ask(.jellyfin, "me") { !$0.user.isEmpty }
        async let plex: Void = ask(.plex, "identity") { !$0.machine.isEmpty }
        _ = await (movary, jellyfin, plex)
    }

    /// A list from one service; nil (and its failure noted) when it fails.
    func list(_ service: MediaService, _ what: String, _ args: MediaArgs, as parseAs: String? = nil) async -> (items: [MediaItem]?, failure: String?) {
        guard let account = accounts[service] else { return (nil, nil) }
        let url = Media.requestURL(service, what, base: account.base, args: args)
        guard !url.isEmpty else { return (nil, Media.failure(service, status: factStatus[service] ?? nil)) }
        do {
            let reply = try await get(service, url)
            return (Media.parse(service, parseAs ?? what, reply: reply, ctx: context(service)), nil)
        } catch {
            return (nil, Media.failure(service, status: error.status))
        }
    }

    /// A search across every service set up. One failing never fails the
    /// search. Searched on submit only.
    public func search(_ q: String) async -> MediaResults {
        let words = Media.words(q)
        guard !words.isEmpty, isConfigured else { return MediaResults() }
        await facts()
        async let jf = list(.jellyfin, "search", MediaArgs(q: words, limit: 40, user: context(.jellyfin).user))
        async let plex = list(.plex, "search", MediaArgs(q: words, limit: 10))
        async let koito = list(.koito, "search", MediaArgs(q: words))
        async let movary = list(.movary, "played", MediaArgs(q: words, limit: 30, user: context(.movary).user))
        let answers = await [jf, plex, koito, movary]
        var koitoItems = answers[2].items ?? []
        if !koitoItems.isEmpty, let account = accounts[.koito] {
            let counted = await withTaskGroup(of: (Int, Int?, Int?).self) { group in
                for (i, it) in koitoItems.prefix(Self.koitoCounts).enumerated() {
                    group.addTask {
                        let args = MediaArgs(kind: it.kind, id: it.sourceId)
                        guard let detail = try? await self.get(.koito, Media.requestURL(.koito, "item", base: account.base, args: args)),
                            let plays = Media.parseFacts(.koito, "item", reply: detail)["plays"] as? Int
                        else { return (i, nil, nil) }
                        guard plays > 0, let reply = try? await self.get(.koito, Media.requestURL(.koito, "last", base: account.base, args: args)) else {
                            return (i, plays, nil)
                        }
                        return (i, plays, Media.parseFacts(.koito, "last", reply: reply)["last"] as? Int)
                    }
                }
                var out: [(Int, Int?, Int?)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (i, plays, last) in counted {
                guard let plays else { continue }
                koitoItems[i].plays = plays
                if plays > 0 {
                    koitoItems[i].playedFrom = "koito"
                    if let last { koitoItems[i].last = last }
                }
            }
        }
        var asked: Set<MediaService> = []
        if answers[2].items != nil { asked.insert(.koito) }
        if answers[3].items != nil { asked.insert(.movary) }
        let items = Media.merge([answers[0].items ?? [], answers[1].items ?? [], koitoItems, answers[3].items ?? []], q: words, asked: asked)
        // What you don't own shows only when you played it (or Koito's count wasn't asked).
        return MediaResults(items: items.filter { $0.inLibrary || $0.plays != 0 }, failures: answers.compactMap(\.failure))
    }

    /// The Media tab before a search: what's playing, what you played and
    /// watched lately, your top artists, albums and tracks for `period`,
    /// your watchlist and what's new in your libraries.
    public func browse(period: String = "month") async -> MediaShelves {
        var shelves = MediaShelves()
        guard isConfigured else { return shelves }
        await facts()
        let p = Media.periods.contains(period) ? period : "month"
        shelves.period = p
        let movaryUser = context(.movary).user, jellyfinUser = context(.jellyfin).user
        async let now = list(.koito, "nowPlaying", MediaArgs())
        async let listens = list(.koito, "listens", MediaArgs(limit: 10))
        async let watched = list(.movary, "history", MediaArgs(limit: 10, user: movaryUser))
        async let artists = list(.koito, "top", MediaArgs(limit: 10, kind: "artists", period: p), as: "topArtists")
        async let albums = list(.koito, "top", MediaArgs(limit: 10, kind: "albums", period: p), as: "topAlbums")
        async let tracks = list(.koito, "top", MediaArgs(limit: 10, kind: "tracks", period: p), as: "topTracks")
        async let watchlist = list(.movary, "watchlist", MediaArgs(limit: 10, user: movaryUser))
        async let jfAdded = list(.jellyfin, "latest", MediaArgs(limit: 12, user: jellyfinUser))
        async let plexAdded = list(.plex, "recent", MediaArgs(limit: 12))
        let all = await [now, listens, watched, artists, albums, tracks, watchlist, jfAdded, plexAdded]
        shelves.nowPlaying = all[0].items ?? []
        shelves.listens = all[1].items ?? []
        shelves.watched = all[2].items ?? []
        shelves.artists = all[3].items ?? []
        shelves.albums = all[4].items ?? []
        shelves.tracks = all[5].items ?? []
        shelves.watchlist = all[6].items ?? []
        shelves.added = Array(Media.merge([all[7].items ?? [], all[8].items ?? []]).prefix(12))
        var seen: Set<String> = []
        shelves.failures = all.compactMap(\.failure).filter { seen.insert(String($0.prefix { $0 != " " })).inserted }
        return shelves
    }
}
